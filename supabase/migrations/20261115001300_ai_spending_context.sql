-- =============================================================================
-- Spending context for the AI assistant
--
-- get_ai_spending_context(p_tz, p_days, p_as_of) -> jsonb   (SECURITY INVOKER: RLS applies)
--   Summarises the CALLER'S OWN spending for the last p_days local days (including today):
--   personal expenses in full plus the caller's own share_minor (expense_splits) of group expenses in
--   groups they currently belong to. This is the same definition as get_expense_insights' personal
--   scope. Other members' amounts, names and emails are never included.
--   p_tz    IANA zone (validated against pg_timezone_names); NULL = the caller's profile time zone.
--   p_days  1..366 (default 90; NULL or outside the range: 22023 invalid_range).
--   p_as_of reference instant (default now()); used by tests to fix "today". Must be finite, not before
--           2000-01-01 (in any zone) and at most one year after now() (22023 invalid_date).
--   The month window is checked (at most 13 months, 22023 invalid_range) before any series is generated.
--   Requires profiles.ai_consent = true, else P0001 'consent_required'. The ai-chat Edge Function checks
--   consent itself before calling; this check is defence in depth, and the key is the function's own
--   error code, so its generic P0001 mapping answers 403 consent_required.
--   Amounts are integer minor units and are never added across currencies.
--   Titles, categories and group names are returned as plain JSON strings; the caller (Edge Function)
--   must treat them as data, never as instructions.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_ai_spending_context(
    p_tz text,
    p_days integer DEFAULT 90,
    p_as_of timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_as_of timestamptz := COALESCE(p_as_of, pg_catalog.now());
    v_profile record;
    v_tz text;
    v_primary text;
    v_today date;
    v_start date;
    v_range_start timestamptz;
    v_range_end timestamptz;
    v_currencies jsonb;
    v_recent jsonb;
    v_groups jsonb;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_days IS NULL OR p_days NOT BETWEEN 1 AND 366 THEN
        RAISE EXCEPTION 'invalid_range' USING ERRCODE = '22023',
            DETAIL = 'p_days must be between 1 and 366.';
    END IF;
    -- The reference instant: finite, not before 2000-01-01 anywhere, at most a year ahead (the same
    -- range as expenses.spent_at). NULL = now().
    IF p_as_of IS NOT NULL
       AND (NOT pg_catalog.isfinite(p_as_of)
            OR p_as_of < '2000-01-01T00:00:00+14'::timestamptz
            OR p_as_of > pg_catalog.now() + interval '1 year') THEN
        RAISE EXCEPTION 'invalid_date' USING ERRCODE = '22023',
            DETAIL = 'p_as_of must be between 2000-01-01 and one year from now.';
    END IF;

    SELECT p.ai_consent, p.currency::text AS currency, p.timezone INTO v_profile
    FROM public.profiles AS p WHERE p.id = v_uid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF NOT COALESCE(v_profile.ai_consent, false) THEN
        RAISE EXCEPTION 'consent_required' USING ERRCODE = 'P0001';
    END IF;

    v_tz := COALESCE(NULLIF(pg_catalog.btrim(p_tz), ''), v_profile.timezone, 'UTC');
    IF NOT public.is_valid_timezone(v_tz) THEN
        RAISE EXCEPTION 'invalid_timezone' USING ERRCODE = '22023';
    END IF;
    v_primary := COALESCE(v_profile.currency, 'INR');

    v_today := (v_as_of AT TIME ZONE v_tz)::date;
    v_start := v_today - (p_days - 1);
    v_range_start := v_start::timestamp AT TIME ZONE v_tz;
    v_range_end := (v_today + 1)::timestamp AT TIME ZONE v_tz;
    -- Guard before generate_series: at most 366 days, i.e. at most 13 calendar months.
    IF v_today - v_start + 1 NOT BETWEEN 1 AND 366
       OR (pg_catalog.date_part('year', v_today) - pg_catalog.date_part('year', v_start)) * 12
          + pg_catalog.date_part('month', v_today) - pg_catalog.date_part('month', v_start) + 1 > 13 THEN
        RAISE EXCEPTION 'invalid_range' USING ERRCODE = '22023',
            DETAIL = 'The context window must cover 1 to 366 days.';
    END IF;

    WITH src AS (
        SELECT e.id, e.title, e.category, e.currency::text AS currency, e.spent_at,
               NULL::uuid AS group_id, e.amount_minor AS amount, false AS is_group_share
        FROM public.expenses AS e
        WHERE e.group_id IS NULL AND e.user_id = v_uid
          AND e.spent_at >= v_range_start AND e.spent_at < v_range_end
        UNION ALL
        SELECT e.id, e.title, e.category, e.currency::text, e.spent_at, e.group_id, s.share_minor, true
        FROM public.expense_splits AS s
        JOIN public.expenses AS e ON e.id = s.expense_id
        WHERE s.user_id = v_uid AND s.share_minor > 0
          AND e.spent_at >= v_range_start AND e.spent_at < v_range_end
    ),
    mine AS (
        SELECT src.*, pg_catalog.date_trunc('month', src.spent_at AT TIME ZONE v_tz)::date AS month
        FROM src
    ),
    months AS (
        SELECT gs::date AS month
        FROM pg_catalog.generate_series(pg_catalog.date_trunc('month', v_start::timestamp),
                                        pg_catalog.date_trunc('month', v_today::timestamp),
                                        interval '1 month') AS gs
    ),
    per_currency AS (
        SELECT cur.currency,
               COALESCE(pg_catalog.sum(r.amount), 0)::bigint AS total,
               COALESCE(pg_catalog.sum(r.amount) FILTER (WHERE NOT r.is_group_share), 0)::bigint AS personal_total,
               COALESCE(pg_catalog.sum(r.amount) FILTER (WHERE r.is_group_share), 0)::bigint AS group_total,
               pg_catalog.count(r.id) AS cnt
        FROM (SELECT DISTINCT r2.currency FROM mine AS r2 UNION SELECT v_primary) AS cur (currency)
        LEFT JOIN mine AS r ON r.currency = cur.currency
        GROUP BY cur.currency
    )
    SELECT
        (SELECT pg_catalog.jsonb_agg(
             pg_catalog.jsonb_build_object(
                 'currency', c.currency,
                 'minor_units', public.currency_minor_units(c.currency),
                 'total_minor', c.total,
                 'personal_total_minor', c.personal_total,
                 'group_share_total_minor', c.group_total,
                 'expense_count', c.cnt,
                 'categories', COALESCE((
                     SELECT pg_catalog.jsonb_agg(
                                pg_catalog.jsonb_build_object('category', k.category, 'total_minor', k.total,
                                                              'count', k.cnt)
                                ORDER BY k.total DESC, k.category)
                     FROM (SELECT r.category, pg_catalog.sum(r.amount)::bigint AS total, pg_catalog.count(*) AS cnt
                           FROM mine AS r WHERE r.currency = c.currency
                           GROUP BY r.category) AS k
                 ), '[]'::jsonb),
                 'months', (
                     SELECT pg_catalog.jsonb_agg(
                                pg_catalog.jsonb_build_object('month', pg_catalog.to_char(m.month, 'YYYY-MM'),
                                                              'total_minor', m.total, 'count', m.cnt)
                                ORDER BY m.month)
                     FROM (SELECT mo.month, COALESCE(pg_catalog.sum(r.amount), 0)::bigint AS total,
                                  pg_catalog.count(r.id) AS cnt
                           FROM months AS mo
                           LEFT JOIN mine AS r ON r.currency = c.currency AND r.month = mo.month
                           GROUP BY mo.month) AS m
                 )
             )
             ORDER BY (c.currency = v_primary) DESC, c.total DESC, c.currency)
         FROM per_currency AS c),
        (SELECT COALESCE(pg_catalog.jsonb_agg(x.item ORDER BY x.spent_at DESC, x.id), '[]'::jsonb)
         FROM (
             SELECT r.id, r.spent_at,
                    pg_catalog.jsonb_build_object(
                        'date', pg_catalog.to_char(r.spent_at AT TIME ZONE v_tz, 'YYYY-MM-DD'),
                        'title', r.title,
                        'category', r.category,
                        'amount_minor', r.amount,
                        'currency', r.currency,
                        'is_group_share', r.is_group_share,
                        'group_name', g.name) AS item
             FROM mine AS r
             LEFT JOIN public.groups AS g ON g.id = r.group_id
             ORDER BY r.spent_at DESC, r.id
             LIMIT 15
         ) AS x)
    INTO v_currencies, v_recent;

    SELECT COALESCE(pg_catalog.jsonb_agg(
               pg_catalog.jsonb_build_object('name', g.name, 'currency', g.currency::text, 'role', gm.role)
               ORDER BY g.name, g.id), '[]'::jsonb)
    INTO v_groups
    FROM public.group_members AS gm
    JOIN public.groups AS g ON g.id = gm.group_id
    WHERE gm.user_id = v_uid AND gm.status = 'approved';

    RETURN pg_catalog.jsonb_build_object(
        'timezone', v_tz,
        'today', v_today,
        'days', p_days,
        'start_date', v_start,
        'end_date', v_today,
        'range_start', v_range_start,
        'range_end', v_range_end,
        'primary_currency', v_primary,
        'share_rule', 'Personal expenses count in full. Group expenses count only as the user''s own share '
                      || '(an equal split among the group''s members when the expense was added).',
        'currencies', COALESCE(v_currencies, '[]'::jsonb),
        'recent_expenses', v_recent,
        'groups', v_groups
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_ai_spending_context(text, integer, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_spending_context(text, integer, timestamptz) TO authenticated, service_role;
