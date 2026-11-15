-- =============================================================================
-- Group invite codes
--
-- * Codes are 16 characters of Crockford base32 (80 random bits from extensions.gen_random_bytes),
--   stored upper-case and unique. Input is normalised (case, separators, I/L -> 1, O -> 0) before an
--   equality lookup, so the unique index is used.
-- * Codes expire (groups.invite_code_expires_at, default 30 days) and can be rotated by the admin.
-- * Joining with a code creates a PENDING VIEWER membership that the admin must approve.
-- * Wrong codes are throttled: at most 10 failed attempts per user per rolling hour. Because a raised
--   exception would roll back the attempt record, join_group_by_code reports outcomes in its jsonb
--   result instead of raising (see the function comment).
-- * Existing (short, hex) codes are replaced with new codes.
--
-- Idempotent and safe on a database that already holds user data.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Code generation and normalisation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_invite_code()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SET search_path = ''
AS $$
DECLARE
    c_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    v_bits bit(80) := ('x' || encode(extensions.gen_random_bytes(10), 'hex'))::bit(80);
    v_code text := '';
BEGIN
    FOR i IN 0..15 LOOP
        v_code := v_code || substr(c_alphabet, substring(v_bits FROM i * 5 + 1 FOR 5)::int + 1, 1);
    END LOOP;
    RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_invite_code(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN p_code IS NULL OR char_length(p_code) > 64 THEN NULL
        ELSE translate(upper(regexp_replace(p_code, '[\s-]', '', 'g')), 'ILO', '110')
    END;
$$;

REVOKE ALL ON FUNCTION public.generate_invite_code() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generate_invite_code() TO service_role;
REVOKE ALL ON FUNCTION public.normalize_invite_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.normalize_invite_code(text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Columns, legacy rotation, constraints
-- -----------------------------------------------------------------------------
-- Replacing legacy codes below is not a user edit: pause the old updated_at trigger so that
-- existing rows keep their updated_at. Resumed after the replacement.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.groups'::regclass AND tgname = 'trigger_groups_updated_at') THEN
        ALTER TABLE public.groups DISABLE TRIGGER trigger_groups_updated_at;
    END IF;
END;
$$;

ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS invite_code_expires_at timestamptz;
UPDATE public.groups SET invite_code_expires_at = now() + interval '30 days' WHERE invite_code_expires_at IS NULL;
ALTER TABLE public.groups ALTER COLUMN invite_code_expires_at SET DEFAULT now() + interval '30 days';
ALTER TABLE public.groups ALTER COLUMN invite_code_expires_at SET NOT NULL;

-- Replace every code that does not have the new format.
UPDATE public.groups
SET invite_code = public.generate_invite_code(),
    invite_code_expires_at = now() + interval '30 days'
WHERE invite_code !~ '^[0-9A-HJKMNP-TV-Z]{16}$';

-- Resume the updated_at trigger paused above.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.groups'::regclass AND tgname = 'trigger_groups_updated_at') THEN
        ALTER TABLE public.groups ENABLE TRIGGER trigger_groups_updated_at;
    END IF;
END;
$$;

ALTER TABLE public.groups ALTER COLUMN invite_code SET DEFAULT public.generate_invite_code();
ALTER TABLE public.groups DROP CONSTRAINT IF EXISTS groups_invite_code_format;
ALTER TABLE public.groups ADD CONSTRAINT groups_invite_code_format
    CHECK (invite_code ~ '^[0-9A-HJKMNP-TV-Z]{16}$');
-- Uniqueness: the baseline's UNIQUE constraint groups_invite_code_key (plain btree on invite_code).

-- -----------------------------------------------------------------------------
-- Failed attempt log (throttle). No client access.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.invite_code_attempts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_invite_code_attempts_user_time
    ON public.invite_code_attempts (user_id, attempted_at DESC);
ALTER TABLE public.invite_code_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.invite_code_attempts FROM anon, authenticated;
GRANT ALL ON TABLE public.invite_code_attempts TO service_role;
DROP POLICY IF EXISTS invite_code_attempts_no_client_access ON public.invite_code_attempts;
CREATE POLICY invite_code_attempts_no_client_access ON public.invite_code_attempts
    AS RESTRICTIVE FOR ALL TO anon, authenticated
    USING (false) WITH CHECK (false);

-- -----------------------------------------------------------------------------
-- join_group_by_code
--
-- Returns jsonb:
--   success: {success: true,  group_id, group_name, role: 'viewer', status: 'pending'}
--   failure: {success: false, error: <key>}  with key one of
--            invalid_code   (counted towards the throttle)
--            rate_limited   (10 failed attempts in the last hour; includes retry_after)
--            code_expired | banned | already_member (includes status)
-- Only a missing session raises (42501 not_authenticated).
-- Failures are returned rather than raised so that the failed-attempt record is committed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_group_by_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    c_max_failures constant int := 10;
    v_uid uuid := auth.uid();
    v_code text := public.normalize_invite_code(p_code);
    v_failures int;
    v_oldest timestamptz;
    v_group public.groups%ROWTYPE;
    v_status text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;

    -- Serialise attempts per user so parallel requests cannot exceed the limit.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('join_group_by_code:' || v_uid::text, 0));

    DELETE FROM public.invite_code_attempts AS a
    WHERE a.user_id = v_uid AND a.attempted_at < now() - interval '1 day';

    SELECT count(*), min(a.attempted_at) INTO v_failures, v_oldest
    FROM public.invite_code_attempts AS a
    WHERE a.user_id = v_uid AND a.attempted_at > now() - interval '1 hour';

    IF v_failures >= c_max_failures THEN
        RETURN jsonb_build_object('success', false, 'error', 'rate_limited',
                                  'retry_after', v_oldest + interval '1 hour');
    END IF;

    IF v_code IS NOT NULL AND v_code ~ '^[0-9A-HJKMNP-TV-Z]{16}$' THEN
        SELECT * INTO v_group FROM public.groups AS g WHERE g.invite_code = v_code;
    END IF;

    IF v_group.id IS NULL THEN
        INSERT INTO public.invite_code_attempts (user_id) VALUES (v_uid);
        RETURN jsonb_build_object('success', false, 'error', 'invalid_code');
    END IF;

    IF v_group.invite_code_expires_at <= now() THEN
        RETURN jsonb_build_object('success', false, 'error', 'code_expired');
    END IF;

    SELECT gm.status INTO v_status FROM public.group_members AS gm
    WHERE gm.group_id = v_group.id AND gm.user_id = v_uid;
    IF FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'already_member', 'status', v_status,
                                  'group_id', v_group.id);
    END IF;

    IF EXISTS (SELECT 1 FROM public.group_bans AS b WHERE b.group_id = v_group.id AND b.user_id = v_uid) THEN
        RETURN jsonb_build_object('success', false, 'error', 'banned');
    END IF;

    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'on', true);
    INSERT INTO public.group_members (group_id, user_id, role, status)
    VALUES (v_group.id, v_uid, 'viewer', 'pending');
    PERFORM pg_catalog.set_config('exevra.membership_rpc', 'off', true);

    RETURN jsonb_build_object('success', true, 'group_id', v_group.id, 'group_name', v_group.name,
                              'role', 'viewer', 'status', 'pending');
