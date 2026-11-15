-- Groups and membership: atomic creation, RPC-only membership changes, roles, admin transfer,
-- leaving, removal with bans, and the invariant that groups.admin_id matches the single admin row.
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

select plan(84);

-- Invariant check used throughout: exactly one approved admin row per group, equal to groups.admin_id.
create or replace function tests.admin_consistent()
returns boolean
language sql
security definer
set search_path = ''
as $$
    select not exists (
        select 1 from public.groups as g
        where (select count(*) from public.group_members as gm where gm.group_id = g.id and gm.role = 'admin') <> 1
           or not exists (select 1 from public.group_members as gm
                          where gm.group_id = g.id and gm.user_id = g.admin_id and gm.role = 'admin' and gm.status = 'approved')
    );
$$;
grant execute on function tests.admin_consistent() to authenticated;

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_user('dave');
select tests.create_user('erin');
select tests.create_user('outsider');
update public.profiles set currency = 'EUR' where id = tests.uid('erin');

-- ---------------------------------------------------------------------------
-- create_group
-- ---------------------------------------------------------------------------
select tests.authenticate_as('alice');
select lives_ok($$ select public.create_group('  Trip  ', 'usd') $$, 'create_group succeeds for an authenticated user');
reset role;
insert into tests.groups (name, id) select 'Trip', id from public.groups where name = 'Trip' and admin_id = tests.uid('alice');

select is((select admin_id from public.groups where id = tests.gid('Trip')), tests.uid('alice'), 'the creator is the group admin');
select is((select currency::text from public.groups where id = tests.gid('Trip')), 'USD', 'the currency is normalised to upper case');
select is((select role || '/' || status from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('alice')),
          'admin/approved', 'the creator gets an approved admin membership in the same call');
select is((select group_id from public.profiles where id = tests.uid('alice')), tests.gid('Trip'), 'the new group becomes the active group');
select ok((select invite_code ~ '^[0-9A-HJKMNP-TV-Z]{16}$' from public.groups where id = tests.gid('Trip')),
          'a server-generated 16-character invite code is assigned');

select tests.create_group_as('erin', 'Euro');
select is((select currency::text from public.groups where id = tests.gid('Euro')), 'EUR',
          'without an explicit currency the creator''s profile currency is used');

select tests.authenticate_as('alice');
select throws_ok($$ select public.create_group('   ', 'INR') $$, '22023', 'invalid_group_name', 'a blank group name is rejected');
select throws_ok($$ select public.create_group(repeat('g', 61), 'INR') $$, '22023', 'invalid_group_name', 'group names are at most 60 characters');
select throws_ok($$ select public.create_group('Valid', 'XYZ') $$, '22023', 'invalid_currency', 'unsupported currencies are rejected');
select throws_ok($$ insert into public.groups (name, admin_id) values ('Direct', tests.uid('alice')) $$,
                 '42501', null, 'groups cannot be inserted directly');
select throws_ok($$ insert into public.groups (id, name, admin_id, invite_code) values (gen_random_uuid(), 'Direct', tests.uid('alice'), 'AAAAAAAAAAAAAAAA') $$,
                 '42501', null, 'clients cannot choose a group id or invite code');

-- ---------------------------------------------------------------------------
-- Group row privileges
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.groups set invite_code = 'aaaa' where id = tests.gid('Trip') $$,
                 '42501', null, 'the admin cannot set the invite code directly');
select throws_ok($$ update public.groups set admin_id = tests.uid('bob') where id = tests.gid('Trip') $$,
                 '42501', null, 'admin_id cannot be changed directly');
select throws_ok($$ update public.groups set currency = 'INR' where id = tests.gid('Trip') $$,
                 '42501', null, 'the group currency cannot be changed directly');
select throws_ok($$ select invite_code from public.groups where id = tests.gid('Trip') $$,
                 '42501', null, 'the invite code is not readable through the table');
select lives_ok($$ update public.groups set name = 'Road Trip' where id = tests.gid('Trip') $$, 'the admin can rename the group');
select throws_ok($$ update public.groups set name = '' where id = tests.gid('Trip') $$, '23514', null, 'renaming keeps the length rule');
reset role;

