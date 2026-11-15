-- =============================================================================
-- Settlements: states, minor units, group currency, and an append-only audit trail
--
-- public.settlements columns after this migration:
--   id (server-generated), group_id, from_user (who pays), to_user (who receives),
--   amount_minor (1 .. 100,000,000,000), currency (always the group currency),
--   status pending | confirmed | voided (default pending), note (<= 200),
--   created_by, created_at (server-set), confirmed_at, voided_at, voided_by, void_reason (<= 200).
--   Renamed: payer_id -> from_user, payee_id -> to_user, notes -> note. Dropped: amount, date.
--   User references point at auth.users ON DELETE SET NULL, so a deleted account's history stays
--   (shown as "Former member").
--
-- public.settlement_events: append-only audit (recorded | confirmed | voided), written by the
-- settlement RPCs (next migration). Readable by approved group members. No client writes, and a
-- trigger rejects UPDATE/DELETE from anyone except the foreign-key actions of a deleted group or
-- account.
--
-- Clients cannot write settlements directly (the old INSERT policy and RPC are removed); only
-- confirmed settlements count towards balances.
-- Legacy rows: amounts converted with the group currency's exponent (never clamped: an amount outside
-- 1 .. 100,000,000,000 minor units stops the migration with legacy_amount_out_of_range), status 'confirmed'
-- (confirmed_at = the old settlement date), created_by = from_user, notes cut to 200; a recorded
-- and a confirmed audit event are added for each.
-- =============================================================================

-- The old RPC wrote the legacy columns; the new one is created in the next migration.
DROP FUNCTION IF EXISTS public.record_settlement(uuid, uuid, numeric, text);

DROP POLICY IF EXISTS "Payers or admins can record settlements" ON public.settlements;
DROP POLICY IF EXISTS "Members can view group settlements" ON public.settlements;

-- -----------------------------------------------------------------------------
-- Renames (guarded)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_pair text[];
BEGIN
    FOREACH v_pair SLICE 1 IN ARRAY ARRAY[['payer_id', 'from_user'], ['payee_id', 'to_user'], ['notes', 'note']] LOOP
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'settlements' AND column_name = v_pair[1])
           AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'settlements' AND column_name = v_pair[2]) THEN
            EXECUTE format('ALTER TABLE public.settlements RENAME COLUMN %I TO %I', v_pair[1], v_pair[2]);
        END IF;
    END LOOP;
END;
$$;

ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS from_user uuid;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS to_user uuid;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS amount_minor bigint;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS currency char(3);
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS status text;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS confirmed_at timestamptz;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS voided_at timestamptz;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS voided_by uuid;
ALTER TABLE public.settlements ADD COLUMN IF NOT EXISTS void_reason text;

-- -----------------------------------------------------------------------------
-- Legacy conversion (only while the NUMERIC column exists)
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_bad text;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'settlements' AND column_name = 'amount') THEN
        UPDATE public.settlements AS s
        SET currency = g.currency
        FROM public.groups AS g
        WHERE g.id = s.group_id AND s.currency IS DISTINCT FROM g.currency;

        EXECUTE $sql$
            SELECT string_agg(id::text, ', ' ORDER BY id)
            FROM (
                SELECT id FROM public.settlements
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
                      DETAIL = 'public.settlements ids: ' || v_bad,
                      HINT = 'Each amount must convert to 1 .. 100000000000 minor units of its currency. '
                          || 'Correct or delete these rows, then apply the migrations again.';
        END IF;

        EXECUTE $sql$
            UPDATE public.settlements
            SET amount_minor = round(amount * (10::numeric ^ public.currency_minor_units(currency::text)))::bigint,
                status = COALESCE(status, 'confirmed'),
                confirmed_at = COALESCE(confirmed_at, date, created_at),
                created_by = COALESCE(created_by, from_user)
            WHERE amount_minor IS NULL
        $sql$;

        ALTER TABLE public.settlements DROP COLUMN amount;
        ALTER TABLE public.settlements DROP COLUMN IF EXISTS date;
    END IF;
END;
$$;

UPDATE public.settlements AS s
SET currency = (SELECT g.currency FROM public.groups AS g WHERE g.id = s.group_id)
WHERE s.currency IS NULL;
UPDATE public.settlements SET status = 'confirmed', confirmed_at = COALESCE(confirmed_at, created_at)
WHERE status IS NULL;

UPDATE public.settlements
SET note = NULLIF(left(regexp_replace(note, '^\s+|\s+$', '', 'g'), 200), '')
WHERE note IS NOT NULL
  AND note IS DISTINCT FROM NULLIF(left(regexp_replace(note, '^\s+|\s+$', '', 'g'), 200), '');

ALTER TABLE public.settlements ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.settlements ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.settlements ALTER COLUMN status SET DEFAULT 'pending';
ALTER TABLE public.settlements ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.settlements ALTER COLUMN amount_minor SET NOT NULL;
ALTER TABLE public.settlements ALTER COLUMN currency SET NOT NULL;
ALTER TABLE public.settlements ALTER COLUMN from_user DROP NOT NULL;
ALTER TABLE public.settlements ALTER COLUMN to_user DROP NOT NULL;

-- -----------------------------------------------------------------------------
-- Constraints
-- -----------------------------------------------------------------------------
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_amount_check;
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_amount_minor_range;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_amount_minor_range
    CHECK (amount_minor > 0 AND amount_minor <= 100000000000);
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_currency_supported;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_currency_supported
    CHECK (currency ~ '^[A-Z]{3}$' AND public.is_supported_currency(currency::text));
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_status_valid;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_status_valid
    CHECK (status IN ('pending', 'confirmed', 'voided'));
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_confirmed_has_time;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_confirmed_has_time
    CHECK (status <> 'confirmed' OR confirmed_at IS NOT NULL);
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_voided_has_time;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_voided_has_time
    CHECK ((status = 'voided') = (voided_at IS NOT NULL));
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_note_length;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_note_length
    CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 200);
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_void_reason_length;
ALTER TABLE public.settlements ADD CONSTRAINT settlements_void_reason_length
    CHECK (void_reason IS NULL OR char_length(void_reason) BETWEEN 1 AND 200);
