-- =============================================================================
-- Expense splits
--
-- public.expense_splits holds each participant's share of a group expense in minor units. It is
-- written only by a trigger:
--   * on INSERT of a group expense: an equal split among the group's members at that moment who are
--     approved and have role admin or member (viewers and pending members are excluded);
--   * on UPDATE of amount_minor, or of the payer (user_id, to a non-NULL value): the amount is split
--     again among the SAME participants, i.e. exactly the users who already have split rows for the
--     expense (frozen at creation), with the same payer-first remainder rule. Current group
--     membership is never consulted again: members who joined later are never added and nobody is
--     removed. An expense without any split row (possible only for legacy data) is charged to its
--     payer alone, so its balances still sum to zero.
-- Later joins, leaves and role changes never rewrite existing splits. When a participant's account
-- is deleted their user_id becomes NULL (shown as "Former member"); that change does not re-split.
-- Deleting an expense deletes its splits (ON DELETE CASCADE). group_id never changes after insert
-- (expenses_before_write); move_expense_scope() moves an expense by deleting it and inserting a new
-- row (20261115001600).
--
-- Departed participants lock an expense. When the frozen participant set of a group expense (its
-- split user_ids plus the payer) contains anyone who is no longer an approved member of the group
-- (members who left or were removed, and former members whose user_id is NULL), its amount and payer
-- cannot change and it cannot be deleted (P0001 expense_locked_member_left): either would change the
-- balance of someone who can no longer settle in the group. Title, category, note, date and receipt
-- edits stay allowed. A role change (e.g. to viewer) does not count as leaving. The rule applies to
-- every writer (clients, service_role, the table owner); the only exception is the deletion of the
-- whole group, whose cascade removes its expenses.
--
-- Payer integrity. The payer of a group expense is an approved admin or member of the group (not a
-- viewer, not a pending member, not someone who left or was removed) whenever it is written: on
-- INSERT and on every payer change, for every writer (42501 payer_not_member). The payer can become
-- NULL only through the foreign key (ON DELETE SET NULL) while the payer's account is being deleted:
-- prepare_account_deletion() marks the transaction (exevra.account_deletion = 'on'), the change
-- arrives one trigger level down, and the auth user no longer exists. A direct UPDATE to NULL is
-- refused. Both checks take the same key-share lock on the group as the lock below.
-- Operator actions outside these rules (service_role TRUNCATE, raw edits of expense_splits) are
-- trusted maintenance and are not checked.
--
-- public.split_equal_shares(total, member_ids, payer) is the single, pure implementation of the
-- equal split. Shares always sum exactly to the total; leftover minor units are assigned by the
-- clearly delimited deterministic rule below.
--
-- Legacy group expenses are back-filled using the group's current approved admins and members (the
-- payer alone when the group has none).
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.expense_splits (
    expense_id uuid NOT NULL REFERENCES public.expenses (id) ON DELETE CASCADE,
    slot smallint NOT NULL CHECK (slot >= 1),
    group_id uuid NOT NULL REFERENCES public.groups (id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
    share_minor bigint NOT NULL CHECK (share_minor >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (expense_id, slot),
    CONSTRAINT expense_splits_one_row_per_user UNIQUE (expense_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_expense_splits_user ON public.expense_splits (user_id);
CREATE INDEX IF NOT EXISTS idx_expense_splits_group ON public.expense_splits (group_id);
ALTER TABLE public.expense_splits ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- Equal split with a deterministic remainder
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.split_equal_shares(p_total bigint, p_member_ids uuid[], p_payer uuid)
RETURNS TABLE (user_id uuid, share_minor bigint)
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
    v_members uuid[];   -- participants, user_id ascending (NULL = former member, kept, sorted last)
    v_order uuid[];     -- order in which participants receive leftover minor units
    v_n integer;
    v_base bigint;
    v_remainder bigint;
BEGIN
    IF p_total IS NULL OR p_total < 0 THEN
        RAISE EXCEPTION 'invalid_amount' USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.array_agg(m ORDER BY m NULLS LAST)
    INTO v_members
    FROM (
        SELECT DISTINCT m FROM pg_catalog.unnest(p_member_ids) AS m WHERE m IS NOT NULL
        UNION ALL
        SELECT m FROM pg_catalog.unnest(p_member_ids) AS m WHERE m IS NULL
    ) AS participants;

    v_n := COALESCE(pg_catalog.cardinality(v_members), 0);
    IF v_n = 0 THEN
        RAISE EXCEPTION 'no_split_members' USING ERRCODE = '22023';
    END IF;

    v_base := p_total / v_n;
    v_remainder := p_total - v_base * v_n;   -- 0 <= v_remainder < v_n

    -- Remainder distribution rule (deterministic)
    -- Each of the first v_remainder participants in v_order receives one extra minor unit.
    -- Order: the payer first (when the payer is a participant), then everyone else by user_id
    -- ascending. Same inputs always give the same shares, and the shares sum exactly to p_total.
    IF p_payer IS NOT NULL AND p_payer = ANY (v_members) THEN
        v_order := pg_catalog.array_prepend(p_payer, pg_catalog.array_remove(v_members, p_payer));
    ELSE
        v_order := v_members;
    END IF;
    FOR i IN 1 .. v_n LOOP
        user_id := v_order[i];
        share_minor := v_base + CASE WHEN i <= v_remainder THEN 1 ELSE 0 END;
        RETURN NEXT;
    END LOOP;
    -- End of remainder distribution rule
END;
$$;
REVOKE ALL ON FUNCTION public.split_equal_shares(bigint, uuid[], uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.split_equal_shares(bigint, uuid[], uuid) TO authenticated, service_role;

-- Current split participants of a group: approved admins and members (viewers and pending excluded).
CREATE OR REPLACE FUNCTION public.group_split_member_ids(p_group_id uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT pg_catalog.array_agg(gm.user_id ORDER BY gm.user_id)
    FROM public.group_members AS gm
    WHERE gm.group_id = p_group_id AND gm.status = 'approved' AND gm.role IN ('admin', 'member');
$$;
REVOKE ALL ON FUNCTION public.group_split_member_ids(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.group_split_member_ids(uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- Trigger: write splits for group expenses
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expense_splits_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_participants uuid[];
BEGIN
    IF NEW.group_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.amount_minor = OLD.amount_minor
           AND (NEW.user_id IS NOT DISTINCT FROM OLD.user_id OR NEW.user_id IS NULL) THEN
            RETURN NULL;
        END IF;
        -- Exactly the participants frozen at creation; current membership is never consulted.
        SELECT pg_catalog.array_agg(s.user_id ORDER BY s.slot)
        INTO v_participants
        FROM public.expense_splits AS s
        WHERE s.expense_id = NEW.id;
        DELETE FROM public.expense_splits AS s WHERE s.expense_id = NEW.id;
        IF v_participants IS NULL THEN
            -- No split rows (legacy data only): the payer carries the whole amount.
            v_participants := ARRAY[NEW.user_id];
        END IF;
    ELSE
        v_participants := public.group_split_member_ids(NEW.group_id);
    END IF;

    INSERT INTO public.expense_splits (expense_id, slot, group_id, user_id, share_minor)
    SELECT NEW.id, s.ord::smallint, NEW.group_id, s.user_id, s.share_minor
    FROM public.split_equal_shares(NEW.amount_minor, v_participants, NEW.user_id)
         WITH ORDINALITY AS s (user_id, share_minor, ord);

    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.expense_splits_sync() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_expense_splits_insert ON public.expenses;
CREATE TRIGGER trigger_expense_splits_insert
    AFTER INSERT ON public.expenses
    FOR EACH ROW
    WHEN (NEW.group_id IS NOT NULL)
    EXECUTE FUNCTION public.expense_splits_sync();

DROP TRIGGER IF EXISTS trigger_expense_splits_amount ON public.expenses;
CREATE TRIGGER trigger_expense_splits_amount
    AFTER UPDATE OF amount_minor, user_id ON public.expenses
    FOR EACH ROW
    WHEN (NEW.group_id IS NOT NULL
          AND (NEW.amount_minor IS DISTINCT FROM OLD.amount_minor
               OR (NEW.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id)))
    EXECUTE FUNCTION public.expense_splits_sync();

-- -----------------------------------------------------------------------------
-- Lock: expenses shared with departed participants
-- -----------------------------------------------------------------------------
-- true when the participants of a group expense (split rows plus p_payer) include a NULL user or
-- someone without an approved membership of p_group_id. false for a personal expense.
CREATE OR REPLACE FUNCTION public.expense_has_departed_participant(p_expense_id uuid, p_group_id uuid, p_payer uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT p_group_id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM (
            SELECT s.user_id FROM public.expense_splits AS s WHERE s.expense_id = p_expense_id
            UNION ALL
            SELECT p_payer
        ) AS participant (user_id)
        WHERE participant.user_id IS NULL
           OR NOT EXISTS (
               SELECT 1 FROM public.group_members AS gm
               WHERE gm.group_id = p_group_id AND gm.user_id = participant.user_id AND gm.status = 'approved'
           )
    );
$$;
REVOKE ALL ON FUNCTION public.expense_has_departed_participant(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expense_has_departed_participant(uuid, uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.expenses_departed_member_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Key-share lock on the group: membership RPCs (leave_group, remove_member, ...) lock the group
    -- row FOR UPDATE, so this check and a concurrent departure run one after the other. A group that
    -- no longer exists is being deleted as a whole (FK cascade): its expenses go with it.
    PERFORM 1 FROM public.groups AS g WHERE g.id = OLD.group_id FOR KEY SHARE;
    IF NOT FOUND THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF public.expense_has_departed_participant(OLD.id, OLD.group_id, OLD.user_id) THEN
        RAISE EXCEPTION 'expense_locked_member_left' USING ERRCODE = 'P0001',
            DETAIL = 'A participant of this expense is no longer a member of the group.',
            HINT = 'Only the title, category, note, date and receipt can still be edited.';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
REVOKE ALL ON FUNCTION public.expenses_departed_member_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_expenses_departed_guard_update ON public.expenses;
CREATE TRIGGER trigger_expenses_departed_guard_update
    BEFORE UPDATE OF amount_minor, user_id ON public.expenses
    FOR EACH ROW
    WHEN (OLD.group_id IS NOT NULL
          AND (NEW.amount_minor IS DISTINCT FROM OLD.amount_minor
               OR (NEW.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id)))
    EXECUTE FUNCTION public.expenses_departed_member_guard();

DROP TRIGGER IF EXISTS trigger_expenses_departed_guard_delete ON public.expenses;
CREATE TRIGGER trigger_expenses_departed_guard_delete
    BEFORE DELETE ON public.expenses
    FOR EACH ROW
    WHEN (OLD.group_id IS NOT NULL)
    EXECUTE FUNCTION public.expenses_departed_member_guard();

-- -----------------------------------------------------------------------------
-- Payer integrity: the payer of a group expense is an approved admin or member
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expenses_payer_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        -- Only the foreign-key action of an account deletion clears the payer (UPDATE only).
        IF TG_OP = 'UPDATE'
           AND pg_catalog.pg_trigger_depth() > 1
           AND COALESCE(pg_catalog.current_setting('exevra.account_deletion', true), '') = 'on'
           AND NOT EXISTS (SELECT 1 FROM auth.users AS u WHERE u.id = OLD.user_id) THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'payer_not_member' USING ERRCODE = '42501',
            DETAIL = 'A group expense needs a payer; it is cleared only when the payer''s account is deleted.';
    END IF;

    -- Same key-share lock as expenses_departed_member_guard: runs before or after a concurrent
    -- leave_group / remove_member, never during it. A missing group is left to the foreign key.
    PERFORM 1 FROM public.groups AS g WHERE g.id = NEW.group_id FOR KEY SHARE;
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.group_members AS gm
        WHERE gm.group_id = NEW.group_id AND gm.user_id = NEW.user_id
          AND gm.status = 'approved' AND gm.role IN ('admin', 'member')
    ) THEN
        RAISE EXCEPTION 'payer_not_member' USING ERRCODE = '42501',
            DETAIL = 'The payer must be an approved admin or member of the group.';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.expenses_payer_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_expenses_payer_guard_insert ON public.expenses;
CREATE TRIGGER trigger_expenses_payer_guard_insert
    BEFORE INSERT ON public.expenses
    FOR EACH ROW
    WHEN (NEW.group_id IS NOT NULL)
    EXECUTE FUNCTION public.expenses_payer_guard();

-- Named to fire after trigger_expenses_departed_guard_update (triggers fire in name order).
DROP TRIGGER IF EXISTS trigger_expenses_payer_guard_update ON public.expenses;
CREATE TRIGGER trigger_expenses_payer_guard_update
    BEFORE UPDATE OF user_id ON public.expenses
    FOR EACH ROW
    WHEN (NEW.group_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id)
    EXECUTE FUNCTION public.expenses_payer_guard();

-- -----------------------------------------------------------------------------
-- Back-fill legacy group expenses (current approved admins and members)
-- -----------------------------------------------------------------------------
INSERT INTO public.expense_splits (expense_id, slot, group_id, user_id, share_minor)
SELECT e.id, s.ord::smallint, e.group_id, s.user_id, s.share_minor
FROM public.expenses AS e
CROSS JOIN LATERAL (SELECT COALESCE(public.group_split_member_ids(e.group_id), ARRAY[e.user_id]) AS ids) AS m
CROSS JOIN LATERAL public.split_equal_shares(e.amount_minor, m.ids, e.user_id)
     WITH ORDINALITY AS s (user_id, share_minor, ord)
WHERE e.group_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.expense_splits AS x WHERE x.expense_id = e.id);

-- -----------------------------------------------------------------------------
-- Privileges and RLS: readable by approved members of the group; written only by the trigger.
-- -----------------------------------------------------------------------------
REVOKE ALL ON TABLE public.expense_splits FROM anon, authenticated;
GRANT SELECT ON TABLE public.expense_splits TO authenticated;
GRANT ALL ON TABLE public.expense_splits TO service_role;

DROP POLICY IF EXISTS expense_splits_select_member ON public.expense_splits;
CREATE POLICY expense_splits_select_member ON public.expense_splits
    FOR SELECT TO authenticated
    USING (group_id IN (SELECT public.get_auth_user_groups()));
