-- =============================================================================
-- Email invitations
--
-- * Only the group admin invites; invited role is 'member' or 'viewer'.
-- * The server creates a 256-bit random token, returns it once, and stores only its SHA-256 hash.
-- * Details, accept and decline are bound to the caller's confirmed account email.
-- * Clients have no direct INSERT/UPDATE/DELETE on group_invitations; admins can list the group's
--   pending, unexpired invitations (without the hash).
-- * An invitation is valid only while its inviter is the group admin: transfer_admin and leave_group
--   revoke the outgoing admin's pending invitations, and accept/details treat any other pending
--   invitation as revoked.
-- * Rate limits (P0001 rate_limited): 20 invitations per inviter per hour; 5 per inviter and recipient
--   email per day; and an address can be invited by at most 10 different inviters per day. Counting
--   distinct inviters (rather than all invitations to an address) means no single account can use
--   up an address's allowance and keep other groups from inviting it.
-- * purge_old_invitations() removes answered/expired invitations after 90 days.
--
-- Idempotent and safe on a database that already holds user data: legacy tokens are hashed, legacy
-- admin invitations become member invitations, malformed emails are removed, and pending invitations
-- that were not sent by the group's admin (the old policy let members invite) are revoked.
-- =============================================================================

-- Functions whose signature or return type changes are dropped first.
DROP FUNCTION IF EXISTS public.create_group_invitation(uuid, text, text);
DROP FUNCTION IF EXISTS public.get_invitation_details(text);
DROP FUNCTION IF EXISTS public.accept_group_invitation(text);

-- -----------------------------------------------------------------------------
-- Table changes
-- -----------------------------------------------------------------------------
ALTER TABLE public.group_invitations ADD COLUMN IF NOT EXISTS token_hash text;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'group_invitations' AND column_name = 'token') THEN
        UPDATE public.group_invitations
        SET token_hash = encode(extensions.digest(token, 'sha256'), 'hex')
        WHERE token_hash IS NULL;
        DROP INDEX IF EXISTS public.idx_group_invitations_token;
        ALTER TABLE public.group_invitations DROP COLUMN token;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'group_invitations' AND column_name = 'accepted_at') THEN
        ALTER TABLE public.group_invitations RENAME COLUMN accepted_at TO responded_at;
    END IF;
END;
$$;
ALTER TABLE public.group_invitations ADD COLUMN IF NOT EXISTS responded_at timestamptz;

-- Rows without a hash can never be accepted.
DELETE FROM public.group_invitations WHERE token_hash IS NULL;
ALTER TABLE public.group_invitations ALTER COLUMN token_hash SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_group_invitations_token_hash ON public.group_invitations (token_hash);

ALTER TABLE public.group_invitations DROP CONSTRAINT IF EXISTS group_invitations_token_hash_format;
ALTER TABLE public.group_invitations ADD CONSTRAINT group_invitations_token_hash_format
    CHECK (token_hash ~ '^[0-9a-f]{64}$');

-- Email: lower-case, trimmed, plausible format, <= 254 chars. Malformed rows are removed.
UPDATE public.group_invitations SET email = lower(btrim(email)) WHERE email <> lower(btrim(email));
DELETE FROM public.group_invitations
WHERE char_length(email) > 254 OR email !~ '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$';

ALTER TABLE public.group_invitations DROP CONSTRAINT IF EXISTS group_invitations_email_check;
ALTER TABLE public.group_invitations DROP CONSTRAINT IF EXISTS group_invitations_email_format;
ALTER TABLE public.group_invitations ADD CONSTRAINT group_invitations_email_format
    CHECK (
        email = lower(btrim(email))
        AND char_length(email) <= 254
        AND email ~ '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$'
    );

-- Role: invitations never grant admin.
UPDATE public.group_invitations SET role = 'member' WHERE role NOT IN ('member', 'viewer');
ALTER TABLE public.group_invitations DROP CONSTRAINT IF EXISTS group_invitations_role_check;
ALTER TABLE public.group_invitations ADD CONSTRAINT group_invitations_role_check
    CHECK (role IN ('member', 'viewer'));

-- Status: persist expiry; keep only the newest pending invitation per (group, email).
UPDATE public.group_invitations SET status = 'expired' WHERE status = 'pending' AND expires_at <= now();
UPDATE public.group_invitations AS gi
SET status = 'revoked'
WHERE gi.status = 'pending'
  AND EXISTS (
      SELECT 1 FROM public.group_invitations AS newer
      WHERE newer.group_id = gi.group_id AND newer.email = gi.email AND newer.status = 'pending'
        AND (newer.created_at, newer.id) > (gi.created_at, gi.id)
  );
