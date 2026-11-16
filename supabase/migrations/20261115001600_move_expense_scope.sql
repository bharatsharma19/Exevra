-- =============================================================================
-- Moving an expense between personal and group scope
--
-- move_expense_scope(p_expense_id uuid, p_group_id uuid) -> public.expenses   (authenticated only)
--   p_group_id NULL      group expense -> personal expense of the payer;
--   p_group_id non-NULL  personal expense -> group expense, or group expense -> another group.
--
-- One transaction: the old row is deleted (its splits go with it) and a new row is inserted with a
-- server-generated id, so expenses.group_id stays immutable for every direct write and realtime
-- subscribers of both scopes see a DELETE and an INSERT. The new row keeps the payer, title,
-- amount_minor, currency, category, spent_at, note and receipt_url; created_at/updated_at are new.
-- A new group expense is split by the normal insert trigger among the target group's current
-- approved admins and members.
--
-- Rules (checked in this order):
--   * caller signed in (42501 not_authenticated);
--   * the expense is visible to the caller: their own personal expense, or an expense of a group where
--     they are an approved member (P0002 expense_not_found otherwise, also for a NULL id);
--   * the caller is the payer (42501 not_expense_payer); even the group admin cannot move someone
--     else's expense;
--   * the target differs from the current scope (22023 invalid_target);
--   * a group expense: the caller is still an approved admin or member of its group (42501
--     not_group_member, e.g. after being made a viewer) and the expense is not locked by a departed
--     participant (P0001 expense_locked_member_left);
--   * a target group: it exists (P0002 group_not_found), the caller is an approved admin or member of
--     it (42501 not_group_member: viewers, pending and non-members) and the expense currency equals the
--     group currency (22023 currency_mismatch);
--   * a personal target: the currency is supported (22023 invalid_currency);
--   * the inserted row passes the usual expense checks (e.g. a legacy spent_at outside the accepted
--     range raises 22023 invalid_date; fix the date first).
-- The expense row is locked first, then the groups (key share), the same order as the expense lock
-- trigger, so a concurrent leave_group/remove_member runs before or after the move, never during it.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.move_expense_scope(p_expense_id uuid, p_group_id uuid)
RETURNS public.expenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_old public.expenses%ROWTYPE;
    v_new public.expenses%ROWTYPE;
    v_target_currency text;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_old FROM public.expenses AS e WHERE e.id = p_expense_id FOR UPDATE;
    IF NOT FOUND
       OR (v_old.group_id IS NULL AND v_old.user_id IS DISTINCT FROM v_uid)
       OR (v_old.group_id IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM public.group_members AS gm
               WHERE gm.group_id = v_old.group_id AND gm.user_id = v_uid AND gm.status = 'approved')) THEN
        RAISE EXCEPTION 'expense_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_old.user_id IS DISTINCT FROM v_uid THEN
        RAISE EXCEPTION 'not_expense_payer' USING ERRCODE = '42501',
            DETAIL = 'Only the payer can move an expense.';
    END IF;
    IF v_old.group_id IS NOT DISTINCT FROM p_group_id THEN
        RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023',
            DETAIL = 'The expense is already in that scope.';
    END IF;

    -- Source group: the caller may still write there and nobody who shares the expense has left.
    IF v_old.group_id IS NOT NULL THEN
        PERFORM 1 FROM public.groups AS g WHERE g.id = v_old.group_id FOR KEY SHARE;
        IF NOT EXISTS (SELECT 1 FROM public.group_members AS gm
                       WHERE gm.group_id = v_old.group_id AND gm.user_id = v_uid
                         AND gm.status = 'approved' AND gm.role IN ('admin', 'member')) THEN
            RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501',
                DETAIL = 'Only an approved admin or member can move an expense out of the group.';
        END IF;
        IF public.expense_has_departed_participant(v_old.id, v_old.group_id, v_old.user_id) THEN
            RAISE EXCEPTION 'expense_locked_member_left' USING ERRCODE = 'P0001',
                DETAIL = 'A participant of this expense is no longer a member of the group.';
        END IF;
    END IF;

    -- Target scope.
    IF p_group_id IS NOT NULL THEN
        SELECT g.currency::text INTO v_target_currency
        FROM public.groups AS g WHERE g.id = p_group_id FOR KEY SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'group_not_found' USING ERRCODE = 'P0002';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.group_members AS gm
                       WHERE gm.group_id = p_group_id AND gm.user_id = v_uid
                         AND gm.status = 'approved' AND gm.role IN ('admin', 'member')) THEN
            RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501',
                DETAIL = 'Only an approved admin or member can add expenses to the group.';
        END IF;
        IF v_old.currency::text <> v_target_currency THEN
            RAISE EXCEPTION 'currency_mismatch' USING ERRCODE = '22023',
                DETAIL = 'A group expense must use the group currency.';
        END IF;
    ELSIF NOT public.is_supported_currency(v_old.currency::text) THEN
        RAISE EXCEPTION 'invalid_currency' USING ERRCODE = '22023';
    END IF;

    DELETE FROM public.expenses AS e WHERE e.id = v_old.id;

    INSERT INTO public.expenses (user_id, group_id, title, amount_minor, currency, category, spent_at, note, receipt_url)
    VALUES (v_old.user_id, p_group_id, v_old.title, v_old.amount_minor, v_old.currency, v_old.category,
            v_old.spent_at, v_old.note, v_old.receipt_url)
    RETURNING * INTO v_new;

    RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION public.move_expense_scope(uuid, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.move_expense_scope(uuid, uuid) TO authenticated;
