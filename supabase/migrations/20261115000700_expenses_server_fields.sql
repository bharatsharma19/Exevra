-- =============================================================================
-- Expenses: server-controlled fields, validation, ownership and access rules
--
-- Columns after this migration:
--   id (server-generated), user_id (payer, auth.users ON DELETE SET NULL), group_id (NULL = personal),
--   title (trimmed, 1..120), amount_minor, currency, category (app list), spent_at (user-chosen
--   instant, timestamptz), note (trimmed, <= 500, NULL when blank), receipt_url (NULL or https <= 2048),
--   is_personal (generated), created_at / updated_at (server-set).
--   Renamed: date -> spent_at, notes -> note.
--
-- * A BEFORE trigger generates id, created_at and updated_at (client values are ignored), trims text,
--   normalises the category case, fills a missing currency (group currency, else profile currency)
--   and rejects a group expense whose currency differs from the group currency (22023
--   currency_mismatch). group_id cannot change after insert.
-- * When the payer's auth user is deleted, user_id becomes NULL ("Former member") on group expenses;
--   personal expenses of that user are deleted.
-- * RLS: personal rows are owner-only. Group rows are readable by approved members (viewers
--   included). Admins and members may add group expenses as themselves; the payer (still admin or
--   member) may edit or delete them, and the group admin may delete any group expense.
-- * Column privileges: clients cannot write id, created_at, updated_at, and cannot change user_id or
--   group_id after insert.
-- * Keyset-pagination indexes (group_id, spent_at DESC, id DESC) and (user_id, spent_at DESC, id DESC);
--   redundant indexes dropped. expenses joins the supabase_realtime publication.
-- Legacy rows: titles trimmed and cut to 120 characters, notes cut to 500, unknown categories mapped to
-- 'Other', non-https receipt URLs cleared; created_at and updated_at are kept.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Category list (matches lib/core/constants/app_constants.dart)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expense_categories()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT ARRAY[
        'Food', 'Transport', 'Housing', 'Entertainment', 'Healthcare',
        'Utilities', 'Shopping', 'Personal', 'Education', 'Other'
    ]::text[];
$$;
REVOKE ALL ON FUNCTION public.expense_categories() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expense_categories() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Renames (guarded)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'expenses' AND column_name = 'date')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'expenses' AND column_name = 'spent_at') THEN
        ALTER TABLE public.expenses RENAME COLUMN date TO spent_at;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'expenses' AND column_name = 'notes')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'expenses' AND column_name = 'note') THEN
        ALTER TABLE public.expenses RENAME COLUMN notes TO note;
    END IF;
END;
$$;

-- The legacy clean-up below is not a user edit: pause the old updated_at trigger so that
-- existing rows keep their updated_at. Resumed at the end of the clean-up.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.expenses'::regclass AND tgname = 'trigger_expenses_updated_at') THEN
        ALTER TABLE public.expenses DISABLE TRIGGER trigger_expenses_updated_at;
    END IF;
END;
$$;

ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS spent_at timestamptz;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS receipt_url text;
UPDATE public.expenses SET spent_at = created_at WHERE spent_at IS NULL;
ALTER TABLE public.expenses ALTER COLUMN spent_at SET DEFAULT now();
ALTER TABLE public.expenses ALTER COLUMN spent_at SET NOT NULL;
ALTER TABLE public.expenses ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.expenses ALTER COLUMN updated_at SET DEFAULT now();

-- -----------------------------------------------------------------------------
-- Legacy data clean-up (before the constraints)
-- -----------------------------------------------------------------------------
UPDATE public.expenses
SET title = COALESCE(NULLIF(left(regexp_replace(title, '^\s+|\s+$', '', 'g'), 120), ''), 'Expense')
WHERE title IS DISTINCT FROM COALESCE(NULLIF(left(regexp_replace(title, '^\s+|\s+$', '', 'g'), 120), ''), 'Expense');

UPDATE public.expenses
SET note = NULLIF(left(regexp_replace(note, '^\s+|\s+$', '', 'g'), 500), '')
WHERE note IS NOT NULL
  AND note IS DISTINCT FROM NULLIF(left(regexp_replace(note, '^\s+|\s+$', '', 'g'), 500), '');

UPDATE public.expenses AS e
SET category = COALESCE(
    (SELECT c FROM unnest(public.expense_categories()) AS c WHERE lower(c) = lower(btrim(e.category))),
    'Other')
