-- =============================================================================
-- Groups and membership
--
-- * groups.currency (CHAR(3)); group name 1..60 chars; server-set timestamps.
-- * group_members.status: 'pending' (asked to join with a code, waiting for the admin) or 'approved'.
--   Pending members are always viewers; the admin is always approved. Exactly one admin row per
--   group, and it matches groups.admin_id.
-- * group_bans: users removed by the admin cannot rejoin with the group code.
-- * Membership rows change ONLY through the RPCs below. A freeze trigger rejects any write to
--   group_members unless the transaction-local setting exevra.membership_rpc = 'on' (set by the RPCs)
--   or the row is removed by a foreign-key cascade (group or profile deleted). Direct table writes
--   are also revoked from client roles.
-- * Groups are created only through create_group(); clients may rename a group they administer and
--   nothing else. The invite code is not readable through the table.
-- * Read access (get_auth_user_groups and the policies built on it) is limited to APPROVED members.
--
-- Idempotent and safe on a database that already holds user data.
-- =============================================================================

-- Allow the cleanup statements below to touch membership rows when re-run after the freeze trigger
-- exists. Reset at the end of the migration.
SELECT pg_catalog.set_config('exevra.membership_rpc', 'on', false);

-- -----------------------------------------------------------------------------
-- groups: currency, name length, timestamps
-- -----------------------------------------------------------------------------
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS currency char(3);

UPDATE public.groups AS g
SET currency = COALESCE(
    (SELECT p.currency FROM public.profiles AS p
     WHERE p.id = g.admin_id AND public.is_supported_currency(p.currency::text)),
    'INR')
WHERE g.currency IS NULL OR NOT public.is_supported_currency(g.currency::text);

ALTER TABLE public.groups ALTER COLUMN currency SET DEFAULT 'INR';
ALTER TABLE public.groups ALTER COLUMN currency SET NOT NULL;
ALTER TABLE public.groups DROP CONSTRAINT IF EXISTS groups_currency_supported;
ALTER TABLE public.groups ADD CONSTRAINT groups_currency_supported
    CHECK (public.is_supported_currency(currency::text));

UPDATE public.groups
SET name = COALESCE(NULLIF(btrim(left(btrim(name), 60)), ''), 'Group')
WHERE name <> btrim(name) OR char_length(btrim(name)) NOT BETWEEN 1 AND 60;

ALTER TABLE public.groups DROP CONSTRAINT IF EXISTS groups_name_check;
ALTER TABLE public.groups DROP CONSTRAINT IF EXISTS groups_name_length;
ALTER TABLE public.groups ADD CONSTRAINT groups_name_length
    CHECK (name = btrim(name) AND char_length(name) BETWEEN 1 AND 60);

ALTER TABLE public.groups ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.groups ALTER COLUMN updated_at SET DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_groups_admin_id ON public.groups (admin_id);

-- -----------------------------------------------------------------------------
-- group_members: status, admin consistency
-- -----------------------------------------------------------------------------
ALTER TABLE public.group_members ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'approved';
ALTER TABLE public.group_members ALTER COLUMN joined_at SET DEFAULT now();

ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_status_check;
ALTER TABLE public.group_members ADD CONSTRAINT group_members_status_check
    CHECK (status IN ('pending', 'approved'));

-- The group's admin_id always has an approved admin membership row ...
INSERT INTO public.group_members (group_id, user_id, role, status, joined_at)
SELECT g.id, g.admin_id, 'admin', 'approved', g.created_at
FROM public.groups AS g
WHERE EXISTS (SELECT 1 FROM public.profiles AS p WHERE p.id = g.admin_id)
  AND NOT EXISTS (SELECT 1 FROM public.group_members AS gm WHERE gm.group_id = g.id AND gm.user_id = g.admin_id);

