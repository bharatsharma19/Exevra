-- =============================================================================
-- Profiles: privacy, validation and email sync
--
-- * A user reads and updates only their own profile row. Co-members' names and avatars are exposed
--   through public.get_group_members() (see the membership migration), never their email.
-- * Clients may update only preference columns (column privileges). id, email, created_at and the
--   active group are server-managed; email is synced from auth.users.
-- * New columns: ai_consent_at, timezone (IANA), locale. profiles.phone is dropped (phone sign-in is
--   not offered).
-- * Validation: display_name 1..60 chars, https avatar URL <= 2048 chars, supported currency.
--
-- Idempotent and safe on a database that already holds user data: legacy values are normalised
-- before each constraint is added.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Shared validation helpers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.supported_currency_codes()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT ARRAY[
        'INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'AUD', 'CAD', 'JPY', 'CHF', 'CNY', 'NZD', 'ZAR',
        'SEK', 'NOK', 'DKK', 'HKD', 'SAR', 'MYR', 'THB', 'IDR', 'PHP', 'BRL', 'MXN', 'KRW'
    ]::text[];
$$;

CREATE OR REPLACE FUNCTION public.is_supported_currency(p_code text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT p_code IS NOT NULL
       AND p_code ~ '^[A-Z]{3}$'
       AND p_code = ANY (public.supported_currency_codes());
$$;

CREATE OR REPLACE FUNCTION public.is_valid_timezone(p_tz text)
RETURNS boolean
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT p_tz IS NOT NULL
       AND char_length(p_tz) <= 64
       AND EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS tz WHERE tz.name = p_tz);
$$;

