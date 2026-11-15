-- =============================================================================
-- Group balances, settle-up suggestions, and the settlement RPCs
--
-- Balance of a participant in a group (all in the group currency, minor units):
--   paid_minor        sum of group expenses they paid
--   owed_minor        sum of their expense_splits shares
--   settled_out_minor confirmed settlements they paid (from_user)
--   settled_in_minor  confirmed settlements they received (to_user)
--   net_minor = paid - owed + settled_out - settled_in
-- Positive net: the others owe them. Negative net: they owe the others. Nets of all rows sum to 0.
-- Pending and voided settlements do not count. Former members (deleted accounts, user_id NULL) are
-- aggregated into one 'Former member' row.
--
-- Settle-up suggestions and the settlement limit use the projected balance
--   effective = net + pending_out - pending_in
-- (what the net becomes once every pending settlement is confirmed), restricted to current approved
-- members, so an in-flight settlement is never suggested or recorded twice.
--
-- RPCs (authenticated + service_role):
--   get_group_balances(group)            approved member (viewers included)
--   get_group_settle_suggestions(group)  approved member (viewers included)
--   record_settlement(group, to_user, amount_minor, note)  caller pays; both approved members;
--        amount <= min(caller's projected debt, payee's projected credit), else P0001
--        settlement_exceeds_debt; creates a pending settlement
--   confirm_settlement(id)               only the payee (to_user), only while pending
--   void_settlement(id, reason)          payer, payee or group admin; not already voided
-- Every write appends a row to settlement_events.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Internal: per-user flows of a group (no access check; not callable by clients)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.group_balance_rows(p_group_id uuid)
RETURNS TABLE (
    user_id uuid,
    paid_minor bigint,
    owed_minor bigint,
    settled_out_minor bigint,
    settled_in_minor bigint,
    pending_out_minor bigint,
    pending_in_minor bigint,
    net_minor bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH flows (uid, paid, owed, s_out, s_in, p_out, p_in) AS (
        SELECT e.user_id, e.amount_minor, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint
        FROM public.expenses AS e WHERE e.group_id = p_group_id
        UNION ALL
        SELECT sp.user_id, 0, sp.share_minor, 0, 0, 0, 0
        FROM public.expense_splits AS sp WHERE sp.group_id = p_group_id
        UNION ALL
        SELECT st.from_user, 0, 0,
               CASE WHEN st.status = 'confirmed' THEN st.amount_minor ELSE 0 END, 0,
               CASE WHEN st.status = 'pending' THEN st.amount_minor ELSE 0 END, 0
        FROM public.settlements AS st WHERE st.group_id = p_group_id AND st.status <> 'voided'
        UNION ALL
        SELECT st.to_user, 0, 0, 0,
               CASE WHEN st.status = 'confirmed' THEN st.amount_minor ELSE 0 END, 0,
               CASE WHEN st.status = 'pending' THEN st.amount_minor ELSE 0 END
        FROM public.settlements AS st WHERE st.group_id = p_group_id AND st.status <> 'voided'
        UNION ALL
        -- Current admins and members always get a row, even without activity.
        SELECT gm.user_id, 0, 0, 0, 0, 0, 0
        FROM public.group_members AS gm
        WHERE gm.group_id = p_group_id AND gm.status = 'approved' AND gm.role IN ('admin', 'member')
    )
    SELECT f.uid,
           sum(f.paid)::bigint, sum(f.owed)::bigint, sum(f.s_out)::bigint, sum(f.s_in)::bigint,
           sum(f.p_out)::bigint, sum(f.p_in)::bigint,
           (sum(f.paid) - sum(f.owed) + sum(f.s_out) - sum(f.s_in))::bigint
    FROM flows AS f
    GROUP BY f.uid;
$$;
REVOKE ALL ON FUNCTION public.group_balance_rows(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.group_balance_rows(uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- get_group_balances
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_group_balances(p_group_id uuid)
RETURNS TABLE (
    user_id uuid,
    display_name text,
    paid_minor bigint,
    owed_minor bigint,
    settled_out_minor bigint,
    settled_in_minor bigint,
    net_minor bigint,
    currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF public.group_role(p_group_id) IS NULL THEN
        RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT b.user_id,
           CASE WHEN b.user_id IS NULL OR p.id IS NULL THEN 'Former member' ELSE p.display_name END,
           b.paid_minor, b.owed_minor, b.settled_out_minor, b.settled_in_minor, b.net_minor,
           g.currency::text
    FROM public.group_balance_rows(p_group_id) AS b
    JOIN public.groups AS g ON g.id = p_group_id
    LEFT JOIN public.profiles AS p ON p.id = b.user_id
    ORDER BY b.net_minor DESC, (b.user_id IS NULL), 2, b.user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.get_group_balances(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_balances(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- get_group_settle_suggestions: greedy largest-debtor -> largest-creditor matching
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_group_settle_suggestions(p_group_id uuid)
RETURNS TABLE (from_user uuid, to_user uuid, amount_minor bigint, currency text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
    v_currency text;
    v_cred_ids uuid[];
    v_cred_amt bigint[];
    v_debt_ids uuid[];
    v_debt_amt bigint[];
    v_i integer;
    v_j integer;
    v_x bigint;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF public.group_role(p_group_id) IS NULL THEN
        RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501';
    END IF;
    SELECT g.currency::text INTO v_currency FROM public.groups AS g WHERE g.id = p_group_id;

    -- Projected balances of current approved members (any role).
    SELECT pg_catalog.array_agg(x.uid ORDER BY x.eff DESC, x.uid) FILTER (WHERE x.eff > 0),
           pg_catalog.array_agg(x.eff ORDER BY x.eff DESC, x.uid) FILTER (WHERE x.eff > 0),
           pg_catalog.array_agg(x.uid ORDER BY x.eff ASC, x.uid) FILTER (WHERE x.eff < 0),
           pg_catalog.array_agg(-x.eff ORDER BY x.eff ASC, x.uid) FILTER (WHERE x.eff < 0)
    INTO v_cred_ids, v_cred_amt, v_debt_ids, v_debt_amt
    FROM (
        SELECT b.user_id AS uid, b.net_minor + b.pending_out_minor - b.pending_in_minor AS eff
        FROM public.group_balance_rows(p_group_id) AS b
        JOIN public.group_members AS gm
          ON gm.group_id = p_group_id AND gm.user_id = b.user_id AND gm.status = 'approved'
    ) AS x;

    IF v_cred_ids IS NULL OR v_debt_ids IS NULL THEN
        RETURN;
    END IF;

    LOOP
        -- Largest remaining creditor and debtor (ties: lower user id).
        v_i := NULL;
        FOR v_k IN 1 .. pg_catalog.cardinality(v_cred_ids) LOOP
            IF v_cred_amt[v_k] > 0 AND (v_i IS NULL OR v_cred_amt[v_k] > v_cred_amt[v_i]
                OR (v_cred_amt[v_k] = v_cred_amt[v_i] AND v_cred_ids[v_k] < v_cred_ids[v_i])) THEN
                v_i := v_k;
            END IF;
        END LOOP;
        v_j := NULL;
        FOR v_k IN 1 .. pg_catalog.cardinality(v_debt_ids) LOOP
            IF v_debt_amt[v_k] > 0 AND (v_j IS NULL OR v_debt_amt[v_k] > v_debt_amt[v_j]
                OR (v_debt_amt[v_k] = v_debt_amt[v_j] AND v_debt_ids[v_k] < v_debt_ids[v_j])) THEN
                v_j := v_k;
            END IF;
        END LOOP;
        EXIT WHEN v_i IS NULL OR v_j IS NULL;

        v_x := LEAST(v_cred_amt[v_i], v_debt_amt[v_j]);
        from_user := v_debt_ids[v_j];
        to_user := v_cred_ids[v_i];
        amount_minor := v_x;
        currency := v_currency;
        RETURN NEXT;
        v_cred_amt[v_i] := v_cred_amt[v_i] - v_x;
        v_debt_amt[v_j] := v_debt_amt[v_j] - v_x;
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.get_group_settle_suggestions(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_settle_suggestions(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- record_settlement
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_settlement(
    p_group_id uuid,
    p_to_user uuid,
    p_amount_minor bigint,
    p_note text DEFAULT NULL
)
RETURNS public.settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_note text := NULLIF(pg_catalog.regexp_replace(p_note, '^\s+|\s+$', '', 'g'), '');
    v_from_eff bigint;
    v_to_eff bigint;
    v_limit bigint;
    v_row public.settlements;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_amount_minor IS NULL OR p_amount_minor <= 0 OR p_amount_minor > 100000000000 THEN
        RAISE EXCEPTION 'invalid_amount' USING ERRCODE = '22023';
    END IF;
    IF p_to_user IS NULL OR p_to_user = v_uid THEN
        RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
    END IF;
    IF v_note IS NOT NULL AND pg_catalog.char_length(v_note) > 200 THEN
        RAISE EXCEPTION 'invalid_note' USING ERRCODE = '22023';
    END IF;
    IF public.group_role(p_group_id) IS NULL THEN
        RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.group_members AS gm
        WHERE gm.group_id = p_group_id AND gm.user_id = p_to_user AND gm.status = 'approved'
    ) THEN
        RAISE EXCEPTION 'member_not_found' USING ERRCODE = 'P0002';
    END IF;

    -- One settlement decision at a time per group, so concurrent requests cannot both pass the limit.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('exevra.settlement:' || p_group_id::text, 0));

    SELECT b.net_minor + b.pending_out_minor - b.pending_in_minor INTO v_from_eff
    FROM public.group_balance_rows(p_group_id) AS b WHERE b.user_id = v_uid;
    SELECT b.net_minor + b.pending_out_minor - b.pending_in_minor INTO v_to_eff
    FROM public.group_balance_rows(p_group_id) AS b WHERE b.user_id = p_to_user;

    v_limit := GREATEST(0, LEAST(-COALESCE(v_from_eff, 0), COALESCE(v_to_eff, 0)));
    IF p_amount_minor > v_limit THEN
        RAISE EXCEPTION 'settlement_exceeds_debt' USING ERRCODE = 'P0001',
            DETAIL = pg_catalog.format('max_amount_minor=%s', v_limit);
    END IF;

    INSERT INTO public.settlements (group_id, from_user, to_user, amount_minor, note, status, created_by)
    VALUES (p_group_id, v_uid, p_to_user, p_amount_minor, v_note, 'pending', v_uid)
    RETURNING * INTO v_row;

    INSERT INTO public.settlement_events (settlement_id, group_id, actor, action, details)
    VALUES (v_row.id, p_group_id, v_uid, 'recorded',
            pg_catalog.jsonb_build_object('from_user', v_uid, 'to_user', p_to_user,
                                          'amount_minor', p_amount_minor, 'currency', v_row.currency, 'note', v_note));
    RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.record_settlement(uuid, uuid, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_settlement(uuid, uuid, bigint, text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- confirm_settlement
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_settlement(p_settlement_id uuid)
RETURNS public.settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_row public.settlements;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_row FROM public.settlements AS s WHERE s.id = p_settlement_id FOR UPDATE;
    IF NOT FOUND OR public.group_role(v_row.group_id) IS NULL THEN
        RAISE EXCEPTION 'settlement_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_row.to_user IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'not_settlement_payee' USING ERRCODE = '42501';
    END IF;
    IF v_row.status <> 'pending' THEN
        RAISE EXCEPTION 'settlement_not_pending' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.settlements AS s
    SET status = 'confirmed', confirmed_at = pg_catalog.now()
    WHERE s.id = p_settlement_id
    RETURNING * INTO v_row;

    INSERT INTO public.settlement_events (settlement_id, group_id, actor, action, details)
    VALUES (v_row.id, v_row.group_id, v_uid, 'confirmed',
            pg_catalog.jsonb_build_object('amount_minor', v_row.amount_minor, 'currency', v_row.currency));
    RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_settlement(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_settlement(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- void_settlement
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.void_settlement(p_settlement_id uuid, p_reason text DEFAULT NULL)
RETURNS public.settlements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_reason text := NULLIF(pg_catalog.regexp_replace(p_reason, '^\s+|\s+$', '', 'g'), '');
    v_previous text;
    v_row public.settlements;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF v_reason IS NOT NULL AND pg_catalog.char_length(v_reason) > 200 THEN
        RAISE EXCEPTION 'invalid_reason' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_row FROM public.settlements AS s WHERE s.id = p_settlement_id FOR UPDATE;
    IF NOT FOUND OR public.group_role(v_row.group_id) IS NULL THEN
        RAISE EXCEPTION 'settlement_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_uid IS DISTINCT FROM v_row.from_user AND v_uid IS DISTINCT FROM v_row.to_user
       AND NOT public.is_group_admin(v_row.group_id) THEN
        RAISE EXCEPTION 'not_settlement_party' USING ERRCODE = '42501';
    END IF;
    IF v_row.status = 'voided' THEN
        RAISE EXCEPTION 'settlement_already_voided' USING ERRCODE = 'P0001';
    END IF;
    v_previous := v_row.status;

    UPDATE public.settlements AS s
    SET status = 'voided', voided_at = pg_catalog.now(), voided_by = v_uid, void_reason = v_reason
    WHERE s.id = p_settlement_id
    RETURNING * INTO v_row;

    INSERT INTO public.settlement_events (settlement_id, group_id, actor, action, details)
    VALUES (v_row.id, v_row.group_id, v_uid, 'voided',
            pg_catalog.jsonb_build_object('previous_status', v_previous, 'reason', v_reason));
    RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.void_settlement(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.void_settlement(uuid, text) TO authenticated, service_role;