-- ... nobody else holds the admin role ...
UPDATE public.group_members AS gm
SET role = 'member'
FROM public.groups AS g
WHERE g.id = gm.group_id AND gm.role = 'admin' AND gm.user_id <> g.admin_id;

-- ... and the admin's row says so.
UPDATE public.group_members AS gm
SET role = 'admin', status = 'approved'
FROM public.groups AS g
WHERE g.id = gm.group_id AND gm.user_id = g.admin_id AND (gm.role <> 'admin' OR gm.status <> 'approved');

ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_pending_is_viewer;
ALTER TABLE public.group_members ADD CONSTRAINT group_members_pending_is_viewer
    CHECK (status = 'approved' OR role = 'viewer');

CREATE UNIQUE INDEX IF NOT EXISTS uq_group_members_one_admin
    ON public.group_members (group_id) WHERE role = 'admin';

-- Indexes: (group_id, user_id) is covered by the unique constraint.
DROP INDEX IF EXISTS public.idx_group_members_group;
CREATE INDEX IF NOT EXISTS idx_group_members_user ON public.group_members (user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_invited_by ON public.group_members (invited_by);

-- -----------------------------------------------------------------------------
-- group_bans
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.group_bans (
    group_id uuid NOT NULL REFERENCES public.groups (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    banned_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_bans_user ON public.group_bans (user_id);
CREATE INDEX IF NOT EXISTS idx_group_bans_banned_by ON public.group_bans (banned_by);
ALTER TABLE public.group_bans ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER so policies can use them without recursing into RLS)
-- -----------------------------------------------------------------------------

-- Groups in which the caller is an APPROVED member (any role, viewers included).
CREATE OR REPLACE FUNCTION public.get_auth_user_groups()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT gm.group_id
    FROM public.group_members AS gm
    WHERE gm.user_id = auth.uid() AND gm.status = 'approved';
$$;

-- The caller's role in a group if they are an approved member, else NULL.
CREATE OR REPLACE FUNCTION public.group_role(p_group_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT gm.role
    FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.user_id = auth.uid() AND gm.status = 'approved';
$$;

CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.groups AS g
        WHERE g.id = p_group_id AND g.admin_id = auth.uid()
    );
$$;

-- Successor rule shared by leave_group and account deletion: the longest-standing other approved
-- member (ties broken by user_id). NULL when there is none.
CREATE OR REPLACE FUNCTION public.pick_successor_admin(p_group_id uuid, p_excluding uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT gm.user_id
    FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id
      AND gm.status = 'approved'
      AND gm.user_id <> p_excluding
    ORDER BY gm.joined_at ASC, gm.user_id ASC
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_auth_user_groups() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.group_role(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_group_admin(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pick_successor_admin(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_auth_user_groups() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.group_role(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_group_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pick_successor_admin(uuid, uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- Membership freeze trigger
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
    -- Rows removed by an ON DELETE CASCADE (group or profile deleted) arrive from the FK trigger.
    IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'membership_rpc_only'
        USING ERRCODE = '42501', HINT = 'Group membership changes only through the membership RPCs.';
END;
$$;
REVOKE ALL ON FUNCTION public.group_members_freeze() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_group_members_freeze ON public.group_members;
CREATE TRIGGER trigger_group_members_freeze
    BEFORE INSERT OR UPDATE OR DELETE ON public.group_members
    FOR EACH ROW EXECUTE FUNCTION public.group_members_freeze();

-- Active-group repointing only considers approved memberships.
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
          AND gm.status = 'approved'
        ORDER BY gm.joined_at ASC, gm.group_id ASC
        LIMIT 1
    )
    WHERE p.id = OLD.user_id
      AND p.group_id = OLD.group_id;
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_member_removal() FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Privileges and RLS
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.groups FROM anon, authenticated;
GRANT SELECT (id, name, admin_id, currency, created_at, updated_at) ON TABLE public.groups TO authenticated;
GRANT UPDATE (name) ON TABLE public.groups TO authenticated;
GRANT DELETE ON TABLE public.groups TO authenticated;
GRANT ALL ON TABLE public.groups TO service_role;

REVOKE ALL ON TABLE public.group_members FROM anon, authenticated;
GRANT SELECT ON TABLE public.group_members TO authenticated;
GRANT ALL ON TABLE public.group_members TO service_role;

REVOKE ALL ON TABLE public.group_bans FROM anon, authenticated;
GRANT SELECT ON TABLE public.group_bans TO authenticated;
GRANT ALL ON TABLE public.group_bans TO service_role;

-- groups
DROP POLICY IF EXISTS "Members can view their group" ON public.groups;
DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.groups;
DROP POLICY IF EXISTS "Only admin can update group" ON public.groups;
DROP POLICY IF EXISTS "Only admin can delete group" ON public.groups;
DROP POLICY IF EXISTS groups_select_member ON public.groups;
DROP POLICY IF EXISTS groups_update_admin ON public.groups;
DROP POLICY IF EXISTS groups_delete_admin ON public.groups;

CREATE POLICY groups_select_member ON public.groups
    FOR SELECT TO authenticated
    USING (id IN (SELECT public.get_auth_user_groups()));

CREATE POLICY groups_update_admin ON public.groups
    FOR UPDATE TO authenticated
    USING (admin_id = (SELECT auth.uid()))
    WITH CHECK (admin_id = (SELECT auth.uid()));

CREATE POLICY groups_delete_admin ON public.groups
    FOR DELETE TO authenticated
    USING (admin_id = (SELECT auth.uid()));

-- group_members: own rows; approved rows of groups the caller belongs to; pending rows for the admin.
DROP POLICY IF EXISTS "Members can view group membership" ON public.group_members;
DROP POLICY IF EXISTS "Users can join or admins can add members" ON public.group_members;
DROP POLICY IF EXISTS "Admins can add group members" ON public.group_members;
DROP POLICY IF EXISTS "Users can leave or admins can remove members" ON public.group_members;
DROP POLICY IF EXISTS "Admins can update group member roles" ON public.group_members;
DROP POLICY IF EXISTS group_members_select ON public.group_members;

CREATE POLICY group_members_select ON public.group_members
    FOR SELECT TO authenticated
    USING (
        user_id = (SELECT auth.uid())
        OR (status = 'approved' AND group_id IN (SELECT public.get_auth_user_groups()))
        OR public.is_group_admin(group_id)
    );

-- group_bans: visible to the group admin only.
DROP POLICY IF EXISTS group_bans_select_admin ON public.group_bans;
CREATE POLICY group_bans_select_admin ON public.group_bans
    FOR SELECT TO authenticated
    USING (public.is_group_admin(group_id));

-- -----------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------

-- Creates a group with the caller as its approved admin and makes it the caller's active group.
CREATE OR REPLACE FUNCTION public.create_group(p_name text, p_currency text DEFAULT NULL)
RETURNS public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_name text := btrim(p_name);
    v_currency text := upper(btrim(p_currency));
    v_group public.groups%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 1 AND 60 THEN
        RAISE EXCEPTION 'invalid_group_name' USING ERRCODE = '22023';
    END IF;
    IF v_currency IS NULL OR v_currency = '' THEN
        SELECT p.currency::text INTO v_currency FROM public.profiles AS p WHERE p.id = v_uid;
        v_currency := COALESCE(v_currency, 'INR');
    END IF;
    IF NOT public.is_supported_currency(v_currency) THEN
        RAISE EXCEPTION 'invalid_currency' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.profiles AS p WHERE p.id = v_uid) THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.groups (name, admin_id, currency)
    VALUES (v_name, v_uid, v_currency)
    RETURNING * INTO v_group;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    INSERT INTO public.group_members (group_id, user_id, role, status)
    VALUES (v_group.id, v_uid, 'admin', 'approved');
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    UPDATE public.profiles SET group_id = v_group.id WHERE id = v_uid;

    RETURN v_group;
END;
$$;

-- Approves a pending member (admin only). p_role: 'member' (default) or 'viewer'.
CREATE OR REPLACE FUNCTION public.approve_member(p_group_id uuid, p_user_id uuid, p_role text DEFAULT 'member')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_member public.group_members%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_group_admin(p_group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;
    IF p_role IS NULL OR p_role NOT IN ('member', 'viewer') THEN
        RAISE EXCEPTION 'invalid_role' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_member FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'member_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_member.status <> 'pending' THEN
        RAISE EXCEPTION 'member_not_pending' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    UPDATE public.group_members
    SET status = 'approved', role = p_role, joined_at = now()
    WHERE id = v_member.id;
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    RETURN jsonb_build_object('group_id', p_group_id, 'user_id', p_user_id, 'role', p_role, 'status', 'approved');
END;
$$;

-- Removes a member or rejects a pending request (admin only) and bans the user from rejoining with
-- the group code. A later invitation from the admin lifts the ban.
CREATE OR REPLACE FUNCTION public.remove_member(p_group_id uuid, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_group_admin(p_group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;
    IF p_user_id = v_uid THEN
        RAISE EXCEPTION 'cannot_remove_self' USING ERRCODE = 'P0001', HINT = 'Use leave_group.';
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    DELETE FROM public.group_members WHERE group_id = p_group_id AND user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'member_not_found' USING ERRCODE = 'P0002';
    END IF;
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    INSERT INTO public.group_bans (group_id, user_id, banned_by)
    VALUES (p_group_id, p_user_id, v_uid)
    ON CONFLICT (group_id, user_id) DO UPDATE SET banned_by = EXCLUDED.banned_by, created_at = now();

    -- Pending invitations to the removed user for this group are withdrawn.
    UPDATE public.group_invitations AS gi
    SET status = 'revoked'
    FROM auth.users AS u
    WHERE u.id = p_user_id
      AND gi.group_id = p_group_id
      AND gi.status = 'pending'
      AND gi.email = lower(u.email);

    RETURN jsonb_build_object('group_id', p_group_id, 'user_id', p_user_id, 'removed', true);
END;
$$;

-- Leaves a group. If the caller is the admin, admin passes to the longest-standing other approved
-- member; if there is none, the group and all its data are deleted.
CREATE OR REPLACE FUNCTION public.leave_group(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_group public.groups%ROWTYPE;
    v_member public.group_members%ROWTYPE;
    v_successor uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_group FROM public.groups AS g WHERE g.id = p_group_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'group_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_member FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.user_id = v_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'not_group_member' USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);

    IF v_group.admin_id = v_uid THEN
        v_successor := public.pick_successor_admin(p_group_id, v_uid);
        IF v_successor IS NULL THEN
            DELETE FROM public.groups WHERE id = p_group_id;
            PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);
            RETURN jsonb_build_object('group_id', p_group_id, 'left', true, 'group_deleted', true, 'new_admin_id', NULL);
        END IF;

        DELETE FROM public.group_members WHERE id = v_member.id;
        UPDATE public.group_members SET role = 'admin'
        WHERE group_id = p_group_id AND user_id = v_successor;
        UPDATE public.groups SET admin_id = v_successor WHERE id = p_group_id;
    ELSE
        DELETE FROM public.group_members WHERE id = v_member.id;
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);
    RETURN jsonb_build_object('group_id', p_group_id, 'left', true, 'group_deleted', false, 'new_admin_id', v_successor);
END;
$$;

-- Hands the admin role to another approved member (admin only). The caller becomes a member.
CREATE OR REPLACE FUNCTION public.transfer_admin(p_group_id uuid, p_new_admin uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_target public.group_members%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    PERFORM 1 FROM public.groups AS g WHERE g.id = p_group_id FOR UPDATE;
    IF NOT public.is_group_admin(p_group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;
    IF p_new_admin IS NULL OR p_new_admin = v_uid THEN
        RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_target FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.user_id = p_new_admin
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'member_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_target.status <> 'approved' THEN
        RAISE EXCEPTION 'member_pending' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    UPDATE public.group_members SET role = 'member' WHERE group_id = p_group_id AND user_id = v_uid;
    UPDATE public.group_members SET role = 'admin' WHERE id = v_target.id;
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    UPDATE public.groups SET admin_id = p_new_admin WHERE id = p_group_id;

    RETURN jsonb_build_object('group_id', p_group_id, 'admin_id', p_new_admin);
END;
$$;

-- Changes an approved member's role between 'member' and 'viewer' (admin only). The admin role is
-- only ever moved with transfer_admin.
CREATE OR REPLACE FUNCTION public.set_member_role(p_group_id uuid, p_user_id uuid, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_target public.group_members%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_group_admin(p_group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;
    IF p_role IS NULL OR p_role NOT IN ('member', 'viewer') THEN
        RAISE EXCEPTION 'invalid_role' USING ERRCODE = '22023', HINT = 'Use transfer_admin to change the admin.';
    END IF;
    IF p_user_id = v_uid THEN
        RAISE EXCEPTION 'cannot_change_own_role' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_target FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'member_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_target.status <> 'approved' THEN
        RAISE EXCEPTION 'member_pending' USING ERRCODE = 'P0001', HINT = 'Use approve_member.';
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    UPDATE public.group_members SET role = p_role WHERE id = v_target.id;
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    RETURN jsonb_build_object('group_id', p_group_id, 'user_id', p_user_id, 'role', p_role);
END;
$$;

-- Sets the caller's active group. NULL switches to personal mode.
CREATE OR REPLACE FUNCTION public.set_active_group(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_group_id IS NOT NULL AND public.group_role(p_group_id) IS NULL THEN
        RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501';
    END IF;

    UPDATE public.profiles SET group_id = p_group_id WHERE id = v_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;

    RETURN jsonb_build_object('group_id', p_group_id);
END;
$$;

-- Member directory for a group the caller belongs to (approved). Never exposes email.
-- Pending requests are listed for the admin only.
CREATE OR REPLACE FUNCTION public.get_group_members(p_group_id uuid)
RETURNS TABLE (
    user_id uuid,
    display_name text,
    avatar_url text,
    role text,
    status text,
    joined_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_is_admin boolean;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF public.group_role(p_group_id) IS NULL THEN
        RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501';
    END IF;
    v_is_admin := public.is_group_admin(p_group_id);

    RETURN QUERY
    SELECT gm.user_id, p.display_name, p.avatar_url, gm.role, gm.status, gm.joined_at
    FROM public.group_members AS gm
    JOIN public.profiles AS p ON p.id = gm.user_id
    WHERE gm.group_id = p_group_id
      AND (gm.status = 'approved' OR v_is_admin)
    ORDER BY (gm.role = 'admin') DESC, (gm.status = 'pending') ASC, gm.joined_at ASC, gm.user_id ASC;
END;
$$;

-- The old approval RPC is replaced by approve_member.
DROP FUNCTION IF EXISTS public.approve_group_member(uuid, uuid);

DO $$
DECLARE
    v_sig text;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'public.create_group(text, text)',
        'public.approve_member(uuid, uuid, text)',
        'public.remove_member(uuid, uuid)',
        'public.leave_group(uuid)',
        'public.transfer_admin(uuid, uuid)',
        'public.set_member_role(uuid, uuid, text)',
        'public.set_active_group(uuid)',
        'public.get_group_members(uuid)'
    ] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_sig);
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- Realtime
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_publication_tables
           WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'group_members'
       ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
    END IF;
END;
$$;

SELECT pg_catalog.set_config('exevra.membership_rpc', 'off', false);
