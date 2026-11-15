-- Profiles: own-row access, server-managed columns, validation, email sync and the member directory.
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

select plan(41);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_group_as('alice', 'Flat');
select tests.add_member(tests.gid('Flat'), 'bob', 'member');

-- Schema
select hasnt_column('public', 'profiles', 'phone', 'profiles has no phone column');
select has_column('public', 'profiles', 'ai_consent_at', 'profiles.ai_consent_at exists');
select has_column('public', 'profiles', 'timezone', 'profiles.timezone exists');
select has_column('public', 'profiles', 'locale', 'profiles.locale exists');
select col_default_is('public', 'profiles', 'timezone', 'Asia/Kolkata'::text, 'timezone defaults to Asia/Kolkata');

-- A co-member's profile row (and so their email) is not readable.
select tests.authenticate_as('bob');
select is((select count(*) from public.profiles where id = tests.uid('alice')), 0::bigint,
          'a group member cannot read another member''s profile row');
select is((select count(*) from public.profiles), 1::bigint, 'a user sees exactly one profile: their own');
select is((select email from public.profiles where id = tests.uid('bob')), 'bob@example.test',
          'a user can read their own email');

-- Server-managed columns are not client-writable.
select throws_ok($$ update public.profiles set email = 'other@example.test' where id = tests.uid('bob') $$,
                 '42501', null, 'a user cannot change their profile email');
select throws_ok($$ update public.profiles set group_id = tests.gid('Flat') where id = tests.uid('bob') $$,
                 '42501', null, 'a user cannot set their active group directly');
select throws_ok($$ update public.profiles set id = gen_random_uuid() where id = tests.uid('bob') $$,
                 '42501', null, 'a user cannot change their profile id');
select throws_ok($$ update public.profiles set created_at = now() - interval '1 year' where id = tests.uid('bob') $$,
                 '42501', null, 'a user cannot change created_at');
select throws_ok($$ update public.profiles set ai_consent_at = now() where id = tests.uid('bob') $$,
                 '42501', null, 'a user cannot write ai_consent_at');
select throws_ok($$ insert into public.profiles (id, display_name) values (gen_random_uuid(), 'X') $$,
                 '42501', null, 'a user cannot insert profiles');
select throws_ok($$ delete from public.profiles where id = tests.uid('bob') $$,
                 '42501', null, 'a user cannot delete profiles');

-- Updating someone else's row affects nothing.
update public.profiles set display_name = 'Changed' where id = tests.uid('alice');
reset role;
select is((select display_name from public.profiles where id = tests.uid('alice')), 'Alice',
          'a user cannot update another user''s profile');

-- Validation
select tests.authenticate_as('bob');
select throws_ok($$ update public.profiles set avatar_url = 'http://images.example.test/a.png' where id = tests.uid('bob') $$,
                 '23514', null, 'avatar_url must be https');
select throws_ok($$ update public.profiles set avatar_url = 'https://images.example.test/' || repeat('a', 2100) where id = tests.uid('bob') $$,
                 '23514', null, 'avatar_url is at most 2048 characters');
select lives_ok($$ update public.profiles set avatar_url = 'https://images.example.test/a.png' where id = tests.uid('bob') $$,
                'an https avatar_url is accepted');
select throws_ok($$ update public.profiles set display_name = '   ' where id = tests.uid('bob') $$,
                 '23514', null, 'display_name cannot be blank');
select throws_ok($$ update public.profiles set display_name = repeat('x', 61) where id = tests.uid('bob') $$,
                 '23514', null, 'display_name is at most 60 characters');
update public.profiles set display_name = '  Bob B  ' where id = tests.uid('bob');
select is((select display_name from public.profiles where id = tests.uid('bob')), 'Bob B', 'display_name is trimmed');
select throws_ok($$ update public.profiles set currency = 'XYZ' where id = tests.uid('bob') $$,
                 '23514', null, 'currency must be supported');
select lives_ok($$ update public.profiles set currency = 'JPY' where id = tests.uid('bob') $$, 'a supported currency is accepted');
select throws_ok($$ update public.profiles set timezone = 'Mars/Olympus_Mons' where id = tests.uid('bob') $$,
                 '22023', 'invalid_timezone', 'timezone must be a known IANA name');
select lives_ok($$ update public.profiles set timezone = 'America/New_York' where id = tests.uid('bob') $$,
                'a valid IANA timezone is accepted');
select throws_ok($$ update public.profiles set theme_mode = 'neon' where id = tests.uid('bob') $$,
                 '23514', null, 'theme_mode must be system, light or dark');
select throws_ok($$ update public.profiles set locale = 'not a locale!' where id = tests.uid('bob') $$,
                 '23514', null, 'locale must look like a BCP 47 tag');
select lives_ok($$ update public.profiles set locale = 'en-IN' where id = tests.uid('bob') $$, 'a locale tag is accepted');

-- AI consent timestamp is server-set.
update public.profiles set ai_consent = true where id = tests.uid('bob');
select isnt((select ai_consent_at from public.profiles where id = tests.uid('bob')), null,
            'granting AI consent records ai_consent_at');
update public.profiles set ai_consent = false where id = tests.uid('bob');
select is((select ai_consent_at from public.profiles where id = tests.uid('bob')), null,
          'withdrawing AI consent clears ai_consent_at');

-- Member directory
select is((select count(*) from public.get_group_members(tests.gid('Flat'))), 2::bigint,
          'a member sees the group''s members through get_group_members');
select is((select display_name from public.get_group_members(tests.gid('Flat'))
           where user_id = tests.uid('alice')), 'Alice', 'the directory exposes display names');
select ok(pg_get_function_result('public.get_group_members(uuid)'::regprocedure) !~ 'email',
          'the directory does not return email addresses');
select tests.authenticate_as('carol');
select throws_ok($$ select * from public.get_group_members(tests.gid('Flat')) $$,
                 '42501', 'not_group_member', 'a non-member cannot list a group''s members');

-- Active group
select tests.authenticate_as('bob');
select lives_ok($$ select public.set_active_group(null) $$, 'a user can switch to personal mode');
reset role;
select is((select group_id from public.profiles where id = tests.uid('bob')), null, 'personal mode stores a NULL active group');
select tests.authenticate_as('carol');
select throws_ok($$ select public.set_active_group(tests.gid('Flat')) $$,
                 '42501', 'not_group_member', 'a user cannot activate a group they do not belong to');
reset role;

-- Email is synced from auth.users.
update auth.users set email = 'bob.new@example.test' where id = tests.uid('bob');
select is((select email from public.profiles where id = tests.uid('bob')), 'bob.new@example.test',
          'a confirmed email change is copied to the profile');

-- New-user trigger sanitises metadata.
select tests.create_user('dora', true, jsonb_build_object('full_name', repeat('D', 100), 'avatar_url', 'http://insecure.example.test/a.png'));
select is((select char_length(display_name) from public.profiles where id = tests.uid('dora')), 60,
          'long names from sign-up metadata are truncated to 60 characters');
select is((select avatar_url from public.profiles where id = tests.uid('dora')), null,
          'non-https avatar URLs from sign-up metadata are dropped');

select * from finish();
rollback;