REVOKE ALL ON FUNCTION public.supported_currency_codes() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_supported_currency(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_valid_timezone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.supported_currency_codes() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_supported_currency(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_valid_timezone(text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Every auth user has a profile row (rows may be missing on old databases).
-- -----------------------------------------------------------------------------
INSERT INTO public.profiles (id, display_name, email)
SELECT u.id,
       COALESCE(NULLIF(left(btrim(split_part(COALESCE(u.email, ''), '@', 1)), 60), ''), 'User'),
       u.email
FROM auth.users AS u
WHERE NOT EXISTS (SELECT 1 FROM public.profiles AS p WHERE p.id = u.id);

-- -----------------------------------------------------------------------------
-- Columns
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS ai_consent_at timestamptz;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'Asia/Kolkata';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS locale text;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS phone;

-- Covers the ON DELETE SET NULL action when a group is deleted.
CREATE INDEX IF NOT EXISTS idx_profiles_group_id ON public.profiles (group_id);

ALTER TABLE public.profiles ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.profiles ALTER COLUMN updated_at SET DEFAULT now();

-- The legacy clean-up below is not a user edit: pause the old updated_at trigger so existing rows keep
-- their updated_at. Resumed after the clean-up.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.profiles'::regclass AND tgname = 'trigger_profiles_updated_at') THEN
        ALTER TABLE public.profiles DISABLE TRIGGER trigger_profiles_updated_at;
    END IF;
END;
$$;

-- Legacy consent has no timestamp: use the last profile update as the best available value.
UPDATE public.profiles SET ai_consent_at = updated_at WHERE ai_consent AND ai_consent_at IS NULL;

-- -----------------------------------------------------------------------------
-- Normalise legacy values, then add constraints
-- -----------------------------------------------------------------------------
UPDATE public.profiles
SET display_name = COALESCE(NULLIF(btrim(left(btrim(display_name), 60)), ''), 'User')
WHERE display_name IS NULL
   OR display_name <> btrim(display_name)
   OR char_length(btrim(display_name)) NOT BETWEEN 1 AND 60;

UPDATE public.profiles
SET avatar_url = NULL
WHERE avatar_url IS NOT NULL
  AND (avatar_url !~ '^https://' OR char_length(avatar_url) > 2048);

UPDATE public.profiles
SET currency = CASE WHEN public.is_supported_currency(upper(btrim(currency))) THEN upper(btrim(currency)) ELSE 'INR' END
WHERE currency IS NULL OR NOT public.is_supported_currency(currency::text);

UPDATE public.profiles SET timezone = 'Asia/Kolkata' WHERE NOT public.is_valid_timezone(timezone);

UPDATE public.profiles SET locale = NULL
WHERE locale IS NOT NULL AND (char_length(locale) > 35 OR locale !~ '^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$');

DO $$
BEGIN
    IF (SELECT data_type FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'currency') <> 'character' THEN
        ALTER TABLE public.profiles ALTER COLUMN currency TYPE char(3) USING currency::char(3);
    END IF;
END;
$$;
ALTER TABLE public.profiles ALTER COLUMN currency SET DEFAULT 'INR';

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_display_name_length;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_display_name_length
    CHECK (display_name = btrim(display_name) AND char_length(display_name) BETWEEN 1 AND 60);

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_avatar_url_https;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_avatar_url_https
    CHECK (avatar_url IS NULL OR (avatar_url ~ '^https://' AND char_length(avatar_url) <= 2048));

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_currency_supported;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_currency_supported
    CHECK (public.is_supported_currency(currency::text));

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_locale_format;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_locale_format
    CHECK (locale IS NULL OR (char_length(locale) <= 35 AND locale ~ '^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,8})*$'));

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_timezone_length;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_timezone_length
    CHECK (char_length(timezone) BETWEEN 1 AND 64);

-- theme_mode already has CHECK (system, light, dark) from the baseline.

-- -----------------------------------------------------------------------------
-- Guard trigger: server-managed columns, consent timestamp, timezone validation
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.profiles_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND current_user IN ('authenticated', 'anon') THEN
        -- Column privileges already prevent these writes; this keeps the invariant if grants change.
        NEW.id := OLD.id;
        NEW.email := OLD.email;
        NEW.created_at := OLD.created_at;
        NEW.group_id := OLD.group_id;
    END IF;

    IF NEW.display_name IS NOT NULL THEN
        NEW.display_name := btrim(NEW.display_name);
    END IF;

    IF TG_OP = 'INSERT' OR NEW.ai_consent IS DISTINCT FROM OLD.ai_consent THEN
        NEW.ai_consent_at := CASE WHEN NEW.ai_consent THEN now() ELSE NULL END;
    ELSIF current_user IN ('authenticated', 'anon') THEN
        NEW.ai_consent_at := OLD.ai_consent_at;
    END IF;

    IF (TG_OP = 'INSERT' OR NEW.timezone IS DISTINCT FROM OLD.timezone)
       AND NOT public.is_valid_timezone(NEW.timezone) THEN
        RAISE EXCEPTION 'invalid_timezone' USING ERRCODE = '22023';
    END IF;

    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.profiles_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_profiles_guard ON public.profiles;
CREATE TRIGGER trigger_profiles_guard
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.profiles_guard();

-- -----------------------------------------------------------------------------
-- New users and email changes
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_avatar text := NEW.raw_user_meta_data ->> 'avatar_url';
BEGIN
    IF v_avatar IS NOT NULL AND (v_avatar !~ '^https://' OR char_length(v_avatar) > 2048) THEN
        v_avatar := NULL;
    END IF;

    INSERT INTO public.profiles (id, display_name, email, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(
            NULLIF(btrim(left(btrim(NEW.raw_user_meta_data ->> 'full_name'), 60)), ''),
            NULLIF(btrim(left(btrim(NEW.raw_user_meta_data ->> 'name'), 60)), ''),
            NULLIF(btrim(left(split_part(COALESCE(NEW.email, ''), '@', 1), 60)), ''),
            'User'
        ),
        NEW.email,
        v_avatar
    )
    ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.handle_auth_user_email_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public.profiles SET email = NEW.email WHERE id = NEW.id;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_auth_user_email_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS on_auth_user_email_changed ON auth.users;
CREATE TRIGGER on_auth_user_email_changed
    AFTER UPDATE OF email ON auth.users
    FOR EACH ROW
    WHEN (OLD.email IS DISTINCT FROM NEW.email)
    EXECUTE FUNCTION public.handle_auth_user_email_change();

-- Re-sync emails that drifted (profiles.email used to be client-writable).
UPDATE public.profiles AS p
SET email = u.email
FROM auth.users AS u
WHERE u.id = p.id AND p.email IS DISTINCT FROM u.email;

-- Clean-up done: resume the updated_at trigger.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.profiles'::regclass AND tgname = 'trigger_profiles_updated_at') THEN
        ALTER TABLE public.profiles ENABLE TRIGGER trigger_profiles_updated_at;
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Privileges and RLS
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.profiles FROM anon, authenticated;
GRANT SELECT ON TABLE public.profiles TO authenticated;
GRANT UPDATE (display_name, avatar_url, currency, timezone, locale, theme_mode, haptics_enabled, ai_consent)
    ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own and group members profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
DROP POLICY IF EXISTS profiles_update_own ON public.profiles;

CREATE POLICY profiles_select_own ON public.profiles
    FOR SELECT TO authenticated
    USING (id = (SELECT auth.uid()));

CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE TO authenticated
    USING (id = (SELECT auth.uid()))
    WITH CHECK (id = (SELECT auth.uid()));