WHERE NOT (e.category = ANY (public.expense_categories()));

UPDATE public.expenses
SET receipt_url = NULL
WHERE receipt_url IS NOT NULL AND NOT (receipt_url ~ '^https://' AND char_length(receipt_url) <= 2048);

-- Resume the updated_at trigger paused above.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.expenses'::regclass AND tgname = 'trigger_expenses_updated_at') THEN
        ALTER TABLE public.expenses ENABLE TRIGGER trigger_expenses_updated_at;
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- Constraints
-- -----------------------------------------------------------------------------
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_title_check;
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_title_length;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_title_length
    CHECK (char_length(title) BETWEEN 1 AND 120 AND title = btrim(title));

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_note_length;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_note_length
    CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500);

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_category_known;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_category_known
    CHECK (category = ANY (public.expense_categories()));

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_receipt_url_https;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_receipt_url_https
    CHECK (receipt_url IS NULL OR (receipt_url ~ '^https://' AND char_length(receipt_url) <= 2048));

-- Payer: auth user, kept as NULL ("Former member") when the account is deleted.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint
        WHERE conrelid = 'public.expenses'::regclass AND conname = 'expenses_user_id_fkey'
          AND confrelid = 'auth.users'::regclass AND confdeltype = 'n'
    ) THEN
        ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_user_id_fkey;
        ALTER TABLE public.expenses ADD CONSTRAINT expenses_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE SET NULL;
    END IF;
END;
$$;
ALTER TABLE public.expenses ALTER COLUMN user_id DROP NOT NULL;

-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expenses_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_group_currency text;
    v_category text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.id := pg_catalog.gen_random_uuid();
        NEW.created_at := pg_catalog.now();
        NEW.updated_at := pg_catalog.now();
        NEW.spent_at := COALESCE(NEW.spent_at, pg_catalog.now());
    ELSE
        IF NEW.group_id IS DISTINCT FROM OLD.group_id THEN
            RAISE EXCEPTION 'expense_group_immutable' USING ERRCODE = '22023';
        END IF;
        NEW.id := OLD.id;
        NEW.created_at := OLD.created_at;
        NEW.updated_at := pg_catalog.now();
        NEW.spent_at := COALESCE(NEW.spent_at, OLD.spent_at);
    END IF;

    NEW.title := pg_catalog.regexp_replace(COALESCE(NEW.title, ''), '^\s+|\s+$', '', 'g');
    NEW.note := NULLIF(pg_catalog.regexp_replace(NEW.note, '^\s+|\s+$', '', 'g'), '');

    SELECT c INTO v_category
    FROM pg_catalog.unnest(public.expense_categories()) AS c
    WHERE pg_catalog.lower(c) = pg_catalog.lower(pg_catalog.btrim(NEW.category));
    IF v_category IS NOT NULL THEN
        NEW.category := v_category;
    END IF;

    IF NEW.currency IS NOT NULL THEN
        NEW.currency := pg_catalog.upper(NEW.currency);
    END IF;

    IF NEW.group_id IS NOT NULL THEN
        SELECT g.currency INTO v_group_currency FROM public.groups AS g WHERE g.id = NEW.group_id;
        IF NEW.currency IS NULL THEN
            NEW.currency := v_group_currency;
        ELSIF v_group_currency IS NOT NULL
              AND NEW.currency <> v_group_currency
              AND (TG_OP = 'INSERT' OR NEW.currency IS DISTINCT FROM OLD.currency) THEN
            RAISE EXCEPTION 'currency_mismatch' USING ERRCODE = '22023',
                DETAIL = 'A group expense must use the group currency.';
        END IF;
    ELSIF NEW.currency IS NULL THEN
        SELECT p.currency INTO v_group_currency FROM public.profiles AS p WHERE p.id = NEW.user_id;
        NEW.currency := COALESCE(v_group_currency, 'INR');
    END IF;

    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.expenses_before_write() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_expenses_updated_at ON public.expenses;
DROP TRIGGER IF EXISTS trigger_expenses_before_write ON public.expenses;
CREATE TRIGGER trigger_expenses_before_write
    BEFORE INSERT OR UPDATE ON public.expenses
    FOR EACH ROW EXECUTE FUNCTION public.expenses_before_write();

