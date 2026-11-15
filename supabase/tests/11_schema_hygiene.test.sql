-- Schema-wide invariants: RLS on every table, policies scoped TO authenticated with one command each,
-- auth.uid() evaluated once per statement, UPDATE policies with WITH CHECK, no anon access, definer
-- functions with an empty search_path, covering indexes for every foreign key and no redundant
-- indexes, and the Realtime publication.
begin;
set local client_min_messages = warning;
create extension if not exists pgtap with schema extensions;
-- ---------------------------------------------------------------------------
-- Test helpers (created inside this file's transaction and rolled back with it)
-- ---------------------------------------------------------------------------
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

create table if not exists tests.users (name text primary key, id uuid not null, email text not null);
create table if not exists tests.groups (name text primary key, id uuid not null);

-- Creates a confirmed auth user; handle_new_user creates the profile.
create or replace function tests.create_user(p_name text, p_confirmed boolean default true, p_meta jsonb default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid := gen_random_uuid();
    v_email text := p_name || '@example.test';
begin
    insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
            case when p_confirmed then now() end,
            coalesce(p_meta, jsonb_build_object('full_name', initcap(p_name))), now(), now());
    insert into tests.users (name, id, email) values (p_name, v_id, v_email);
    return v_id;
end;
$$;

create or replace function tests.uid(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select u.id from tests.users as u where u.name = p_name $$;

create or replace function tests.gid(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select g.id from tests.groups as g where g.name = p_name $$;

create or replace function tests.set_claims(p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform set_config('request.jwt.claims',
        json_build_object('sub', u.id, 'email', u.email, 'role', 'authenticated')::text, true)
    from tests.users as u where u.name = p_name;
end;
$$;

-- Acts as the given user for the following statements (like an API request with their JWT).
create or replace function tests.authenticate_as(p_name text)
returns void
language plpgsql
set search_path = ''
as $$
begin
    perform tests.set_claims(p_name);
    perform set_config('role', 'authenticated', true);
end;
$$;

-- Fixture shortcuts (run as the table owner; they call the real RPCs with the user's identity).
create or replace function tests.create_group_as(p_name text, p_group text, p_currency text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    perform tests.set_claims(p_name);
    v_id := (public.create_group(p_group, p_currency)).id;
    insert into tests.groups (name, id) values (p_group, v_id);
    return v_id;
end;
$$;

-- Adds an approved member directly (fixture only; bypasses the RPCs on purpose).
create or replace function tests.add_member(p_group uuid, p_name text, p_role text default 'member',
                                            p_status text default 'approved', p_joined_at timestamptz default now())
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform set_config('exevra.membership_rpc', 'on', true);
    insert into public.group_members (group_id, user_id, role, status, joined_at)
    values (p_group, tests.uid(p_name), p_role, p_status, p_joined_at);
    perform set_config('exevra.membership_rpc', 'off', true);
end;
$$;


create table if not exists tests.expenses (name text primary key, id uuid not null);

-- Adds an expense paid by p_payer (fixture: runs as the table owner, so RLS is bypassed but every
-- trigger still applies).
create or replace function tests.add_expense(p_payer text, p_group text, p_title text, p_amount bigint,
                                             p_spent_at timestamptz default now(), p_category text default 'Food',
                                             p_currency text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    insert into public.expenses (user_id, group_id, title, amount_minor, currency, category, spent_at)
    values (tests.uid(p_payer), case when p_group is null then null else tests.gid(p_group) end,
            p_title, p_amount, p_currency, p_category, p_spent_at)
    returning id into v_id;
    insert into tests.expenses (name, id) values (p_title, v_id);
    return v_id;
end;
$$;

create or replace function tests.eid(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select e.id from tests.expenses as e where e.name = p_name $$;

create or replace function tests.share(p_expense text, p_user text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select s.share_minor from public.expense_splits as s
    where s.expense_id = tests.eid(p_expense) and s.user_id = tests.uid(p_user)
$$;

-- Removes a membership directly (fixture only).
create or replace function tests.remove_member(p_group uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform set_config('exevra.membership_rpc', 'on', true);
    delete from public.group_members where group_id = p_group and user_id = tests.uid(p_name);
    perform set_config('exevra.membership_rpc', 'off', true);
end;
$$;

create table if not exists tests.settlements (name text primary key, id uuid not null);

-- Net balance of a user in a group (NULL user = former members), read without an access check.
create or replace function tests.net(p_group text, p_user text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
    select b.net_minor from public.group_balance_rows(tests.gid(p_group)) as b
    where b.user_id is not distinct from (case when p_user is null then null else tests.uid(p_user) end)
$$;

-- Records a settlement through the RPC as p_from and remembers it under p_name.
create or replace function tests.settle(p_name text, p_from text, p_group text, p_to text, p_amount bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    perform tests.set_claims(p_from);
    v_id := (public.record_settlement(tests.gid(p_group), tests.uid(p_to), p_amount)).id;
    insert into tests.settlements (name, id) values (p_name, v_id);
    return v_id;
end;
$$;

create or replace function tests.sid(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$ select s.id from tests.settlements as s where s.name = p_name $$;

grant execute on all functions in schema tests to anon, authenticated;

select plan(25);

-- ===========================================================================
-- Row level security and policies
-- ===========================================================================
select is((select array_agg(c.relname::text order by c.relname) from pg_class as c
           where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
          null, 'every public table has row level security enabled');
select is((select array_agg(c.relname::text order by c.relname) from pg_class as c
           where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
             and not exists (select 1 from pg_policies as p where p.schemaname = 'public' and p.tablename = c.relname)),
          null, 'every public table has at least one policy');
select is((select array_agg(tablename || '.' || policyname order by 1) from pg_policies
           where schemaname = 'public' and roles <> '{authenticated}'::name[]),
          null, 'every policy is scoped TO authenticated');
select is((select array_agg(tablename || '.' || policyname order by 1) from pg_policies
           where schemaname = 'public' and cmd = 'ALL'),
          null, 'every policy covers a single command');
select is((select array_agg(tablename || '.' || policyname order by 1) from pg_policies
           where schemaname = 'public' and cmd = 'UPDATE' and (qual is null or with_check is null)),
          null, 'every UPDATE policy has USING and WITH CHECK');
select is((select array_agg(tablename || '.' || policyname order by 1) from pg_policies
           where schemaname = 'public'
             and regexp_count(coalesce(qual, '') || ' ' || coalesce(with_check, ''), 'auth\.(uid|jwt|role)\(\)')
                 <> regexp_count(coalesce(qual, '') || ' ' || coalesce(with_check, ''), 'SELECT auth\.(uid|jwt|role)\(\)')),
          null, 'every auth.uid() in a policy is wrapped in a scalar subquery (evaluated once per statement)');

-- ===========================================================================
-- Privileges
-- ===========================================================================
select is((select array_agg(c.relname::text order by c.relname) from pg_class as c
           where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm')
             and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
                  or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete')
                  or has_table_privilege('anon', c.oid, 'truncate') or has_table_privilege('anon', c.oid, 'references')
                  or has_table_privilege('anon', c.oid, 'trigger'))),
          null, 'anon has no privileges on any public table');
select is((select array_agg(p.oid::regprocedure::text order by 1) from pg_proc as p
           where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'execute')),
          null, 'anon cannot execute any public function');
select is((select array_agg(p.oid::regprocedure::text order by 1) from pg_proc as p
           where p.pronamespace = 'public'::regnamespace and p.prosecdef
             and not coalesce(p.proconfig, '{}') @> array['search_path=""']),
          null, 'every SECURITY DEFINER function pins search_path to empty');
select is((select array_agg(p.oid::regprocedure::text order by 1) from pg_proc as p
           where p.pronamespace = 'public'::regnamespace and p.prorettype = 'trigger'::regtype
             and has_function_privilege('authenticated', p.oid, 'execute')),
          null, 'trigger functions are not callable by clients');
select is((select array_agg(p.oid::regprocedure::text order by 1) from pg_proc as p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('prepare_account_deletion', 'purge_old_invitations', 'purge_old_ai_usage',
                               'pick_successor_admin', 'group_balance_rows', 'group_split_member_ids')
             and (has_function_privilege('authenticated', p.oid, 'execute') or not has_function_privilege('service_role', p.oid, 'execute'))),
          null, 'maintenance and internal functions are service_role only');
select is((select array_agg(c.oid::regclass::text order by 1) from pg_class as c
           where c.relnamespace = 'public'::regnamespace and c.relkind = 'S'
             and (has_sequence_privilege('authenticated', c.oid, 'usage') or has_sequence_privilege('authenticated', c.oid, 'update')
                  or has_sequence_privilege('authenticated', c.oid, 'select') or has_sequence_privilege('anon', c.oid, 'usage')
                  or has_sequence_privilege('anon', c.oid, 'update') or has_sequence_privilege('anon', c.oid, 'select'))),
          null, 'client roles have no privileges on public sequences (e.g. cannot advance a throttle sequence)');
select ok(not has_database_privilege('authenticated', current_database(), 'TEMP')
          and not has_database_privilege('anon', current_database(), 'TEMP')
          and not has_database_privilege('authenticator', current_database(), 'TEMP'),
          'client roles cannot create temporary objects (no pg_temp shadowing inside definer functions)');
select ok(has_database_privilege('postgres', current_database(), 'TEMP')
          and has_database_privilege('service_role', current_database(), 'TEMP'),
          'server roles keep the TEMP privilege');

-- ===========================================================================
-- Indexes
-- ===========================================================================
select is((select array_agg(c.conrelid::regclass::text || '.' || c.conname order by 1)
           from pg_constraint as c
           where c.contype = 'f' and c.connamespace = 'public'::regnamespace
             and not exists (
                 select 1 from pg_index as i
                 where i.indrelid = c.conrelid
                   and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] @> c.conkey
                   and (i.indkey::int2[])[0:array_length(c.conkey, 1) - 1] <@ c.conkey)),
          null, 'every foreign key has a covering index');
select is((select array_agg(a.indexrelid::regclass::text order by 1)
           from pg_index as a
           join pg_index as b on b.indrelid = a.indrelid and b.indexrelid <> a.indexrelid
           where a.indrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)
             and not a.indisunique and a.indpred is null and a.indexprs is null
             and b.indpred is null and b.indexprs is null
             and array_length(a.indkey::int2[], 1) <= array_length(b.indkey::int2[], 1)
             and array_to_string((b.indkey::int2[])[0:array_length(a.indkey::int2[], 1) - 1], ',')
                 = array_to_string(a.indkey::int2[], ',')
             and array_to_string((b.indoption::int2[])[0:array_length(a.indkey::int2[], 1) - 1], ',')
                 = array_to_string(a.indoption::int2[], ',')),
          null, 'no non-unique index is a prefix of another index');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_expenses_group_spent'
                  and indexdef like '%(group_id, spent_at DESC, id DESC)%'), 'group feed keyset index');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'idx_expenses_user_spent'
                  and indexdef like '%(user_id, spent_at DESC, id DESC)%'), 'personal feed keyset index');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'groups' and indexdef like '%(invite_code)%'
                  and indexdef like 'CREATE UNIQUE%'), 'invite codes are looked up through a unique index');

-- ===========================================================================
-- Realtime
-- ===========================================================================
select is((select array_agg(tablename::text order by tablename) from pg_publication_tables
           where pubname = 'supabase_realtime' and schemaname = 'public'),
          array['expenses', 'group_members', 'settlements'], 'expenses, members and settlements are published for realtime');

-- Without TEMP, a client session cannot place a type in pg_temp to shadow the unqualified types used
-- inside definer functions.
set local role authenticated;
select throws_ok($$ create domain pg_temp.text as pg_catalog.text $$, '42501', null,
                 'an authenticated session cannot create objects in pg_temp');
select throws_ok($$ create temporary table t_probe (x int) $$, '42501', null,
                 'an authenticated session cannot create temporary tables');
reset role;

-- ===========================================================================
-- Membership freeze still lets a foreign-key action clear invited_by
-- ===========================================================================
select tests.create_user('gus');
select tests.create_user('hal');
select tests.create_user('ivy');
select tests.create_group_as('ivy', 'Porch', 'INR');
select tests.add_member(tests.gid('Porch'), 'gus');
select tests.add_member(tests.gid('Porch'), 'hal');
select set_config('exevra.membership_rpc', 'on', true);
update public.group_members set invited_by = tests.uid('gus') where user_id = tests.uid('hal');
select set_config('exevra.membership_rpc', 'off', true);
select lives_ok(format($$ delete from public.profiles where id = %L $$, tests.uid('gus')),
                'deleting an inviter''s profile clears invited_by on the rows they invited');
select is((select invited_by from public.group_members where user_id = tests.uid('hal')), null, 'invited_by is cleared');
select throws_ok(format($$ update public.group_members set invited_by = null where user_id = %L $$, tests.uid('ivy')),
                 '42501', 'membership_rpc_only', 'a direct update is still refused');

select * from finish();
rollback;