-- different_settlement_parties (from_user <> to_user) is kept from the baseline.
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS different_settlement_parties;
ALTER TABLE public.settlements ADD CONSTRAINT different_settlement_parties CHECK (from_user <> to_user);

DO $$
DECLARE
    v_fk text[];
BEGIN
    FOREACH v_fk SLICE 1 IN ARRAY ARRAY[
        ['settlements_payer_id_fkey', 'settlements_from_user_fkey', 'from_user'],
        ['settlements_payee_id_fkey', 'settlements_to_user_fkey', 'to_user'],
        ['-', 'settlements_created_by_fkey', 'created_by'],
        ['-', 'settlements_voided_by_fkey', 'voided_by']
    ] LOOP
        EXECUTE format('ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS %I', v_fk[1]);
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_constraint
            WHERE conrelid = 'public.settlements'::regclass AND conname = v_fk[2]
              AND confrelid = 'auth.users'::regclass AND confdeltype = 'n'
        ) THEN
            EXECUTE format('ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS %I', v_fk[2]);
            EXECUTE format('ALTER TABLE public.settlements ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES auth.users (id) ON DELETE SET NULL',
                           v_fk[2], v_fk[3]);
        END IF;
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- Server-controlled fields and the group currency
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.settlements_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_group_currency text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.id := pg_catalog.gen_random_uuid();
        NEW.created_at := pg_catalog.now();
    ELSE
        IF NEW.group_id IS DISTINCT FROM OLD.group_id THEN
            RAISE EXCEPTION 'settlement_group_immutable' USING ERRCODE = '22023';
        END IF;
        NEW.id := OLD.id;
        NEW.created_at := OLD.created_at;
    END IF;

    SELECT g.currency INTO v_group_currency FROM public.groups AS g WHERE g.id = NEW.group_id;
    IF NEW.currency IS NULL THEN
        NEW.currency := v_group_currency;
    ELSIF v_group_currency IS NOT NULL AND pg_catalog.upper(NEW.currency) <> v_group_currency
          AND (TG_OP = 'INSERT' OR NEW.currency IS DISTINCT FROM OLD.currency) THEN
        RAISE EXCEPTION 'currency_mismatch' USING ERRCODE = '22023',
            DETAIL = 'A settlement must use the group currency.';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.settlements_before_write() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_settlements_before_write ON public.settlements;
