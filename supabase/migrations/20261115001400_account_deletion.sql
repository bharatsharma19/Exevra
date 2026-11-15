-- =============================================================================
-- Account deletion
--
-- prepare_account_deletion(p_user_id) -> jsonb   (SECURITY DEFINER, EXECUTE for service_role only)
--   Run by the delete-account Edge Function before auth.admin.deleteUser(p_user_id):
--   1. the user's pending settlements (as payer or payee) in every group that is kept are voided
--      with reason 'account_deleted', before any membership changes (the departure trigger on
--      group_members, 20261115001000, uses the same reason for anything left);
--   2. every group the user administers passes to the longest-standing other approved member
--      (pick_successor_admin, the same rule as leave_group); a group with no other approved member
--      is deleted with all its data;
--   3. the user's memberships, bans, personal expenses (group_id IS NULL), AI usage events, AI
--      reports, invitations they sent or that were addressed to their email, invite-code attempts and
--      profile are deleted.
--   Group expenses they paid, their split rows and settlements stay; when the auth user is deleted
--   the foreign keys set the user columns to NULL and balances show them as 'Former member'.
--   Every group the user belongs to or administers is locked first (the same group-row lock the
--   membership RPCs take), so the admin hand-over cannot interleave with them.
--   Idempotent: a second call finds nothing left to change and returns zero counts. When there is no
--   auth user with that id any more (already deleted, e.g. a delete-account retry after
--   auth.admin.deleteUser succeeded), it changes nothing and returns the same shape with zero counts
--   and already_deleted = true; otherwise already_deleted is false.
--
-- A BEFORE DELETE trigger on auth.users runs the same function, so deleting a user by any path
-- (dashboard, admin API without the Edge Function) never takes other members' data with it.
-- The function also marks the transaction (exevra.account_deletion = 'on'): only then may the foreign
-- key clear the payer of a group expense (expenses_payer_guard, 20261115000800).
--
-- delete_user_account() (client-callable, deleted auth.users directly) is dropped.
-- =============================================================================

DROP FUNCTION IF EXISTS public.delete_user_account();