-- ---------------------------------------------------------------------------
-- Membership rows are written only through RPCs
-- ---------------------------------------------------------------------------
select tests.add_member(tests.gid('Trip'), 'bob', 'member', 'approved', now() - interval '3 days');
select tests.add_member(tests.gid('Trip'), 'carol', 'member', 'approved', now() - interval '2 days');
select tests.add_member(tests.gid('Trip'), 'dave', 'viewer', 'approved', now() - interval '1 day');

select tests.authenticate_as('alice');
select throws_ok($$ insert into public.group_members (group_id, user_id, role) values (tests.gid('Trip'), tests.uid('outsider'), 'member') $$,
                 '42501', null, 'an admin cannot add an arbitrary user directly');
select throws_ok($$ update public.group_members set user_id = tests.uid('outsider') where group_id = tests.gid('Trip') and user_id = tests.uid('bob') $$,
                 '42501', null, 'membership rows cannot be re-pointed to another user');
select throws_ok($$ update public.group_members set group_id = tests.gid('Euro') where group_id = tests.gid('Trip') and user_id = tests.uid('bob') $$,
                 '42501', null, 'membership rows cannot be moved to another group');
select throws_ok($$ update public.group_members set role = 'admin' where group_id = tests.gid('Trip') and user_id = tests.uid('bob') $$,
                 '42501', null, 'roles cannot be changed directly');
select throws_ok($$ delete from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('alice') $$,
                 '42501', null, 'the admin cannot delete their own membership row directly');
reset role;
select is((select count(*) from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('alice')), 1::bigint,
          'the admin membership row is still present');
select tests.authenticate_as('dave');
select throws_ok($$ update public.group_members set role = 'member' where group_id = tests.gid('Trip') and user_id = tests.uid('dave') $$,
                 '42501', null, 'a viewer cannot change their own role');
reset role;
select is((select count(*) from public.profiles where id = tests.uid('outsider') and group_id is not null), 0::bigint,
          'an unrelated user was not attached to any group');
select throws_ok($$ insert into public.group_members (group_id, user_id, role) values (tests.gid('Trip'), tests.uid('outsider'), 'member') $$,
                 '42501', 'membership_rpc_only', 'the freeze trigger also blocks privileged direct inserts');

-- ---------------------------------------------------------------------------
-- Pending members (code join) and approve_member
-- ---------------------------------------------------------------------------
select tests.authenticate_as('outsider');
select throws_ok($$ select invite_code from public.groups $$, '42501', null, 'a non-member cannot read invite codes');
reset role;
select set_config('tests.trip_code', (select invite_code from public.groups where id = tests.gid('Trip')), true);
select tests.authenticate_as('outsider');
select is((public.join_group_by_code(current_setting('tests.trip_code')))->>'status', 'pending', 'joining with the code creates a pending membership');
select is((select count(*) from public.groups where id = tests.gid('Trip')), 0::bigint, 'a pending member cannot read the group row');
select throws_ok($$ select * from public.get_group_members(tests.gid('Trip')) $$, '42501', 'not_group_member',
                 'a pending member cannot list members');
select throws_ok($$ select public.set_active_group(tests.gid('Trip')) $$, '42501', 'not_group_member',
                 'a pending member cannot activate the group');
select is((select (g->>'status') || '/' || coalesce(g->>'invite_code', 'hidden') from jsonb_array_elements(public.get_user_groups()) as g
           where (g->>'id')::uuid = tests.gid('Trip')), 'pending/hidden', 'get_user_groups lists the pending group without the code');

select tests.authenticate_as('bob');
select is((select count(*) from public.group_members where group_id = tests.gid('Trip') and status = 'pending'), 0::bigint,
          'regular members do not see pending requests');
select throws_ok($$ select public.approve_member(tests.gid('Trip'), tests.uid('outsider')) $$, '42501', 'not_group_admin',
                 'a non-admin cannot approve members');
select tests.authenticate_as('alice');
select is((select count(*) from public.group_members where group_id = tests.gid('Trip') and status = 'pending'), 1::bigint,
          'the admin sees pending requests');
select is((select count(*) from public.get_group_members(tests.gid('Trip')) where status = 'pending'), 1::bigint,
          'the admin sees pending requests in the directory');
select ok((select (g->>'invite_code') is not null from jsonb_array_elements(public.get_user_groups()) as g
           where (g->>'id')::uuid = tests.gid('Trip')), 'get_user_groups returns the code to the admin');
select throws_ok($$ select public.approve_member(tests.gid('Trip'), tests.uid('erin')) $$, 'P0002', 'member_not_found',
                 'approving a non-member raises not found');