CREATE TRIGGER trigger_settlements_before_write
    BEFORE INSERT OR UPDATE ON public.settlements
    FOR EACH ROW EXECUTE FUNCTION public.settlements_before_write();

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
ALTER INDEX IF EXISTS public.idx_settlements_payer RENAME TO idx_settlements_from_user;
ALTER INDEX IF EXISTS public.idx_settlements_payee RENAME TO idx_settlements_to_user;
CREATE INDEX IF NOT EXISTS idx_settlements_group ON public.settlements (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_settlements_from_user ON public.settlements (from_user);
CREATE INDEX IF NOT EXISTS idx_settlements_to_user ON public.settlements (to_user);
CREATE INDEX IF NOT EXISTS idx_settlements_created_by ON public.settlements (created_by);
CREATE INDEX IF NOT EXISTS idx_settlements_voided_by ON public.settlements (voided_by);

-- -----------------------------------------------------------------------------
-- Audit trail
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.settlement_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    settlement_id uuid NOT NULL REFERENCES public.settlements (id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES public.groups (id) ON DELETE CASCADE,
    actor uuid REFERENCES auth.users (id) ON DELETE SET NULL,
    action text NOT NULL CHECK (action IN ('recorded', 'confirmed', 'voided')),
    at timestamptz NOT NULL DEFAULT now(),
    details jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_settlement_events_settlement ON public.settlement_events (settlement_id, at);
CREATE INDEX IF NOT EXISTS idx_settlement_events_group ON public.settlement_events (group_id);
CREATE INDEX IF NOT EXISTS idx_settlement_events_actor ON public.settlement_events (actor);
ALTER TABLE public.settlement_events ENABLE ROW LEVEL SECURITY;

-- Rows are immutable. The only changes allowed come from foreign-key actions (a deleted group or
-- settlement removes its events; a deleted account clears `actor`), which run one trigger level down.
CREATE OR REPLACE FUNCTION public.settlement_events_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF pg_catalog.pg_trigger_depth() > 1 THEN
        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
        IF NEW.actor IS NULL
           AND (NEW.id, NEW.settlement_id, NEW.group_id, NEW.action, NEW.at, NEW.details)
               IS NOT DISTINCT FROM (OLD.id, OLD.settlement_id, OLD.group_id, OLD.action, OLD.at, OLD.details) THEN
            RETURN NEW;
        END IF;
    END IF;
    RAISE EXCEPTION 'settlement_events_append_only' USING ERRCODE = '42501';
END;
$$;
REVOKE ALL ON FUNCTION public.settlement_events_append_only() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_settlement_events_append_only ON public.settlement_events;
CREATE TRIGGER trigger_settlement_events_append_only
    BEFORE UPDATE OR DELETE ON public.settlement_events
    FOR EACH ROW EXECUTE FUNCTION public.settlement_events_append_only();

-- Server-set id and time on insert.
CREATE OR REPLACE FUNCTION public.settlement_events_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    NEW.id := pg_catalog.gen_random_uuid();
    NEW.at := pg_catalog.now();
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.settlement_events_before_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_settlement_events_before_insert ON public.settlement_events;
CREATE TRIGGER trigger_settlement_events_before_insert
    BEFORE INSERT ON public.settlement_events
    FOR EACH ROW EXECUTE FUNCTION public.settlement_events_before_insert();

-- Legacy settlements get their audit history once.
INSERT INTO public.settlement_events (settlement_id, group_id, actor, action, details)
SELECT s.id, s.group_id, s.from_user, a.action,
       pg_catalog.jsonb_build_object('legacy', true, 'amount_minor', s.amount_minor, 'currency', s.currency,
                                     'occurred_at', COALESCE(s.confirmed_at, s.created_at))
FROM public.settlements AS s
CROSS JOIN (VALUES ('recorded'), ('confirmed')) AS a (action)
WHERE s.status = 'confirmed'
  AND NOT EXISTS (SELECT 1 FROM public.settlement_events AS e WHERE e.settlement_id = s.id);

-- -----------------------------------------------------------------------------
-- Privileges and RLS: read-only for approved members of the group.
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.settlements FROM anon, authenticated;
GRANT SELECT ON TABLE public.settlements TO authenticated;
GRANT ALL ON TABLE public.settlements TO service_role;

REVOKE ALL ON TABLE public.settlement_events FROM anon, authenticated, service_role;
GRANT SELECT ON TABLE public.settlement_events TO authenticated;
GRANT SELECT, INSERT ON TABLE public.settlement_events TO service_role;

DROP POLICY IF EXISTS settlements_select_member ON public.settlements;
CREATE POLICY settlements_select_member ON public.settlements
    FOR SELECT TO authenticated
    USING (group_id IN (SELECT public.get_auth_user_groups()));

DROP POLICY IF EXISTS settlement_events_select_member ON public.settlement_events;
CREATE POLICY settlement_events_select_member ON public.settlement_events
    FOR SELECT TO authenticated
    USING (group_id IN (SELECT public.get_auth_user_groups()));

-- -----------------------------------------------------------------------------
-- Realtime
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
       AND NOT EXISTS (
           SELECT 1 FROM pg_catalog.pg_publication_tables
           WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'settlements'
       ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.settlements;
    END IF;
END;
$$;