CREATE UNIQUE INDEX IF NOT EXISTS uq_group_invitations_pending_email
    ON public.group_invitations (group_id, email) WHERE status = 'pending';

-- Only the admin may invite (groups.admin_id was made consistent by the membership migration).
UPDATE public.group_invitations AS gi
SET status = 'revoked'
WHERE gi.status = 'pending'
  AND NOT EXISTS (SELECT 1 FROM public.groups AS g WHERE g.id = gi.group_id AND g.admin_id = gi.inviter_id);

UPDATE public.group_invitations SET responded_at = COALESCE(responded_at, created_at)
WHERE status IN ('accepted', 'declined') AND responded_at IS NULL;

ALTER TABLE public.group_invitations ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.group_invitations ALTER COLUMN expires_at SET DEFAULT now() + interval '7 days';

-- Indexes for rate limits, FKs and lookups.
CREATE INDEX IF NOT EXISTS idx_group_invitations_inviter_created ON public.group_invitations (inviter_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_invitations_email_created ON public.group_invitations (email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_invitations_group ON public.group_invitations (group_id);

-- -----------------------------------------------------------------------------
-- Privileges and RLS
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.group_invitations FROM anon, authenticated;
GRANT SELECT (id, group_id, inviter_id, email, role, status, expires_at, created_at, responded_at)
    ON TABLE public.group_invitations TO authenticated;
GRANT ALL ON TABLE public.group_invitations TO service_role;

ALTER TABLE public.group_invitations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Members can view group invitations" ON public.group_invitations;
DROP POLICY IF EXISTS "Members can create group invitations" ON public.group_invitations;
DROP POLICY IF EXISTS "Admins or inviters can update/revoke invitations" ON public.group_invitations;
DROP POLICY IF EXISTS group_invitations_select_admin_pending ON public.group_invitations;

CREATE POLICY group_invitations_select_admin_pending ON public.group_invitations
    FOR SELECT TO authenticated
    USING (status = 'pending' AND expires_at > now() AND public.is_group_admin(group_id));

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------

-- The caller's confirmed account email (lower-case), or NULL.
CREATE OR REPLACE FUNCTION public.auth_confirmed_email()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT lower(u.email)
    FROM auth.users AS u
    WHERE u.id = auth.uid() AND u.email_confirmed_at IS NOT NULL AND u.email IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.auth_confirmed_email() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auth_confirmed_email() TO service_role;

CREATE OR REPLACE FUNCTION public.hash_invitation_token(p_token text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT encode(extensions.digest(btrim(p_token), 'sha256'), 'hex');
$$;
REVOKE ALL ON FUNCTION public.hash_invitation_token(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hash_invitation_token(text) TO service_role;

-- -----------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------

-- Creates an invitation (group admin only) and returns the raw token once.
CREATE OR REPLACE FUNCTION public.create_group_invitation(p_group_id uuid, p_email text, p_role text DEFAULT 'member')
RETURNS TABLE (invitation_id uuid, token text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    c_per_inviter_per_hour constant int := 20;
    c_per_inviter_email_per_day constant int := 5;
    c_inviters_per_email_per_day constant int := 10;
    v_uid uuid := auth.uid();
    v_email text := lower(btrim(p_email));
    v_token text;
    v_row public.group_invitations%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.groups AS g WHERE g.id = p_group_id) THEN
        RAISE EXCEPTION 'group_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT public.is_group_admin(p_group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;
    IF p_role IS NULL OR p_role NOT IN ('member', 'viewer') THEN
        RAISE EXCEPTION 'invalid_role' USING ERRCODE = '22023';
    END IF;
    IF v_email IS NULL OR char_length(v_email) > 254
       OR v_email !~ '^[a-z0-9._%+''-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$' THEN
        RAISE EXCEPTION 'invalid_email' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.group_members AS gm
        JOIN auth.users AS u ON u.id = gm.user_id
        WHERE gm.group_id = p_group_id AND gm.status = 'approved' AND lower(u.email) = v_email
    ) THEN
        RAISE EXCEPTION 'already_member' USING ERRCODE = '23505';
    END IF;

    -- Serialise per inviter and per address so the limits hold under concurrency (always in this
    -- order: inviter, then address).
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('create_group_invitation:' || v_uid::text, 0));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('create_group_invitation_email:' || v_email, 0));

    IF (SELECT count(*) FROM public.group_invitations AS gi
        WHERE gi.inviter_id = v_uid AND gi.created_at > now() - interval '1 hour') >= c_per_inviter_per_hour
    OR (SELECT count(*) FROM public.group_invitations AS gi
        WHERE gi.inviter_id = v_uid AND gi.email = v_email
          AND gi.created_at > now() - interval '1 day') >= c_per_inviter_email_per_day
    OR (SELECT count(DISTINCT gi.inviter_id) FROM public.group_invitations AS gi
        WHERE gi.email = v_email AND gi.inviter_id <> v_uid
          AND gi.created_at > now() - interval '1 day') >= c_inviters_per_email_per_day THEN
        RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'P0001';
    END IF;

    -- A new invitation replaces a pending one for the same address and lifts a ban on that user.
    UPDATE public.group_invitations AS gi
    SET status = 'revoked'
    WHERE gi.group_id = p_group_id AND gi.email = v_email AND gi.status = 'pending';

    DELETE FROM public.group_bans AS b
    USING auth.users AS u
    WHERE b.group_id = p_group_id AND b.user_id = u.id AND lower(u.email) = v_email;

    v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');

    INSERT INTO public.group_invitations (group_id, inviter_id, email, role, token_hash, status)
    VALUES (p_group_id, v_uid, v_email, p_role, public.hash_invitation_token(v_token), 'pending')
    RETURNING * INTO v_row;

    invitation_id := v_row.id;
    token := v_token;
    expires_at := v_row.expires_at;
    RETURN NEXT;
END;
$$;

-- Invitation preview for the invited account only.
CREATE OR REPLACE FUNCTION public.get_invitation_details(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_email text;
    v_inv public.group_invitations%ROWTYPE;
    v_group_name text;
    v_admin_id uuid;
    v_inviter_name text;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    v_email := public.auth_confirmed_email();
    IF v_email IS NULL THEN
        RAISE EXCEPTION 'email_not_confirmed' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_inv FROM public.group_invitations AS gi
    WHERE gi.token_hash = public.hash_invitation_token(p_token);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_inv.email <> v_email THEN
        RAISE EXCEPTION 'invite_email_mismatch' USING ERRCODE = '42501';
    END IF;

    SELECT g.name, g.admin_id INTO v_group_name, v_admin_id FROM public.groups AS g WHERE g.id = v_inv.group_id;
    SELECT p.display_name INTO v_inviter_name FROM public.profiles AS p WHERE p.id = v_inv.inviter_id;

    RETURN jsonb_build_object(
        'invitation_id', v_inv.id,
        'group_id', v_inv.group_id,
        'group_name', v_group_name,
        'inviter_name', v_inviter_name,
        'role', v_inv.role,
        'status', CASE
                      WHEN v_inv.status = 'pending' AND v_inv.inviter_id IS DISTINCT FROM v_admin_id THEN 'revoked'
                      WHEN v_inv.status = 'pending' AND v_inv.expires_at <= now() THEN 'expired'
                      ELSE v_inv.status
                  END,
        'expires_at', v_inv.expires_at
    );
END;
$$;

-- Accepts an invitation addressed to the caller's confirmed email.
CREATE OR REPLACE FUNCTION public.accept_group_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_email text;
    v_inv public.group_invitations%ROWTYPE;
    v_group public.groups%ROWTYPE;
    v_member public.group_members%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    v_email := public.auth_confirmed_email();
    IF v_email IS NULL THEN
        RAISE EXCEPTION 'email_not_confirmed' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_inv FROM public.group_invitations AS gi
    WHERE gi.token_hash = public.hash_invitation_token(p_token)
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_inv.email <> v_email THEN
        RAISE EXCEPTION 'invite_email_mismatch' USING ERRCODE = '42501';
    END IF;

    CASE
        WHEN v_inv.status = 'accepted' THEN RAISE EXCEPTION 'invite_already_used' USING ERRCODE = 'P0001';
        WHEN v_inv.status = 'declined' THEN RAISE EXCEPTION 'invite_declined' USING ERRCODE = 'P0001';
        WHEN v_inv.status = 'revoked' THEN RAISE EXCEPTION 'invite_revoked' USING ERRCODE = 'P0001';
        WHEN v_inv.status = 'expired' OR v_inv.expires_at <= now() THEN
            -- Not persisted here (the exception would roll it back); purge_old_invitations marks it.
            RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0001';
        ELSE NULL;
    END CASE;

    SELECT * INTO v_group FROM public.groups AS g WHERE g.id = v_inv.group_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'group_not_found' USING ERRCODE = 'P0002';
    END IF;
    -- An invitation carries the authority of the admin who sent it.
    IF v_inv.inviter_id IS DISTINCT FROM v_group.admin_id THEN
        RAISE EXCEPTION 'invite_revoked' USING ERRCODE = 'P0001',
            DETAIL = 'The inviter is no longer the group admin.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.group_bans AS b WHERE b.group_id = v_inv.group_id AND b.user_id = v_uid) THEN
        RAISE EXCEPTION 'banned' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_member FROM public.group_members AS gm
    WHERE gm.group_id = v_inv.group_id AND gm.user_id = v_uid
    FOR UPDATE;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    IF v_member.id IS NULL THEN
        INSERT INTO public.group_members (group_id, user_id, role, status, invited_by)
        VALUES (v_inv.group_id, v_uid, v_inv.role, 'approved', v_inv.inviter_id);
    ELSIF v_member.status = 'pending' THEN
        -- A pending code request is superseded by the admin's invitation.
        UPDATE public.group_members
        SET role = v_inv.role, status = 'approved', invited_by = v_inv.inviter_id, joined_at = now()
        WHERE id = v_member.id;
    ELSE
        RAISE EXCEPTION 'already_member' USING ERRCODE = '23505';
    END IF;
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    UPDATE public.group_invitations SET status = 'accepted', responded_at = now() WHERE id = v_inv.id;
    UPDATE public.profiles SET group_id = v_inv.group_id WHERE id = v_uid;

    RETURN jsonb_build_object('group_id', v_group.id, 'group_name', v_group.name,
                              'role', v_inv.role, 'status', 'approved');
END;
$$;

-- Declines an invitation addressed to the caller's confirmed email.
CREATE OR REPLACE FUNCTION public.decline_group_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_email text;
    v_inv public.group_invitations%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    v_email := public.auth_confirmed_email();
    IF v_email IS NULL THEN
        RAISE EXCEPTION 'email_not_confirmed' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_inv FROM public.group_invitations AS gi
    WHERE gi.token_hash = public.hash_invitation_token(p_token)
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_inv.email <> v_email THEN
        RAISE EXCEPTION 'invite_email_mismatch' USING ERRCODE = '42501';
    END IF;

    CASE
        WHEN v_inv.status = 'accepted' THEN RAISE EXCEPTION 'invite_already_used' USING ERRCODE = 'P0001';
        WHEN v_inv.status = 'declined' THEN RAISE EXCEPTION 'invite_declined' USING ERRCODE = 'P0001';
        WHEN v_inv.status = 'revoked' THEN RAISE EXCEPTION 'invite_revoked' USING ERRCODE = 'P0001';
        WHEN v_inv.status = 'expired' OR v_inv.expires_at <= now() THEN
            RAISE EXCEPTION 'invite_expired' USING ERRCODE = 'P0001';
        ELSE NULL;
    END CASE;

    UPDATE public.group_invitations SET status = 'declined', responded_at = now() WHERE id = v_inv.id;

    RETURN jsonb_build_object('invitation_id', v_inv.id, 'status', 'declined');
END;
$$;

-- Revokes a pending invitation (group admin only).
CREATE OR REPLACE FUNCTION public.revoke_group_invitation(p_invitation_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inv public.group_invitations%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_inv FROM public.group_invitations AS gi WHERE gi.id = p_invitation_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'invite_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT public.is_group_admin(v_inv.group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;
    IF v_inv.status <> 'pending' THEN
        RAISE EXCEPTION 'invite_not_pending' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.group_invitations SET status = 'revoked', responded_at = now() WHERE id = v_inv.id;

    RETURN jsonb_build_object('invitation_id', v_inv.id, 'status', 'revoked');
END;
$$;

-- Housekeeping (service_role / scheduler): persists expiry, deletes answered or expired invitations
-- older than 90 days and throttle records older than a day.
CREATE OR REPLACE FUNCTION public.purge_old_invitations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_expired int;
    v_deleted int;
    v_attempts int;
BEGIN
    UPDATE public.group_invitations SET status = 'expired'
    WHERE status = 'pending' AND expires_at <= now();
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    DELETE FROM public.group_invitations
    WHERE status <> 'pending' AND created_at < now() - interval '90 days';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    DELETE FROM public.invite_code_attempts WHERE attempted_at < now() - interval '1 day';
    GET DIAGNOSTICS v_attempts = ROW_COUNT;

    RETURN jsonb_build_object('expired', v_expired, 'deleted', v_deleted, 'attempts_deleted', v_attempts);
END;
$$;

REVOKE ALL ON FUNCTION public.create_group_invitation(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_invitation_details(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_group_invitation(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decline_group_invitation(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_group_invitation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.purge_old_invitations() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.create_group_invitation(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_invitation_details(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.accept_group_invitation(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.decline_group_invitation(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_group_invitation(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.purge_old_invitations() TO service_role;

-- Daily cleanup when pg_cron is enabled (Dashboard > Database > Extensions). Without pg_cron, schedule
-- `select public.purge_old_invitations();` from any service-role job.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-old-invitations') THEN
            PERFORM cron.unschedule('purge-old-invitations');
        END IF;
        PERFORM cron.schedule('purge-old-invitations', '17 3 * * *', 'select public.purge_old_invitations();');
    END IF;
END;
$$;
