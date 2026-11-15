-- =============================================================================
-- Function hardening
--
-- Recreates every function from the baseline with:
--   * `SET search_path = ''` as a function attribute (not a statement in the body), so callers cannot
--     influence name resolution and the setting never leaks into the caller's session;
--   * fully qualified object names (public.*, auth.*, extensions.*);
--   * pgcrypto referenced through the `extensions` schema, where Supabase installs it;
--   * deterministic ordering where a single row is picked;
--   * explicit EXECUTE privileges: nothing for PUBLIC/anon, only the roles that need it.
--
-- Behaviour is otherwise unchanged except for small safety fixes: errors carry SQLSTATEs, a
-- membership is never role-changed through ON CONFLICT, approving a non-pending member raises, the
-- group invite code is only returned to the group admin, and leaving a group never moves a user
-- who is in personal mode into another group. Later migrations replace several of these functions.
-- Idempotent: CREATE OR REPLACE + REVOKE/GRANT.
-- =============================================================================

-- New functions created by `postgres` in `public` must not be executable by `anon` by default.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;

-- -----------------------------------------------------------------------------
-- Trigger functions
-- -----------------------------------------------------------------------------

-- updated_at maintenance needs no elevated rights.
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- When a membership row is deleted, a profile whose active group was that group is pointed at the
-- user's oldest remaining membership (deterministic order), or NULL (personal mode).
CREATE OR REPLACE FUNCTION public.handle_member_removal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public.profiles AS p
    SET group_id = (
        SELECT gm.group_id
        FROM public.group_members AS gm
        WHERE gm.user_id = OLD.user_id
          AND gm.group_id <> OLD.group_id
        ORDER BY gm.joined_at ASC, gm.group_id ASC
        LIMIT 1
    )
    WHERE p.id = OLD.user_id
      AND p.group_id = OLD.group_id;
    RETURN OLD;
END;
$$;

