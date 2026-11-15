-- =============================================================================
-- Money in integer minor units, with a currency on every expense
--
-- * public.currency_minor_units(code): ISO 4217 exponent of a supported currency (JPY and KRW 0,
--   every other supported code 2, including IDR), NULL for anything unsupported.
-- * expenses.amount_minor BIGINT (1 .. 100,000,000,000) replaces the NUMERIC amount column.
-- * expenses.currency CHAR(3), a supported code. A group expense always uses its group's currency
--   (enforced by the expense write trigger in the next migration); a personal expense may use any
--   supported currency.
--
-- Legacy rows: the currency of a group expense becomes the group currency, a personal expense gets
-- the owner's profile currency (or INR), and amount_minor = round(amount * 10^minor_units) (half away
-- from zero, e.g. 10.005 -> 1001). Values are never clamped: if any amount would convert to less than
-- one minor unit or more than 100,000,000,000 minor units, the migration stops with
-- legacy_amount_out_of_range and lists the expense ids, so the owner can correct them deliberately
-- (README: pre-flight query). created_at and updated_at of existing rows are kept. The NUMERIC column
-- is dropped once converted, together with the old insights RPC that read it (replaced by
-- get_expense_insights(text, uuid, text, text, timestamptz) later).
-- Idempotent: the conversion only runs while the old column exists.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Currency helper
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.currency_minor_units(p_code text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN NOT public.is_supported_currency(p_code) THEN NULL
        WHEN p_code IN ('JPY', 'KRW') THEN 0
        ELSE 2
    END;
$$;

REVOKE ALL ON FUNCTION public.currency_minor_units(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.currency_minor_units(text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- expenses: currency + amount_minor
-- -----------------------------------------------------------------------------
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS currency char(3);
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS amount_minor bigint;

-- The old insights RPC reads expenses.amount; it is replaced later in this series.
DROP FUNCTION IF EXISTS public.get_expense_insights(text, uuid);

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

DO $$
DECLARE
    v_bad text;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'expenses' AND column_name = 'amount'
    ) THEN
        -- Group expenses take the group currency.
        UPDATE public.expenses AS e
        SET currency = g.currency
        FROM public.groups AS g
        WHERE e.group_id = g.id
          AND e.currency IS DISTINCT FROM g.currency;

        -- Personal expenses take the owner's profile currency, else INR.
        UPDATE public.expenses AS e
        SET currency = COALESCE(
            (SELECT p.currency FROM public.profiles AS p
             WHERE p.id = e.user_id AND public.is_supported_currency(p.currency::text)),
            'INR')
        WHERE e.group_id IS NULL
          AND (e.currency IS NULL OR NOT public.is_supported_currency(e.currency::text));

        -- Amounts that cannot be stored exactly stop the upgrade instead of being changed.
        EXECUTE $sql$
            SELECT string_agg(id::text, ', ' ORDER BY id)
            FROM (
                SELECT id FROM public.expenses
                WHERE amount_minor IS NULL
                  AND round(amount * (10::numeric ^ public.currency_minor_units(currency::text)))
                      NOT BETWEEN 1 AND 100000000000
                ORDER BY id
                LIMIT 50
            ) AS bad
        $sql$ INTO v_bad;
        IF v_bad IS NOT NULL THEN
            RAISE EXCEPTION 'legacy_amount_out_of_range'
                USING ERRCODE = '22003',
                      DETAIL = 'public.expenses ids: ' || v_bad,
                      HINT = 'Each amount must convert to 1 .. 100000000000 minor units of its currency. '
                          || 'Correct or delete these rows, then apply the migrations again.';
        END IF;

        EXECUTE $sql$
            UPDATE public.expenses
            SET amount_minor = round(amount * (10::numeric ^ public.currency_minor_units(currency::text)))::bigint
            WHERE amount_minor IS NULL
        $sql$;

        ALTER TABLE public.expenses DROP COLUMN amount;
    END IF;
END;
$$;

-- Defensive: any row still without a currency gets the group, profile or default currency.
UPDATE public.expenses AS e
SET currency = COALESCE(
    (SELECT g.currency FROM public.groups AS g WHERE g.id = e.group_id),
    (SELECT p.currency FROM public.profiles AS p
     WHERE p.id = e.user_id AND public.is_supported_currency(p.currency::text)),
    'INR')
WHERE e.currency IS NULL;

-- Resume the updated_at trigger paused above.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
               WHERE tgrelid = 'public.expenses'::regclass AND tgname = 'trigger_expenses_updated_at') THEN
        ALTER TABLE public.expenses ENABLE TRIGGER trigger_expenses_updated_at;
    END IF;
END;
$$;

ALTER TABLE public.expenses ALTER COLUMN currency SET NOT NULL;
ALTER TABLE public.expenses ALTER COLUMN amount_minor SET NOT NULL;

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_amount_minor_range;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_amount_minor_range
    CHECK (amount_minor > 0 AND amount_minor <= 100000000000);

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_currency_supported;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_currency_supported
    CHECK (currency ~ '^[A-Z]{3}$' AND public.is_supported_currency(currency::text));