select throws_ok($$ select public.approve_member(tests.gid('Trip'), tests.uid('outsider'), 'admin') $$, '22023', 'invalid_role',
                 'approval cannot grant admin');
select lives_ok($$ select public.approve_member(tests.gid('Trip'), tests.uid('outsider'), 'viewer') $$, 'the admin approves a pending member');
select throws_ok($$ select public.approve_member(tests.gid('Trip'), tests.uid('outsider')) $$, 'P0001', 'member_not_pending',
                 'approving twice raises');
reset role;
select is((select role || '/' || status from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('outsider')),
          'viewer/approved', 'the approved member has the chosen role');

-- ---------------------------------------------------------------------------
-- set_member_role
-- ---------------------------------------------------------------------------
select tests.authenticate_as('bob');
select throws_ok($$ select public.set_member_role(tests.gid('Trip'), tests.uid('dave'), 'member') $$, '42501', 'not_group_admin',
                 'a non-admin cannot change roles');
select tests.authenticate_as('alice');
select throws_ok($$ select public.set_member_role(tests.gid('Trip'), tests.uid('bob'), 'admin') $$, '22023', 'invalid_role',
                 'set_member_role cannot grant admin');
select throws_ok($$ select public.set_member_role(tests.gid('Trip'), tests.uid('alice'), 'viewer') $$, 'P0001', 'cannot_change_own_role',
                 'the admin cannot demote themselves');
select throws_ok($$ select public.set_member_role(tests.gid('Trip'), tests.uid('erin'), 'viewer') $$, 'P0002', 'member_not_found',
                 'changing the role of a non-member raises');
select lives_ok($$ select public.set_member_role(tests.gid('Trip'), tests.uid('dave'), 'member') $$, 'the admin promotes a viewer to member');
reset role;
select is((select role from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('dave')), 'member',
          'the role change is stored');

-- ---------------------------------------------------------------------------
-- transfer_admin
-- ---------------------------------------------------------------------------
select tests.authenticate_as('bob');
select throws_ok($$ select public.transfer_admin(tests.gid('Trip'), tests.uid('bob')) $$, '42501', 'not_group_admin',
                 'a non-admin cannot take over the group');
select tests.authenticate_as('alice');
select throws_ok($$ select public.transfer_admin(tests.gid('Trip'), tests.uid('alice')) $$, '22023', 'invalid_target',
                 'transfer to oneself is rejected');
select throws_ok($$ select public.transfer_admin(tests.gid('Trip'), tests.uid('erin')) $$, 'P0002', 'member_not_found',
                 'transfer to a non-member is rejected');
select lives_ok($$ select public.transfer_admin(tests.gid('Trip'), tests.uid('bob')) $$, 'the admin transfers the group');
reset role;
select is((select admin_id from public.groups where id = tests.gid('Trip')), tests.uid('bob'), 'groups.admin_id follows the transfer');
select is((select role from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('alice')), 'member',
          'the previous admin becomes a member');
select ok(tests.admin_consistent(), 'exactly one admin row per group, matching groups.admin_id (after transfer)');
select tests.authenticate_as('alice');
select throws_ok($$ select public.rotate_invite_code(tests.gid('Trip')) $$, '42501', 'not_group_admin',
                 'the previous admin lost admin rights');

-- ---------------------------------------------------------------------------
-- remove_member and bans
-- ---------------------------------------------------------------------------
select tests.authenticate_as('carol');
select throws_ok($$ select public.remove_member(tests.gid('Trip'), tests.uid('dave')) $$, '42501', 'not_group_admin',
                 'a non-admin cannot remove members');
select tests.authenticate_as('bob');
select throws_ok($$ select public.remove_member(tests.gid('Trip'), tests.uid('bob')) $$, 'P0001', 'cannot_remove_self',
                 'the admin cannot remove themselves');
select throws_ok($$ select public.remove_member(tests.gid('Trip'), tests.uid('erin')) $$, 'P0002', 'member_not_found',
                 'removing a non-member raises');
select lives_ok($$ select public.remove_member(tests.gid('Trip'), tests.uid('outsider')) $$, 'the admin removes a member');
select is((select count(*) from public.group_bans where group_id = tests.gid('Trip') and user_id = tests.uid('outsider')), 1::bigint,
          'removal records a ban visible to the admin');