-- Creates (or refreshes) the profile row for a new auth user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, email, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(
            NULLIF(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''),
            NULLIF(btrim(NEW.raw_user_meta_data ->> 'name'), ''),
            NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
            'User'
        ),
        NEW.email,
        NEW.raw_user_meta_data ->> 'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- RLS helper
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_auth_user_groups()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT gm.group_id FROM public.group_members AS gm WHERE gm.user_id = auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- RPCs (same behaviour as the baseline; replaced by later migrations)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_group_by_invite(p_invite_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_group public.groups%ROWTYPE;
    v_user_id uuid := auth.uid();
    v_role text;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_group FROM public.groups AS g
    WHERE lower(g.invite_code) = lower(btrim(p_invite_code));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid invite code' USING ERRCODE = 'P0002';
    END IF;

    v_role := CASE WHEN v_group.admin_id = v_user_id THEN 'admin' ELSE 'member' END;

    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_group.id, v_user_id, v_role)
    ON CONFLICT (group_id, user_id) DO UPDATE SET role = EXCLUDED.role;

    UPDATE public.profiles SET group_id = v_group.id WHERE id = v_user_id;

    RETURN jsonb_build_object('success', true, 'group_id', v_group.id, 'group_name', v_group.name, 'role', v_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_group_invitation(p_group_id uuid, p_email text, p_role text DEFAULT 'member')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_inviter_role text;
    v_invitation public.group_invitations%ROWTYPE;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT gm.role INTO v_inviter_role FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.user_id = v_user_id;

    IF v_inviter_role IS NULL OR v_inviter_role NOT IN ('admin', 'member') THEN
        RAISE EXCEPTION 'Only active group members and admins can send invitations' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.group_invitations (group_id, inviter_id, email, role, token, status, expires_at)
    VALUES (
        p_group_id,
        v_user_id,
        btrim(lower(p_email)),
        CASE WHEN p_role IN ('admin', 'member', 'viewer') THEN p_role ELSE 'member' END,
        encode(extensions.gen_random_bytes(24), 'hex'),
        'pending',
        now() + interval '7 days'
    )
    RETURNING * INTO v_invitation;

    RETURN jsonb_build_object(
        'success', true,
        'invitation_id', v_invitation.id,
        'group_id', v_invitation.group_id,
        'email', v_invitation.email,
        'role', v_invitation.role,
        'token', v_invitation.token,
        'status', v_invitation.status,
        'expires_at', v_invitation.expires_at
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_invitation_details(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_invite record;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT gi.*, g.name AS group_name, p.display_name AS inviter_name
    INTO v_invite
    FROM public.group_invitations AS gi
    JOIN public.groups AS g ON g.id = gi.group_id
    JOIN public.profiles AS p ON p.id = gi.inviter_id
    WHERE gi.token = btrim(p_token);

    IF NOT FOUND THEN
        RETURN jsonb_build_object('valid', false, 'error', 'Invalid invitation token');
    END IF;

    RETURN jsonb_build_object(
        'valid', true,
        'invitation_id', v_invite.id,
        'group_id', v_invite.group_id,
        'group_name', v_invite.group_name,
        'inviter_name', v_invite.inviter_name,
        'email', v_invite.email,
        'role', v_invite.role,
        'status', CASE WHEN v_invite.expires_at < now() AND v_invite.status = 'pending' THEN 'expired' ELSE v_invite.status END,
        'expires_at', v_invite.expires_at
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_group_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_invite public.group_invitations%ROWTYPE;
    v_group public.groups%ROWTYPE;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_invite FROM public.group_invitations AS gi WHERE gi.token = btrim(p_token) FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid invitation token' USING ERRCODE = 'P0002';
    END IF;

    IF v_invite.status = 'accepted' THEN
        RAISE EXCEPTION 'Invitation has already been accepted';
    ELSIF v_invite.status IN ('revoked', 'declined') THEN
        RAISE EXCEPTION 'Invitation is no longer valid';
    ELSIF v_invite.status = 'expired' OR v_invite.expires_at < now() THEN
        RAISE EXCEPTION 'Invitation has expired';
    END IF;

    SELECT * INTO v_group FROM public.groups AS g WHERE g.id = v_invite.group_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group no longer exists' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.group_members (group_id, user_id, role, invited_by)
    VALUES (v_invite.group_id, v_user_id, v_invite.role, v_invite.inviter_id)
    ON CONFLICT (group_id, user_id) DO NOTHING;

    UPDATE public.profiles SET group_id = v_invite.group_id WHERE id = v_user_id;

    UPDATE public.group_invitations SET status = 'accepted', accepted_at = now() WHERE id = v_invite.id;

    RETURN jsonb_build_object('success', true, 'group_id', v_group.id, 'group_name', v_group.name, 'role', v_invite.role);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_settlement(p_group_id uuid, p_payee_id uuid, p_amount numeric, p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_settlement public.settlements%ROWTYPE;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    IF v_user_id = p_payee_id THEN
        RAISE EXCEPTION 'Payer and payee cannot be the same user' USING ERRCODE = '22023';
    END IF;
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Settlement amount must be positive' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.group_members AS gm WHERE gm.group_id = p_group_id AND gm.user_id = v_user_id)
       OR NOT EXISTS (SELECT 1 FROM public.group_members AS gm WHERE gm.group_id = p_group_id AND gm.user_id = p_payee_id) THEN
        RAISE EXCEPTION 'Both parties must be members of the group to settle' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.settlements (group_id, payer_id, payee_id, amount, notes)
    VALUES (p_group_id, v_user_id, p_payee_id, p_amount, p_notes)
    RETURNING * INTO v_settlement;

    RETURN jsonb_build_object(
        'success', true,
        'settlement_id', v_settlement.id,
        'group_id', v_settlement.group_id,
        'payer_id', v_settlement.payer_id,
        'payee_id', v_settlement.payee_id,
        'amount', v_settlement.amount,
        'date', v_settlement.date
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_groups()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_groups jsonb;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_agg(group_row ORDER BY group_row.created_at DESC, group_row.id)
    INTO v_groups
    FROM (
        SELECT g.id, g.name,
               CASE WHEN g.admin_id = v_user_id THEN g.invite_code END AS invite_code,
               g.admin_id, g.created_at, gm.role,
               (SELECT count(*) FROM public.group_members AS m WHERE m.group_id = g.id) AS members_count
        FROM public.group_members AS gm
        JOIN public.groups AS g ON g.id = gm.group_id
        WHERE gm.user_id = v_user_id
    ) AS group_row;

    RETURN COALESCE(v_groups, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_group_member(p_group_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_admin_id uuid := auth.uid();
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.groups AS g WHERE g.id = p_group_id AND g.admin_id = v_admin_id) THEN
        RAISE EXCEPTION 'Only the group admin can review and approve members' USING ERRCODE = '42501';
    END IF;

    UPDATE public.group_members SET role = 'member'
    WHERE group_id = p_group_id AND user_id = p_user_id AND role = 'viewer';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No pending member found' USING ERRCODE = 'P0002';
    END IF;
    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_expense_insights(p_timeframe text DEFAULT 'monthly', p_group_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_start_date timestamptz;
    v_total numeric(12, 2) := 0;
    v_count int := 0;
    v_categories jsonb := '[]'::jsonb;
    v_trends jsonb := '[]'::jsonb;
    v_highest jsonb := '{}'::jsonb;
    v_avg_daily numeric(12, 2) := 0;
    v_days_count int := 30;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    IF p_group_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.group_members AS gm WHERE gm.group_id = p_group_id AND gm.user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not authorized to view this group''s insights' USING ERRCODE = '42501';
    END IF;

    IF p_timeframe = 'weekly' THEN
        v_start_date := now() - interval '7 days';
        v_days_count := 7;
    ELSIF p_timeframe = 'yearly' THEN
        v_start_date := now() - interval '365 days';
        v_days_count := 365;
    ELSE
        v_start_date := now() - interval '30 days';
        v_days_count := 30;
    END IF;

    SELECT COALESCE(sum(e.amount), 0), count(*)
    INTO v_total, v_count
    FROM public.expenses AS e
    WHERE e.date >= v_start_date
      AND ((p_group_id IS NULL AND e.group_id IS NULL AND e.user_id = v_user_id)
           OR (p_group_id IS NOT NULL AND e.group_id = p_group_id));

    IF v_days_count > 0 THEN
        v_avg_daily := round(v_total / v_days_count, 2);
    END IF;

    SELECT jsonb_build_object('id', e.id, 'title', e.title, 'amount', e.amount, 'category', e.category, 'date', e.date)
    INTO v_highest
    FROM public.expenses AS e
    WHERE e.date >= v_start_date
      AND ((p_group_id IS NULL AND e.group_id IS NULL AND e.user_id = v_user_id)
           OR (p_group_id IS NOT NULL AND e.group_id = p_group_id))
    ORDER BY e.amount DESC, e.id
    LIMIT 1;

    SELECT jsonb_agg(cat_row)
    INTO v_categories
    FROM (
        SELECT e.category,
               sum(e.amount) AS total,
               count(*) AS count,
               CASE WHEN v_total > 0 THEN round((sum(e.amount) / v_total) * 100, 2) ELSE 0 END AS percentage
        FROM public.expenses AS e
        WHERE e.date >= v_start_date
          AND ((p_group_id IS NULL AND e.group_id IS NULL AND e.user_id = v_user_id)
               OR (p_group_id IS NOT NULL AND e.group_id = p_group_id))
        GROUP BY e.category
        ORDER BY total DESC
    ) AS cat_row;

    SELECT jsonb_agg(trend_row)
    INTO v_trends
    FROM (
        SELECT to_char(e.date, CASE WHEN p_timeframe = 'yearly' THEN 'Mon YYYY' ELSE 'YYYY-MM-DD' END) AS label,
               date_trunc(CASE WHEN p_timeframe = 'yearly' THEN 'month' ELSE 'day' END, e.date) AS point_date,
               sum(e.amount) AS total,
               count(*) AS count
        FROM public.expenses AS e
        WHERE e.date >= v_start_date
          AND ((p_group_id IS NULL AND e.group_id IS NULL AND e.user_id = v_user_id)
               OR (p_group_id IS NOT NULL AND e.group_id = p_group_id))
        GROUP BY 1, 2
        ORDER BY point_date ASC
    ) AS trend_row;

    RETURN jsonb_build_object(
        'timeframe', p_timeframe,
        'total_amount', v_total,
        'expense_count', v_count,
        'average_daily', v_avg_daily,
        'highest_expense', COALESCE(v_highest, '{}'::jsonb),
        'category_breakdown', COALESCE(v_categories, '[]'::jsonb),
        'trend_data', COALESCE(v_trends, '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;
    DELETE FROM public.groups WHERE admin_id = v_user_id;
    DELETE FROM public.profiles WHERE id = v_user_id;
    DELETE FROM auth.users WHERE id = v_user_id;
    RETURN true;
END;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
-- Trigger functions are never called directly.
REVOKE ALL ON FUNCTION public.handle_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_member_removal() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- RLS helper: evaluated inside policies as the querying role.
REVOKE ALL ON FUNCTION public.get_auth_user_groups() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_groups() TO authenticated, service_role;

DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'public.join_group_by_invite(text)',
        'public.create_group_invitation(uuid, text, text)',
        'public.get_invitation_details(text)',
        'public.accept_group_invitation(text)',
        'public.record_settlement(uuid, uuid, numeric, text)',
        'public.get_user_groups()',
        'public.approve_group_member(uuid, uuid)',
        'public.get_expense_insights(text, uuid)',
        'public.delete_user_account()'
    ] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_sig);
    END LOOP;
END;
$$;
