-- =============================================================================
-- Expense splits
--
-- public.expense_splits holds each participant's share of a group expense in minor units. It is
-- written only by a trigger:
--   * on INSERT of a group expense: an equal split among the group's members at that moment who are
--     approved and have role admin or member (viewers and pending members are excluded);
--   * on UPDATE of amount_minor: the new amount is split again among the SAME participants.
-- Later joins, leaves and role changes never rewrite existing splits. When a participant's account
-- is deleted their user_id becomes NULL (shown as "Former member").
--
-- public.split_equal_shares(total, member_ids, payer) is the single, pure implementation of the
-- equal split. Shares always sum exactly to the total; leftover minor units are assigned by the
-- clearly delimited deterministic rule below.
--
-- Legacy group expenses are back-filled using the group's current approved admins and members.
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
        IF NEW.amount_minor = OLD.amount_minor THEN
            RETURN NULL;
        END IF;
        -- Same participants as before; only the amounts change.
        SELECT pg_catalog.array_agg(s.user_id ORDER BY s.slot)
        INTO v_participants
        FROM public.expense_splits AS s
        WHERE s.expense_id = NEW.id;
        DELETE FROM public.expense_splits AS s WHERE s.expense_id = NEW.id;
    END IF;

    IF v_participants IS NULL THEN
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
    AFTER UPDATE OF amount_minor ON public.expenses
    FOR EACH ROW
    WHEN (NEW.group_id IS NOT NULL AND NEW.amount_minor IS DISTINCT FROM OLD.amount_minor)
    EXECUTE FUNCTION public.expense_splits_sync();

-- -----------------------------------------------------------------------------
-- Back-fill legacy group expenses (current approved admins and members)
-- -----------------------------------------------------------------------------
INSERT INTO public.expense_splits (expense_id, slot, group_id, user_id, share_minor)
SELECT e.id, s.ord::smallint, e.group_id, s.user_id, s.share_minor
FROM public.expenses AS e
CROSS JOIN LATERAL (SELECT public.group_split_member_ids(e.group_id) AS ids) AS m
CROSS JOIN LATERAL public.split_equal_shares(e.amount_minor, m.ids, e.user_id)
     WITH ORDINALITY AS s (user_id, share_minor, ord)
WHERE e.group_id IS NOT NULL
  AND m.ids IS NOT NULL
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
