-- =============================================================================
-- Spending insights bucketed in the user's time zone
--
-- get_expense_insights(p_scope, p_group_id, p_timeframe, p_tz, p_as_of) -> jsonb   (SECURITY INVOKER)
--   p_scope     'personal': the caller's personal expenses PLUS the caller's own share (expense_splits)
--                           of expenses in groups they currently belong to;
--               'group':    every expense of p_group_id (caller must be an approved member, viewers ok).
--   p_timeframe 'week'  = the last 7 local days including today, one bucket per day;
--               'month' = the last 30 local days including today, one bucket per day;
--               'year'  = the last 12 calendar months including the current one, one bucket per month.
--               Every bucket is present (zero-filled).
--   p_tz        IANA zone from pg_timezone_names; NULL = the caller's profile time zone.
--               Buckets use date_trunc on (spent_at AT TIME ZONE p_tz).
--   p_as_of     reference instant (default now()); "today" is its local date.
-- Amounts are never added across currencies: the result holds one block per currency, the primary
-- currency first (group currency, or the caller's profile currency in personal scope).
-- Replaces the old get_expense_insights(text, uuid), dropped earlier in this series.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_expense_insights(
    p_scope text DEFAULT 'personal',
    p_group_id uuid DEFAULT NULL,
    p_timeframe text DEFAULT 'month',
    p_tz text DEFAULT NULL,
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
    v_tz text;
    v_primary text;
    v_today date;
    v_start date;
    v_end date;
    v_unit text;
    v_days integer;
    v_range_start timestamptz;
    v_range_end timestamptz;
    v_currencies jsonb;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_scope IS NULL OR p_scope NOT IN ('personal', 'group') THEN
        RAISE EXCEPTION 'invalid_scope' USING ERRCODE = '22023';
    END IF;
    IF p_timeframe IS NULL OR p_timeframe NOT IN ('week', 'month', 'year') THEN
        RAISE EXCEPTION 'invalid_timeframe' USING ERRCODE = '22023';
    END IF;

    v_tz := NULLIF(pg_catalog.btrim(p_tz), '');
    IF v_tz IS NULL THEN
        SELECT p.timezone INTO v_tz FROM public.profiles AS p WHERE p.id = v_uid;
        v_tz := COALESCE(v_tz, 'UTC');
    END IF;
    IF NOT public.is_valid_timezone(v_tz) THEN
        RAISE EXCEPTION 'invalid_timezone' USING ERRCODE = '22023';
    END IF;

    IF p_scope = 'group' THEN
        IF p_group_id IS NULL THEN
            RAISE EXCEPTION 'invalid_group' USING ERRCODE = '22023';
        END IF;
        IF public.group_role(p_group_id) IS NULL THEN
            RAISE EXCEPTION 'not_group_member' USING ERRCODE = '42501';
        END IF;
        SELECT g.currency::text INTO v_primary FROM public.groups AS g WHERE g.id = p_group_id;
    ELSE
        IF p_group_id IS NOT NULL THEN
            RAISE EXCEPTION 'invalid_group' USING ERRCODE = '22023';
        END IF;
        SELECT p.currency::text INTO v_primary FROM public.profiles AS p WHERE p.id = v_uid;
    END IF;
    v_primary := COALESCE(v_primary, 'INR');

    -- Local calendar window.
    v_today := (v_as_of AT TIME ZONE v_tz)::date;
    v_end := v_today;
    IF p_timeframe = 'week' THEN
        v_start := v_today - 6;
        v_unit := 'day';
    ELSIF p_timeframe = 'month' THEN
        v_start := v_today - 29;
        v_unit := 'day';
    ELSE
        v_start := (pg_catalog.date_trunc('month', v_today::timestamp) - interval '11 months')::date;
        v_unit := 'month';
    END IF;
    v_days := v_end - v_start + 1;
    v_range_start := v_start::timestamp AT TIME ZONE v_tz;
    v_range_end := (v_end + 1)::timestamp AT TIME ZONE v_tz;

    WITH src AS (
        SELECT e.id, e.title, e.category, e.currency::text AS currency, e.spent_at, e.group_id,
               e.amount_minor AS amount
        FROM public.expenses AS e
        WHERE p_scope = 'personal' AND e.group_id IS NULL AND e.user_id = v_uid
          AND e.spent_at >= v_range_start AND e.spent_at < v_range_end
        UNION ALL
        SELECT e.id, e.title, e.category, e.currency::text, e.spent_at, e.group_id, s.share_minor
        FROM public.expense_splits AS s
        JOIN public.expenses AS e ON e.id = s.expense_id
        WHERE p_scope = 'personal' AND s.user_id = v_uid AND s.share_minor > 0
          AND e.spent_at >= v_range_start AND e.spent_at < v_range_end
        UNION ALL
        SELECT e.id, e.title, e.category, e.currency::text, e.spent_at, e.group_id, e.amount_minor
        FROM public.expenses AS e
        WHERE p_scope = 'group' AND e.group_id = p_group_id
          AND e.spent_at >= v_range_start AND e.spent_at < v_range_end
    ),
    contrib AS (
        SELECT src.*,
               pg_catalog.date_trunc(v_unit, src.spent_at AT TIME ZONE v_tz)::date AS bucket
        FROM src
    ),
    buckets AS (
        SELECT gs::date AS bucket
        FROM pg_catalog.generate_series(v_start::timestamp, v_end::timestamp,
                                        CASE WHEN v_unit = 'day' THEN interval '1 day' ELSE interval '1 month' END) AS gs
    ),
    per_currency AS (
        SELECT c.currency,
               COALESCE((SELECT pg_catalog.sum(x.amount) FROM contrib AS x WHERE x.currency = c.currency), 0)::bigint AS total,
               (SELECT pg_catalog.count(*) FROM contrib AS x WHERE x.currency = c.currency) AS cnt
        FROM (SELECT DISTINCT x.currency FROM contrib AS x UNION SELECT v_primary) AS c
    )
    SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
            'currency', pc.currency,
            'minor_units', public.currency_minor_units(pc.currency),
            'total_minor', pc.total,
            'expense_count', pc.cnt,
            'average_daily_minor', pg_catalog.round(pc.total::numeric / v_days)::bigint,
            'categories', COALESCE((
                SELECT pg_catalog.jsonb_agg(
                           pg_catalog.jsonb_build_object(
                               'category', k.category,
                               'total_minor', k.total,
                               'count', k.cnt,
                               'percentage', CASE WHEN pc.total > 0
                                                  THEN pg_catalog.round(100.0 * k.total / pc.total, 2) ELSE 0 END)
                           ORDER BY k.total DESC, k.category)
                FROM (SELECT x.category, pg_catalog.sum(x.amount)::bigint AS total, pg_catalog.count(*) AS cnt
                      FROM contrib AS x WHERE x.currency = pc.currency GROUP BY x.category) AS k
            ), '[]'::jsonb),
            'series', (
                SELECT pg_catalog.jsonb_agg(
                           pg_catalog.jsonb_build_object(
                               'bucket', pg_catalog.to_char(y.bucket, CASE WHEN v_unit = 'day' THEN 'YYYY-MM-DD' ELSE 'YYYY-MM' END),
                               'total_minor', y.total,
                               'count', y.cnt)
                           ORDER BY y.bucket)
                FROM (SELECT b.bucket, COALESCE(pg_catalog.sum(x.amount), 0)::bigint AS total, pg_catalog.count(x.id) AS cnt
                      FROM buckets AS b
                      LEFT JOIN contrib AS x ON x.bucket = b.bucket AND x.currency = pc.currency
                      GROUP BY b.bucket) AS y
            ),
            'highest', (
                SELECT pg_catalog.jsonb_build_object('id', x.id, 'title', x.title, 'category', x.category,
                                                     'amount_minor', x.amount, 'spent_at', x.spent_at,
                                                     'group_id', x.group_id)
                FROM contrib AS x WHERE x.currency = pc.currency
                ORDER BY x.amount DESC, x.spent_at DESC, x.id
                LIMIT 1
            )
        )
        ORDER BY (pc.currency = v_primary) DESC, pc.total DESC, pc.currency
    )
    INTO v_currencies
    FROM per_currency AS pc;

    RETURN pg_catalog.jsonb_build_object(
        'scope', p_scope,
        'group_id', p_group_id,
        'timeframe', p_timeframe,
        'timezone', v_tz,
        'bucket', v_unit,
        'start_date', v_start,
        'end_date', v_end,
        'day_count', v_days,
        'range_start', v_range_start,
        'range_end', v_range_end,
        'primary_currency', v_primary,
        'currencies', COALESCE(v_currencies, '[]'::jsonb)
    );
END;
$$;
REVOKE ALL ON FUNCTION public.get_expense_insights(text, uuid, text, text, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_expense_insights(text, uuid, text, text, timestamptz) TO authenticated, service_role;