-- A personal expense whose owner was deleted (user_id set to NULL by the FK) is removed.
CREATE OR REPLACE FUNCTION public.expenses_drop_orphaned_personal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    DELETE FROM public.expenses AS e WHERE e.id = NEW.id AND e.group_id IS NULL AND e.user_id IS NULL;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.expenses_drop_orphaned_personal() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_expenses_drop_orphaned_personal ON public.expenses;
CREATE TRIGGER trigger_expenses_drop_orphaned_personal
    AFTER UPDATE OF user_id ON public.expenses
    FOR EACH ROW
    WHEN (NEW.user_id IS NULL AND NEW.group_id IS NULL)
    EXECUTE FUNCTION public.expenses_drop_orphaned_personal();

-- -----------------------------------------------------------------------------
-- RLS helper: groups where the caller may add expenses (approved admin or member).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_auth_user_writable_groups()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT gm.group_id
    FROM public.group_members AS gm
    WHERE gm.user_id = auth.uid() AND gm.status = 'approved' AND gm.role IN ('admin', 'member');
$$;
REVOKE ALL ON FUNCTION public.get_auth_user_writable_groups() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_auth_user_writable_groups() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Privileges and RLS
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.expenses FROM anon, authenticated;
GRANT SELECT ON TABLE public.expenses TO authenticated;
GRANT INSERT (user_id, group_id, title, amount_minor, currency, category, spent_at, note, receipt_url)
    ON TABLE public.expenses TO authenticated;
GRANT UPDATE (title, amount_minor, currency, category, spent_at, note, receipt_url)
    ON TABLE public.expenses TO authenticated;
GRANT DELETE ON TABLE public.expenses TO authenticated;
GRANT ALL ON TABLE public.expenses TO service_role;

DROP POLICY IF EXISTS "Select Expenses Policy" ON public.expenses;
DROP POLICY IF EXISTS "Insert Expenses Policy" ON public.expenses;
DROP POLICY IF EXISTS "Update Expenses Policy" ON public.expenses;
DROP POLICY IF EXISTS "Delete Expenses Policy" ON public.expenses;
DROP POLICY IF EXISTS expenses_select ON public.expenses;
DROP POLICY IF EXISTS expenses_insert ON public.expenses;
DROP POLICY IF EXISTS expenses_update ON public.expenses;
DROP POLICY IF EXISTS expenses_delete ON public.expenses;

CREATE POLICY expenses_select ON public.expenses
    FOR SELECT TO authenticated
    USING (
        (group_id IS NULL AND user_id = (SELECT auth.uid()))
        OR group_id IN (SELECT public.get_auth_user_groups())
    );

CREATE POLICY expenses_insert ON public.expenses
    FOR INSERT TO authenticated
    WITH CHECK (
        user_id = (SELECT auth.uid())
        AND (group_id IS NULL OR group_id IN (SELECT public.get_auth_user_writable_groups()))
    );

CREATE POLICY expenses_update ON public.expenses
    FOR UPDATE TO authenticated
    USING (
        user_id = (SELECT auth.uid())
        AND (group_id IS NULL OR group_id IN (SELECT public.get_auth_user_writable_groups()))
    )
    WITH CHECK (
        user_id = (SELECT auth.uid())
        AND (group_id IS NULL OR group_id IN (SELECT public.get_auth_user_writable_groups()))
    );

CREATE POLICY expenses_delete ON public.expenses
    FOR DELETE TO authenticated
    USING (
        (group_id IS NULL AND user_id = (SELECT auth.uid()))
        OR (group_id IS NOT NULL AND public.is_group_admin(group_id))
        OR (user_id = (SELECT auth.uid()) AND group_id IN (SELECT public.get_auth_user_writable_groups()))
    );

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_expenses_user_id;
DROP INDEX IF EXISTS public.idx_expenses_group_id;
DROP INDEX IF EXISTS public.idx_expenses_date;
DROP INDEX IF EXISTS public.idx_expenses_category;
DROP INDEX IF EXISTS public.idx_expenses_personal_feed;
DROP INDEX IF EXISTS public.idx_expenses_group_feed;
CREATE INDEX IF NOT EXISTS idx_expenses_group_spent ON public.expenses (group_id, spent_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_user_spent ON public.expenses (user_id, spent_at DESC, id DESC);

-- -----------------------------------------------------------------------------
-- Realtime
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_publication_tables
           WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'expenses'
       ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses;
    END IF;
END;
$$;