select tests.authenticate_as('carol');
select is((select count(*) from public.group_bans), 0::bigint, 'bans are not visible to regular members');
select throws_ok($$ insert into public.group_bans (group_id, user_id) values (tests.gid('Trip'), tests.uid('dave')) $$,
                 '42501', null, 'bans cannot be written directly');
select tests.authenticate_as('outsider');
select is((public.join_group_by_code(current_setting('tests.trip_code')))->>'error', 'banned',
          'a removed user cannot rejoin with the group code');
reset role;
select is((select count(*) from public.group_members where group_id = tests.gid('Trip') and user_id = tests.uid('outsider')), 0::bigint,
          'the removed user has no membership');

-- ---------------------------------------------------------------------------
-- leave_group
-- ---------------------------------------------------------------------------
select tests.authenticate_as('erin');
select throws_ok($$ select public.leave_group(tests.gid('Trip')) $$, 'P0002', 'not_group_member', 'a non-member cannot leave');
select throws_ok($$ select public.leave_group(gen_random_uuid()) $$, 'P0002', 'group_not_found', 'leaving an unknown group raises');

-- A member leaving: their active group moves to their next approved membership or NULL.
reset role;
update public.profiles set group_id = tests.gid('Trip') where id = tests.uid('dave');
select tests.authenticate_as('dave');
select is((public.leave_group(tests.gid('Trip')))->>'group_deleted', 'false', 'a member leaves the group');
reset role;
select is((select group_id from public.profiles where id = tests.uid('dave')), null, 'the active group is cleared when it was left');

-- The admin leaving: admin passes to the longest-standing approved member. carol joined two days
-- ago; alice's membership dates from the group's creation today.
select tests.authenticate_as('bob');
select is((public.leave_group(tests.gid('Trip')))->>'new_admin_id', tests.uid('carol')::text,
          'the admin role passes to the longest-standing approved member');
reset role;
select is((select admin_id from public.groups where id = tests.gid('Trip')), tests.uid('carol'), 'groups.admin_id follows the successor');
select ok(tests.admin_consistent(), 'exactly one admin row per group, matching groups.admin_id (after leave)');

-- Remaining: carol (admin), alice. A pending request does not count as a successor.
select tests.add_member(tests.gid('Trip'), 'erin', 'viewer', 'pending');
select tests.authenticate_as('alice');
select is((public.leave_group(tests.gid('Trip')))->>'group_deleted', 'false', 'the last regular member leaves');
select tests.authenticate_as('carol');
select is((public.leave_group(tests.gid('Trip')))->>'group_deleted', 'true',
          'the last approved member leaving deletes the group');
reset role;
select is((select count(*) from public.groups where id = tests.gid('Trip')), 0::bigint, 'the group is gone');
select is((select count(*) from public.group_members where group_id = tests.gid('Trip')), 0::bigint, 'its memberships are gone');

-- ---------------------------------------------------------------------------
-- Deleting a group directly (admin) cascades its memberships.
-- ---------------------------------------------------------------------------
select tests.add_member(tests.gid('Euro'), 'carol', 'member');
select tests.authenticate_as('carol');
delete from public.groups where id = tests.gid('Euro');
reset role;
select is((select count(*) from public.groups where id = tests.gid('Euro')), 1::bigint, 'a non-admin cannot delete the group');
select tests.authenticate_as('erin');
select lives_ok($$ delete from public.groups where id = tests.gid('Euro') $$, 'the admin deletes the group');
reset role;
select is((select count(*) from public.group_members where group_id = tests.gid('Euro')), 0::bigint,
          'memberships are removed by the cascade');

-- ---------------------------------------------------------------------------
-- set_active_group and get_user_groups
-- ---------------------------------------------------------------------------
select tests.create_group_as('dave', 'Home');
select tests.authenticate_as('dave');
select is((public.set_active_group(tests.gid('Home')))->>'group_id', tests.gid('Home')::text, 'a member can activate their group');
select is(jsonb_array_length(public.get_user_groups()), 1, 'get_user_groups lists the caller''s groups');
reset role;
set local role anon;
select throws_ok($$ select public.create_group('Anon', 'INR') $$, '42501', null, 'anon cannot create groups');
reset role;
select ok(tests.admin_consistent(), 'exactly one admin row per group, matching groups.admin_id (final)');

select * from finish();
rollback;
