-- Group invite codes: format and entropy, normalised lookup, expiry, rotation, failed-attempt
-- throttle, pending-viewer joins and bans.
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

select plan(33);

select tests.create_user('admin');
select tests.create_user('member');
select tests.create_user('viewer');
select tests.create_user('guesser');
select tests.create_user('joiner');
select tests.create_user('late');
select tests.create_group_as('admin', 'Club');
select tests.add_member(tests.gid('Club'), 'member', 'member');
select tests.add_member(tests.gid('Club'), 'viewer', 'viewer');
select set_config('tests.code', (select invite_code from public.groups where id = tests.gid('Club')), true);

-- ---------------------------------------------------------------------------
-- Format, entropy, uniqueness
-- ---------------------------------------------------------------------------
select is(char_length(current_setting('tests.code')), 16, 'invite codes are 16 characters');
select ok(current_setting('tests.code') ~ '^[0-9A-HJKMNP-TV-Z]{16}$', 'invite codes use the Crockford base32 alphabet');
select is((select count(distinct c) from (select public.generate_invite_code() as c from generate_series(1, 500)) as s), 500::bigint,
          '500 generated codes are distinct');
select is((select count(*) from (select public.generate_invite_code() as c from generate_series(1, 500)) as s
           where c !~ '^[0-9A-HJKMNP-TV-Z]{16}$'), 0::bigint, 'every generated code matches the format');
select ok((select count(distinct substr(c, 1, 1)) from (select public.generate_invite_code() as c from generate_series(1, 500)) as s) >= 28,
          'the first character uses (almost) the whole alphabet');
select ok((select invite_code_expires_at between now() + interval '29 days' and now() + interval '31 days'
           from public.groups where id = tests.gid('Club')), 'codes expire after 30 days by default');
select is(public.normalize_invite_code(' abcd-efgh-ijkl-mnop '), 'ABCDEFGH1JK1MN0P', 'input is normalised (case, separators, I/L/O)');
select ok((select indexdef ~ '\(invite_code\)' from pg_indexes where schemaname = 'public' and indexname = 'groups_invite_code_key'),
          'a unique index on invite_code serves the lookup');

-- ---------------------------------------------------------------------------
-- Joining
-- ---------------------------------------------------------------------------
select tests.authenticate_as('joiner');
select is(public.join_group_by_code(lower(substr(current_setting('tests.code'), 1, 8)) || '-' || lower(substr(current_setting('tests.code'), 9))) ->> 'success',
          'true', 'a lower-case, dash-separated code is accepted');
reset role;
select is((select role || '/' || status from public.group_members where group_id = tests.gid('Club') and user_id = tests.uid('joiner')),
          'viewer/pending', 'a code join creates a pending viewer');
select is((select group_id from public.profiles where id = tests.uid('joiner')), null, 'a pending join does not change the active group');

select tests.authenticate_as('joiner');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'error', 'already_member', 'joining twice reports already_member');

-- A viewer reusing the code is not upgraded.
select tests.authenticate_as('viewer');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'error', 'already_member', 'an existing viewer gets already_member');
reset role;
select is((select role || '/' || status from public.group_members where group_id = tests.gid('Club') and user_id = tests.uid('viewer')),
          'viewer/approved', 'the viewer''s role is unchanged by reusing the code');

-- ---------------------------------------------------------------------------
-- Failed-attempt throttle
-- ---------------------------------------------------------------------------
select tests.authenticate_as('guesser');
select is((select count(*) from generate_series(1, 10) as i
           where public.join_group_by_code(lpad(i::text, 16, '0')) ->> 'error' = 'invalid_code'), 10::bigint,
          'ten wrong codes are reported as invalid_code');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'error', 'rate_limited',
          'after ten failures in an hour even the right code is refused');
select ok((public.join_group_by_code('anything') ->> 'retry_after') is not null, 'the throttle response says when to retry');
reset role;
select is((select count(*) from public.invite_code_attempts where user_id = tests.uid('guesser')), 10::bigint,
          'refused attempts while throttled are not recorded');
select is((select count(*) from public.group_members where user_id = tests.uid('guesser')), 0::bigint,
          'the throttled user did not join');

-- Attempts older than an hour no longer count.
update public.invite_code_attempts set attempted_at = now() - interval '61 minutes' where user_id = tests.uid('guesser');
select tests.authenticate_as('guesser');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'success', 'true', 'the throttle window is one hour');

-- Nine failures still allow the right code.
select tests.authenticate_as('late');
select is((select count(*) from generate_series(1, 9) as i
           where public.join_group_by_code('WRONG' || i::text) ->> 'error' = 'invalid_code'), 9::bigint, 'nine wrong codes');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'success', 'true', 'below the limit the right code works');

select throws_ok($$ select * from public.invite_code_attempts $$, '42501', null, 'clients cannot read the attempt log');
select throws_ok($$ delete from public.invite_code_attempts $$, '42501', null, 'clients cannot clear the attempt log');

-- ---------------------------------------------------------------------------
-- Expiry and rotation
-- ---------------------------------------------------------------------------
reset role;
select tests.create_user('newcomer');
update public.groups set invite_code_expires_at = now() - interval '1 minute' where id = tests.gid('Club');
select tests.authenticate_as('newcomer');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'error', 'code_expired', 'an expired code is refused');

select tests.authenticate_as('member');
select throws_ok($$ select public.rotate_invite_code(tests.gid('Club')) $$, '42501', 'not_group_admin', 'only the admin can rotate the code');
select tests.authenticate_as('joiner');
select throws_ok($$ select public.rotate_invite_code(tests.gid('Club')) $$, '42501', 'not_group_admin', 'a pending member cannot rotate the code');
select tests.authenticate_as('admin');
select set_config('tests.new_code', public.rotate_invite_code(tests.gid('Club')) ->> 'invite_code', true);
select isnt(current_setting('tests.new_code'), current_setting('tests.code'), 'rotation issues a different code');
select ok(current_setting('tests.new_code') ~ '^[0-9A-HJKMNP-TV-Z]{16}$', 'the rotated code has the standard format');

select tests.authenticate_as('newcomer');
select is(public.join_group_by_code(current_setting('tests.code')) ->> 'error', 'invalid_code', 'the old code stops working after rotation');
select is(public.join_group_by_code(current_setting('tests.new_code')) ->> 'success', 'true', 'the new code works and resets the expiry');

-- ---------------------------------------------------------------------------
-- Removed users are banned from code joins.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('admin');
select public.remove_member(tests.gid('Club'), tests.uid('member'));
select tests.authenticate_as('member');
select is(public.join_group_by_code(current_setting('tests.new_code')) ->> 'error', 'banned', 'a removed member cannot rejoin with the code');

reset role;
set local role anon;
select throws_ok($$ select public.join_group_by_code('ABCDEFGHJKMNPQRS') $$, '42501', null, 'anon cannot use join_group_by_code');
reset role;

select * from finish();
rollback;
