-- Function and privilege hygiene for the public schema.
-- Invariants: definer functions pin search_path, nothing is executable by anon or PUBLIC,
-- trigger and maintenance functions are not callable by clients, every table has RLS, and the
-- anonymous role has no table privileges.
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

grant execute on all functions in schema tests to anon, authenticated;

select plan(19);

-- Functions owned by the application (extension members excluded).
create temporary view app_functions as
select p.oid, p.oid::regprocedure::text as signature, p.prosecdef, p.proconfig, p.proacl, p.prosrc, p.prokind
from pg_proc as p
where p.pronamespace = 'public'::regnamespace
  and not exists (select 1 from pg_depend as d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e');
grant select on app_functions to authenticated;

select is(
    (select array_agg(signature order by signature) from app_functions
     where prosecdef and not ('search_path=""' = any (coalesce(proconfig, '{}')))),
    null,
    'every SECURITY DEFINER function sets search_path to empty as a function attribute'
);

select is(
    (select array_agg(signature order by signature) from app_functions
     where not exists (select 1 from unnest(coalesce(proconfig, '{}')) as c where c like 'search_path=%')),
    null,
    'every function has a fixed search_path'
);

select is(
    (select array_agg(signature order by signature) from app_functions
     where prosecdef and prosrc ~* 'set\s+search_path'),
    null,
    'no definer function changes search_path inside its body'
);

select is(
    (select array_agg(signature order by signature) from app_functions
     where has_function_privilege('anon', oid, 'execute')),
    null,
    'anon cannot execute any application function'
);

select is(
    (select array_agg(signature order by signature) from app_functions
     where proacl is null
        or exists (select 1 from aclexplode(proacl) as a where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
    null,
    'PUBLIC has no EXECUTE privilege on any application function'
);

select is(
    (select array_agg(signature order by signature) from app_functions as f
     join pg_type as t on t.oid = (select prorettype from pg_proc where oid = f.oid)
     where t.typname = 'trigger' and has_function_privilege('authenticated', f.oid, 'execute')),
    null,
    'trigger functions are not executable by authenticated'
);

select ok(not has_function_privilege('authenticated', 'public.purge_old_invitations()', 'execute'),
          'purge_old_invitations is not callable by clients');
select ok(has_function_privilege('service_role', 'public.purge_old_invitations()', 'execute'),
          'purge_old_invitations is callable by service_role');
select ok(not has_function_privilege('authenticated', 'public.generate_invite_code()', 'execute'),
          'clients cannot generate invite codes directly');
select ok(not has_function_privilege('anon', 'public.get_invitation_details(text)', 'execute'),
          'anon cannot read invitation details');
select ok(not has_function_privilege('anon', 'public.accept_group_invitation(text)', 'execute'),
          'anon cannot accept invitations');
select ok(not has_function_privilege('anon', 'public.join_group_by_code(text)', 'execute'),
          'anon cannot join groups with a code');

select is((select provolatile::text from pg_proc where oid = 'public.get_auth_user_groups()'::regprocedure), 's',
          'get_auth_user_groups is STABLE');

select is(
    (select array_agg(c.relname::text order by c.relname) from pg_class as c
     where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and not c.relrowsecurity),
    null,
    'every public table has row level security enabled'
);

select is(
    (select array_agg(c.relname::text order by c.relname) from pg_class as c
     where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm')
       and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
            or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))
       and c.relname in ('profiles', 'groups', 'group_members', 'group_bans', 'group_invitations', 'invite_code_attempts')),
    null,
    'anon has no privileges on profile, group, membership and invitation tables'
);

select is((select extnamespace::regnamespace::text from pg_extension where extname = 'pgcrypto'), 'extensions',
          'pgcrypto lives in the extensions schema');

-- The invitation RPC works with pgcrypto in `extensions` and leaves the caller's search_path alone.
select tests.create_user('hygiene_admin');
select tests.create_group_as('hygiene_admin', 'Hygiene');
select tests.authenticate_as('hygiene_admin');
select set_config('tests.search_path_before', current_setting('search_path'), true);
select lives_ok(
    $$ select public.create_group_invitation(tests.gid('Hygiene'), 'friend@example.test', 'member') $$,
    'create_group_invitation runs with pgcrypto in the extensions schema'
);
select is(current_setting('search_path'), current_setting('tests.search_path_before'),
          'calling a definer function does not change the session search_path');

reset role;
set local role anon;
select throws_ok($$ select public.get_invitation_details('any-token') $$, '42501', null,
                 'anon is refused by get_invitation_details');
reset role;

select * from finish();
rollback;
