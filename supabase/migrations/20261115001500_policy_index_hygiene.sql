-- =============================================================================
-- Policy, privilege, index and Realtime hygiene (final pass over the whole public schema)
--
-- * Every policy is scoped TO authenticated, one command per policy, and uses (select auth.uid());
--   membership helpers appear only as uncorrelated subqueries (group_id IN (SELECT ...)), never as a
--   per-row call such as is_group_admin(group_id).
--   The last exception (invite_code_attempts, FOR ALL to anon and authenticated) is replaced by a
--   deny-all SELECT policy for authenticated; the table has no client privileges at all.
-- * anon holds no privileges on any public table, sequence or function. authenticated holds no
--   privileges on public sequences (no client inserts into a table with an identity column).
-- * Objects created later grant nothing to client roles by default (see 20261115000100).
-- * Client roles (anon, authenticated, and authenticator, which switches to them) cannot create
--   temporary objects. Every SECURITY DEFINER function pins search_path = '', but PostgreSQL still
--   resolves unqualified type and relation names in pg_temp first; without TEMP a session cannot
--   place objects there. PostgREST never needs temporary objects. Every other role keeps TEMP.
-- * Indexes: every foreign key has a covering index; keyset pagination indexes on expenses exist;
--   indexes superseded by those are dropped (re-checked here so a hosted database that still has
--   them is cleaned up).
-- * Realtime: expenses, group_members and settlements are in supabase_realtime.
-- Idempotent.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Policies
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS invite_code_attempts_no_client_access ON public.invite_code_attempts;
DROP POLICY IF EXISTS invite_code_attempts_select_none ON public.invite_code_attempts;
CREATE POLICY invite_code_attempts_select_none ON public.invite_code_attempts
    FOR SELECT TO authenticated
    USING (false);

-- -----------------------------------------------------------------------------
-- anon privileges
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_rel record;
BEGIN
    FOR v_rel IN
        SELECT c.oid::regclass AS rel
        FROM pg_catalog.pg_class AS c
        WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'v', 'm', 'S', 'p')
    LOOP
        EXECUTE pg_catalog.format('REVOKE ALL ON %s FROM anon', v_rel.rel);
    END LOOP;
END;
$$;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM anon;

-- Default privileges (future objects grant nothing to client roles) are set at the start of the
-- series, in 20261115000100_function_hardening.sql.

-- -----------------------------------------------------------------------------
-- Sequences: no client access (the only one, invite_code_attempts_id_seq, is written by
-- join_group_by_code as its owner).
-- -----------------------------------------------------------------------------
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

-- -----------------------------------------------------------------------------
-- Temporary objects: none for client roles. TEMPORARY is granted to PUBLIC by default, so it is
-- revoked from PUBLIC and granted back to every other role.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_role text;
BEGIN
    EXECUTE pg_catalog.format('REVOKE TEMPORARY ON DATABASE %I FROM PUBLIC', pg_catalog.current_database());
    FOR v_role IN
        SELECT r.rolname FROM pg_catalog.pg_roles AS r
        WHERE r.rolname NOT IN ('anon', 'authenticated', 'authenticator')
          AND r.rolname !~ '^pg_'
        ORDER BY r.rolname
    LOOP
        EXECUTE pg_catalog.format('GRANT TEMPORARY ON DATABASE %I TO %I', pg_catalog.current_database(), v_role);
    END LOOP;
    EXECUTE pg_catalog.format('REVOKE TEMPORARY ON DATABASE %I FROM anon, authenticated, authenticator',
                              pg_catalog.current_database());
END;
$$;

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
-- Superseded by the keyset indexes (group_id|user_id, spent_at DESC, id DESC) and by unique keys.
DROP INDEX IF EXISTS public.idx_expenses_user_id;
DROP INDEX IF EXISTS public.idx_expenses_group_id;
DROP INDEX IF EXISTS public.idx_expenses_date;
DROP INDEX IF EXISTS public.idx_expenses_category;
DROP INDEX IF EXISTS public.idx_expenses_personal_feed;
DROP INDEX IF EXISTS public.idx_expenses_group_feed;
DROP INDEX IF EXISTS public.idx_group_members_group;
DROP INDEX IF EXISTS public.idx_group_invitations_token;

CREATE INDEX IF NOT EXISTS idx_expenses_group_spent ON public.expenses (group_id, spent_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_user_spent ON public.expenses (user_id, spent_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_groups_admin_id ON public.groups (admin_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON public.group_members (user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_invited_by ON public.group_members (invited_by);
CREATE INDEX IF NOT EXISTS idx_group_invitations_group ON public.group_invitations (group_id);
CREATE INDEX IF NOT EXISTS idx_group_invitations_inviter_created ON public.group_invitations (inviter_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_invitations_email_created ON public.group_invitations (email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_settlements_group ON public.settlements (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_expense_splits_user ON public.expense_splits (user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_group_id ON public.profiles (group_id);

-- -----------------------------------------------------------------------------
-- Realtime
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_table text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
        RETURN;
    END IF;
    FOREACH v_table IN ARRAY ARRAY['expenses', 'group_members', 'settlements'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
                       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = v_table) THEN
            EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
        END IF;
    END LOOP;
END;
$$;