-- -----------------------------------------------------------------------------
-- Membership freeze: also let a foreign-key action clear invited_by (inviter's profile deleted).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.group_members_freeze()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF COALESCE(current_setting('exevra.membership_rpc', true), '') = 'on' THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    -- Changes made by a foreign-key action arrive one trigger level down: rows removed by
    -- ON DELETE CASCADE (group or profile deleted) and invited_by cleared by ON DELETE SET NULL.
    IF pg_trigger_depth() > 1 THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        IF TG_OP = 'UPDATE' AND NEW.invited_by IS NULL
           AND (NEW.id, NEW.group_id, NEW.user_id, NEW.role, NEW.status, NEW.joined_at)
               IS NOT DISTINCT FROM (OLD.id, OLD.group_id, OLD.user_id, OLD.role, OLD.status, OLD.joined_at) THEN
            RETURN NEW;
        END IF;
    END IF;
    RAISE EXCEPTION 'membership_rpc_only'
        USING ERRCODE = '42501', HINT = 'Group membership changes only through the membership RPCs.';
END;
$$;
REVOKE ALL ON FUNCTION public.group_members_freeze() FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- prepare_account_deletion
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prepare_account_deletion(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_emails text[];
    v_group_id uuid;
    v_successor uuid;
    v_transferred jsonb := '[]'::jsonb;
    v_deleted_groups jsonb := '[]'::jsonb;
    v_settlement public.settlements;
    v_voided integer := 0;
    v_memberships integer := 0;
    v_rows integer;
    v_personal integer;
    v_usage integer;
    v_reports integer;
    v_invitations integer;
    v_profile integer;
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users AS u WHERE u.id = p_user_id) THEN
        -- Already deleted: the foreign keys removed or anonymised everything when the auth user went.
        RETURN pg_catalog.jsonb_build_object(
            'user_id', p_user_id,
            'admin_transferred', '[]'::jsonb,
            'groups_deleted', '[]'::jsonb,
            'settlements_voided', 0,
            'memberships_removed', 0,
            'personal_expenses_deleted', 0,
            'ai_usage_events_deleted', 0,
            'ai_reports_deleted', 0,
            'invitations_deleted', 0,
            'profile_deleted', false,
            'already_deleted', true
        );
    END IF;

    -- One deletion at a time per user (Edge Function retry racing the auth trigger).
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exevra.account_deletion:' || p_user_id::text, 0));
    -- Kept until the end of the transaction: the auth user's foreign-key actions run after this
    -- function returns (BEFORE DELETE trigger on auth.users).
    PERFORM pg_catalog.set_config('exevra.account_deletion', 'on', true);
    PERFORM pg_catalog.set_config('exevra.departure_reason', 'account_deleted', true);

    SELECT pg_catalog.array_agg(DISTINCT pg_catalog.lower(pg_catalog.btrim(x.email)))
    INTO v_emails
    FROM (SELECT u.email FROM auth.users AS u WHERE u.id = p_user_id
          UNION ALL
          SELECT p.email FROM public.profiles AS p WHERE p.id = p_user_id) AS x
    WHERE x.email IS NOT NULL;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);

    -- Lock every group the user belongs to or administers (in id order) before changing anything, so
    -- a concurrent membership RPC on one of them (for example transfer_admin to this user) either
    -- finishes first or waits; admin_id is re-read below after the locks are held.
    PERFORM 1 FROM public.groups AS g
    WHERE g.admin_id = p_user_id
       OR g.id IN (SELECT gm.group_id FROM public.group_members AS gm WHERE gm.user_id = p_user_id)
    ORDER BY g.id
    FOR UPDATE;

    -- 1. Pending settlements can no longer be confirmed by (or for) this user. Done before any
    --    membership is removed, so the count covers every group that is kept (a group deleted in
    --    step 2 takes its settlements with it).
    FOR v_settlement IN
        SELECT * FROM public.settlements AS s
        WHERE s.status = 'pending'
          AND s.group_id NOT IN (SELECT g.id FROM public.groups AS g
                                 WHERE g.admin_id = p_user_id
                                   AND public.pick_successor_admin(g.id, p_user_id) IS NULL)
          AND (s.from_user = p_user_id OR s.to_user = p_user_id)
        ORDER BY s.created_at, s.id
        FOR UPDATE
    LOOP
        UPDATE public.settlements AS s
        SET status = 'voided', voided_at = pg_catalog.now(), voided_by = p_user_id, void_reason = 'account_deleted'
        WHERE s.id = v_settlement.id;
        INSERT INTO public.settlement_events (settlement_id, group_id, actor, action, details)
        VALUES (v_settlement.id, v_settlement.group_id, p_user_id, 'voided',
                pg_catalog.jsonb_build_object('previous_status', 'pending', 'reason', 'account_deleted'));
        v_voided := v_voided + 1;
    END LOOP;

    -- 2. Groups the user administers.
    FOR v_group_id IN
        SELECT g.id FROM public.groups AS g
        WHERE g.admin_id = p_user_id
        ORDER BY g.created_at, g.id
    LOOP
        v_successor := public.pick_successor_admin(v_group_id, p_user_id);
        IF v_successor IS NULL THEN
            DELETE FROM public.groups AS g WHERE g.id = v_group_id;
            v_deleted_groups := v_deleted_groups || pg_catalog.to_jsonb(v_group_id);
        ELSE
            DELETE FROM public.group_members AS gm WHERE gm.group_id = v_group_id AND gm.user_id = p_user_id;
            GET DIAGNOSTICS v_rows = ROW_COUNT;
            v_memberships := v_memberships + v_rows;
            UPDATE public.group_members AS gm SET role = 'admin'
            WHERE gm.group_id = v_group_id AND gm.user_id = v_successor;
            UPDATE public.groups AS g SET admin_id = v_successor WHERE g.id = v_group_id;
            v_transferred := v_transferred
                || pg_catalog.jsonb_build_object('group_id', v_group_id, 'new_admin_id', v_successor);
        END IF;
    END LOOP;

    -- 3. Personal data.
    DELETE FROM public.group_members AS gm WHERE gm.user_id = p_user_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_memberships := v_memberships + v_rows;
    DELETE FROM public.group_bans AS b WHERE b.user_id = p_user_id;
    DELETE FROM public.expenses AS e WHERE e.user_id = p_user_id AND e.group_id IS NULL;
    GET DIAGNOSTICS v_personal = ROW_COUNT;
    DELETE FROM public.ai_usage_events AS e WHERE e.user_id = p_user_id;
    GET DIAGNOSTICS v_usage = ROW_COUNT;
    DELETE FROM public.ai_reports AS r WHERE r.user_id = p_user_id;
    GET DIAGNOSTICS v_reports = ROW_COUNT;
    DELETE FROM public.group_invitations AS i
    WHERE i.inviter_id = p_user_id OR i.email = ANY (COALESCE(v_emails, '{}'::text[]));
    GET DIAGNOSTICS v_invitations = ROW_COUNT;
    DELETE FROM public.invite_code_attempts AS a WHERE a.user_id = p_user_id;
    DELETE FROM public.profiles AS p WHERE p.id = p_user_id;
    GET DIAGNOSTICS v_profile = ROW_COUNT;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    RETURN pg_catalog.jsonb_build_object(
        'user_id', p_user_id,
        'admin_transferred', v_transferred,
        'groups_deleted', v_deleted_groups,
        'settlements_voided', v_voided,
        'memberships_removed', v_memberships,
        'personal_expenses_deleted', v_personal,
        'ai_usage_events_deleted', v_usage,
        'ai_reports_deleted', v_reports,
        'invitations_deleted', v_invitations,
        'profile_deleted', v_profile > 0,
        'already_deleted', false
    );
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- Safety net: any deletion of an auth user prepares the account first.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_auth_user_deleted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM public.prepare_account_deletion(OLD.id);
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_auth_user_deleted() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_deleted ON auth.users;
CREATE TRIGGER on_auth_user_deleted
    BEFORE DELETE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_auth_user_deleted();
