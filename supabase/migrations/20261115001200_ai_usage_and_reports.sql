-- =============================================================================
-- AI assistant support: usage metering, quota and content reports
--
-- * ai_usage_events: one row per assistant request (metadata only: provider, model, status, latency,
--   token counts). Message content is never stored. Readable by its owner; written only by the RPCs.
-- * consume_ai_quota(p_daily_limit, p_per_minute) -> uuid: atomically checks the caller's request
--   count for the current UTC day and the last 60 seconds and, if both are under the limits, records a
--   'reserved' event and returns its id. Otherwise raises P0001 'quota_exceeded' (DETAIL reset_at=...)
--   or 'rate_limited' (DETAIL retry_after=...). Every reservation counts, whatever its final status.
-- * finish_ai_usage(p_event_id, ...) completes the caller's own reserved event with the outcome.
-- * ai_reports: a user can report an assistant answer (reason + excerpt). Insert own only, read own
--   only, never updated or deleted by clients. At most 30 reports per user per rolling day.
-- * purge_old_ai_usage(): service_role only, deletes usage events older than 180 days.
--
-- Idempotent; the tables are new, so no legacy data needs converting.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ai_usage_events
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_usage_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    provider text,
    model text,
    status text NOT NULL DEFAULT 'reserved',
    latency_ms integer,
    input_tokens integer,
    output_tokens integer
);

ALTER TABLE public.ai_usage_events DROP CONSTRAINT IF EXISTS ai_usage_events_status_valid;
ALTER TABLE public.ai_usage_events ADD CONSTRAINT ai_usage_events_status_valid
    CHECK (status IN ('reserved', 'succeeded', 'failed', 'refused', 'interrupted', 'cancelled'));
ALTER TABLE public.ai_usage_events DROP CONSTRAINT IF EXISTS ai_usage_events_provider_format;
ALTER TABLE public.ai_usage_events ADD CONSTRAINT ai_usage_events_provider_format
    CHECK (provider IS NULL OR provider ~ '^[a-z0-9][a-z0-9._-]{0,39}$');
ALTER TABLE public.ai_usage_events DROP CONSTRAINT IF EXISTS ai_usage_events_model_format;
ALTER TABLE public.ai_usage_events ADD CONSTRAINT ai_usage_events_model_format
    CHECK (model IS NULL OR model ~ '^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,99}$');
ALTER TABLE public.ai_usage_events DROP CONSTRAINT IF EXISTS ai_usage_events_metrics_range;
ALTER TABLE public.ai_usage_events ADD CONSTRAINT ai_usage_events_metrics_range
    CHECK (
        (latency_ms IS NULL OR latency_ms BETWEEN 0 AND 3600000)
        AND (input_tokens IS NULL OR input_tokens BETWEEN 0 AND 10000000)
        AND (output_tokens IS NULL OR output_tokens BETWEEN 0 AND 10000000)
    );
ALTER TABLE public.ai_usage_events DROP CONSTRAINT IF EXISTS ai_usage_events_finished_consistent;
ALTER TABLE public.ai_usage_events ADD CONSTRAINT ai_usage_events_finished_consistent
    CHECK ((status = 'reserved') = (finished_at IS NULL));

-- Quota queries: WHERE user_id = $1 AND created_at >= $2 (also covers the FK).
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_user_created ON public.ai_usage_events (user_id, created_at DESC);

ALTER TABLE public.ai_usage_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_usage_events FROM anon, authenticated;
GRANT SELECT ON TABLE public.ai_usage_events TO authenticated;
GRANT ALL ON TABLE public.ai_usage_events TO service_role;

DROP POLICY IF EXISTS ai_usage_events_select_own ON public.ai_usage_events;
CREATE POLICY ai_usage_events_select_own ON public.ai_usage_events
    FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));