END;
$$;

-- Replaces the group's code with a fresh one valid for 30 days (admin only).
CREATE OR REPLACE FUNCTION public.rotate_invite_code(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code text;
    v_expires timestamptz;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_group_admin(p_group_id) THEN
        RAISE EXCEPTION 'not_group_admin' USING ERRCODE = '42501';
    END IF;

    UPDATE public.groups
    SET invite_code = public.generate_invite_code(),
        invite_code_expires_at = now() + interval '30 days'
    WHERE id = p_group_id
    RETURNING invite_code, invite_code_expires_at INTO v_code, v_expires;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'group_not_found' USING ERRCODE = 'P0002';
    END IF;

    RETURN jsonb_build_object('group_id', p_group_id, 'invite_code', v_code, 'invite_code_expires_at', v_expires);
END;
$$;

-- get_user_groups now also returns the code's expiry (admin only).
CREATE OR REPLACE FUNCTION public.get_user_groups()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_groups jsonb;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC, r.id)
    INTO v_groups
    FROM (
        SELECT g.id, g.name, g.currency, g.admin_id, g.created_at,
               gm.role, gm.status, gm.joined_at,
               CASE WHEN g.admin_id = v_uid THEN g.invite_code END AS invite_code,
               CASE WHEN g.admin_id = v_uid THEN g.invite_code_expires_at END AS invite_code_expires_at,
               (SELECT count(*) FROM public.group_members AS m
                WHERE m.group_id = g.id AND m.status = 'approved') AS members_count
        FROM public.group_members AS gm
        JOIN public.groups AS g ON g.id = gm.group_id
        WHERE gm.user_id = v_uid
    ) AS r;

    RETURN COALESCE(v_groups, '[]'::jsonb);
END;
$$;

-- The old code join (joined as member, no throttle) is replaced by join_group_by_code.
DROP FUNCTION IF EXISTS public.join_group_by_invite(text);

REVOKE ALL ON FUNCTION public.join_group_by_code(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rotate_invite_code(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_user_groups() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_group_by_code(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rotate_invite_code(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_groups() TO authenticated, service_role;