-- -----------------------------------------------------------------------------
-- consume_ai_quota
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.consume_ai_quota(p_daily_limit integer, p_per_minute integer)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_now timestamptz := pg_catalog.now();
    v_day_start timestamptz := pg_catalog.date_trunc('day', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
    v_today integer;
    v_last_minute integer;
    v_oldest timestamptz;
    v_id uuid;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_daily_limit IS NULL OR p_daily_limit NOT BETWEEN 1 AND 1000 THEN
        RAISE EXCEPTION 'invalid_limit' USING ERRCODE = '22023', DETAIL = 'p_daily_limit must be 1..1000.';
    END IF;
    IF p_per_minute IS NULL OR p_per_minute NOT BETWEEN 1 AND 60 THEN
        RAISE EXCEPTION 'invalid_limit' USING ERRCODE = '22023', DETAIL = 'p_per_minute must be 1..60.';
    END IF;

    -- Serialise concurrent requests of the same user so the count and the insert are atomic.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exevra.ai_quota:' || v_uid::text, 0));

    SELECT pg_catalog.count(*) INTO v_today
    FROM public.ai_usage_events AS e
    WHERE e.user_id = v_uid AND e.created_at >= v_day_start;
    IF v_today >= p_daily_limit THEN
        RAISE EXCEPTION 'quota_exceeded' USING ERRCODE = 'P0001',
            DETAIL = 'reset_at=' || pg_catalog.to_char((v_day_start + interval '1 day') AT TIME ZONE 'UTC',
                                                       'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    END IF;

    SELECT pg_catalog.count(*), pg_catalog.min(e.created_at) INTO v_last_minute, v_oldest
    FROM public.ai_usage_events AS e
    WHERE e.user_id = v_uid AND e.created_at > v_now - interval '60 seconds';
    IF v_last_minute >= p_per_minute THEN
        RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'P0001',
            DETAIL = 'retry_after=' || pg_catalog.to_char((v_oldest + interval '60 seconds') AT TIME ZONE 'UTC',
                                                          'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    END IF;

    INSERT INTO public.ai_usage_events (user_id, created_at, status)
    VALUES (v_uid, v_now, 'reserved')
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.consume_ai_quota(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_ai_quota(integer, integer) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- finish_ai_usage
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finish_ai_usage(
    p_event_id uuid,
    p_provider text,
    p_model text,
    p_status text,
    p_latency_ms integer DEFAULT NULL,
    p_input_tokens integer DEFAULT NULL,
    p_output_tokens integer DEFAULT NULL
)
RETURNS public.ai_usage_events
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid uuid := auth.uid();
    v_row public.ai_usage_events;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
    END IF;
    IF p_status IS NULL OR p_status NOT IN ('succeeded', 'failed', 'refused', 'interrupted', 'cancelled') THEN
        RAISE EXCEPTION 'invalid_status' USING ERRCODE = '22023';
    END IF;
    IF (p_latency_ms IS NOT NULL AND p_latency_ms NOT BETWEEN 0 AND 3600000)
       OR (p_input_tokens IS NOT NULL AND p_input_tokens NOT BETWEEN 0 AND 10000000)
       OR (p_output_tokens IS NOT NULL AND p_output_tokens NOT BETWEEN 0 AND 10000000) THEN
        RAISE EXCEPTION 'invalid_metrics' USING ERRCODE = '22023';
    END IF;
    IF (p_provider IS NOT NULL AND p_provider !~ '^[a-z0-9][a-z0-9._-]{0,39}$')
       OR (p_model IS NOT NULL AND p_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/@-]{0,99}$') THEN
        RAISE EXCEPTION 'invalid_provider' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_row FROM public.ai_usage_events AS e
    WHERE e.id = p_event_id AND e.user_id = v_uid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'usage_event_not_found' USING ERRCODE = 'P0002';
    END IF;
    IF v_row.status <> 'reserved' THEN
        RAISE EXCEPTION 'usage_event_finished' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.ai_usage_events AS e
    SET status = p_status,
        provider = p_provider,
        model = p_model,
        latency_ms = p_latency_ms,
        input_tokens = p_input_tokens,
        output_tokens = p_output_tokens,
        finished_at = pg_catalog.now()
    WHERE e.id = v_row.id
    RETURNING * INTO v_row;
    RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.finish_ai_usage(uuid, text, text, text, integer, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finish_ai_usage(uuid, text, text, text, integer, integer, integer)
    TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- purge_old_ai_usage (retention: 180 days)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_old_ai_usage()
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_deleted integer;
BEGIN
    DELETE FROM public.ai_usage_events AS e WHERE e.created_at < pg_catalog.now() - interval '180 days';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN pg_catalog.jsonb_build_object('deleted', v_deleted);
END;
$$;
REVOKE ALL ON FUNCTION public.purge_old_ai_usage() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_ai_usage() TO service_role;

-- Daily cleanup when pg_cron is enabled; otherwise see supabase/README.md.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-old-ai-usage') THEN
            PERFORM cron.unschedule('purge-old-ai-usage');
        END IF;
        PERFORM cron.schedule('purge-old-ai-usage', '37 3 * * *', 'select public.purge_old_ai_usage();');
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- ai_reports
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    provider text,
    reason text NOT NULL,
    message_excerpt text NOT NULL,
    note text
);

ALTER TABLE public.ai_reports DROP CONSTRAINT IF EXISTS ai_reports_reason_valid;
ALTER TABLE public.ai_reports ADD CONSTRAINT ai_reports_reason_valid
    CHECK (reason IN ('inaccurate', 'offensive', 'harmful', 'inappropriate', 'privacy', 'other'));
ALTER TABLE public.ai_reports DROP CONSTRAINT IF EXISTS ai_reports_provider_format;
ALTER TABLE public.ai_reports ADD CONSTRAINT ai_reports_provider_format
    CHECK (provider IS NULL OR provider ~ '^[a-z0-9][a-z0-9._-]{0,39}$');
ALTER TABLE public.ai_reports DROP CONSTRAINT IF EXISTS ai_reports_excerpt_length;
ALTER TABLE public.ai_reports ADD CONSTRAINT ai_reports_excerpt_length
    CHECK (char_length(message_excerpt) BETWEEN 1 AND 2000);
ALTER TABLE public.ai_reports DROP CONSTRAINT IF EXISTS ai_reports_note_length;
ALTER TABLE public.ai_reports ADD CONSTRAINT ai_reports_note_length
    CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500);

CREATE INDEX IF NOT EXISTS idx_ai_reports_user_created ON public.ai_reports (user_id, created_at DESC);

-- Server-set id and timestamp, trimmed note, and at most 30 reports per user per rolling day.
-- SECURITY INVOKER: the count only needs the caller's own rows, which RLS lets them read; a row for
-- another user is rejected by the INSERT policy anyway.
CREATE OR REPLACE FUNCTION public.ai_reports_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    NEW.id := pg_catalog.gen_random_uuid();
    NEW.created_at := pg_catalog.now();
    NEW.note := NULLIF(pg_catalog.btrim(NEW.note), '');
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('exevra.ai_reports:' || NEW.user_id::text, 0));
    IF (SELECT pg_catalog.count(*) FROM public.ai_reports AS r
        WHERE r.user_id = NEW.user_id AND r.created_at > pg_catalog.now() - interval '1 day') >= 30 THEN
        RAISE EXCEPTION 'rate_limited' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.ai_reports_before_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_ai_reports_before_insert ON public.ai_reports;
CREATE TRIGGER trigger_ai_reports_before_insert
    BEFORE INSERT ON public.ai_reports
    FOR EACH ROW EXECUTE FUNCTION public.ai_reports_before_insert();

ALTER TABLE public.ai_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_reports FROM anon, authenticated;
GRANT SELECT ON TABLE public.ai_reports TO authenticated;
GRANT INSERT (user_id, provider, reason, message_excerpt, note) ON TABLE public.ai_reports TO authenticated;
GRANT ALL ON TABLE public.ai_reports TO service_role;

DROP POLICY IF EXISTS ai_reports_select_own ON public.ai_reports;
CREATE POLICY ai_reports_select_own ON public.ai_reports
    FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS ai_reports_insert_own ON public.ai_reports;
CREATE POLICY ai_reports_insert_own ON public.ai_reports
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));
