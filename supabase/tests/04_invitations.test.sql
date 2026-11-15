-- Email invitations: admin-only creation, hashed server tokens, email-bound details/accept/decline,
-- state transitions, no direct table writes, rate limits, ban lifting and cleanup.
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

select plan(72);

-- Stores raw tokens returned by the RPC for later steps (test-only).
create table tests.tokens (label text primary key, token text not null, invitation_id uuid not null);
grant select on tests.tokens to authenticated;

create or replace function tests.invite(p_admin text, p_group text, p_email text, p_role text, p_label text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
    r record;
begin
    perform tests.set_claims(p_admin);
    select * into r from public.create_group_invitation(tests.gid(p_group), p_email, p_role);
    insert into tests.tokens (label, token, invitation_id) values (p_label, r.token, r.invitation_id)
    on conflict (label) do update set token = excluded.token, invitation_id = excluded.invitation_id;
    return r.token;
end;
$$;

create or replace function tests.token(p_label text)
returns text language sql stable security definer set search_path = ''
as $$ select t.token from tests.tokens as t where t.label = p_label $$;
create or replace function tests.invitation(p_label text)
returns uuid language sql stable security definer set search_path = ''
as $$ select t.invitation_id from tests.tokens as t where t.label = p_label $$;
grant execute on all functions in schema tests to authenticated, anon;

select tests.create_user('admin');
select tests.create_user('member');
select tests.create_user('viewer');
select tests.create_user('invitee');
select tests.create_user('stranger');
select tests.create_user('other_admin');
select tests.create_user('unconfirmed', false);
select tests.create_group_as('admin', 'House');
select tests.create_group_as('other_admin', 'Other');
select tests.add_member(tests.gid('House'), 'member', 'member');
select tests.add_member(tests.gid('House'), 'viewer', 'viewer');

-- ---------------------------------------------------------------------------
-- Creation
-- ---------------------------------------------------------------------------
select hasnt_column('public', 'group_invitations', 'token', 'raw tokens are not stored');
select has_column('public', 'group_invitations', 'token_hash', 'only a token hash is stored');

select tests.authenticate_as('admin');
select is((select count(*) from public.create_group_invitation(tests.gid('House'), ' Invitee@Example.TEST ', 'member')), 1::bigint,
          'the admin can create an invitation');
reset role;
select tests.invite('admin', 'House', 'invitee@example.test', 'member', 'main');
select ok(tests.token('main') ~ '^[A-Za-z0-9_-]{43}$', 'the token is 256 bits of base64url (43 characters)');
select is((select token_hash from public.group_invitations where id = tests.invitation('main')),
          encode(extensions.digest(tests.token('main'), 'sha256'), 'hex'), 'the stored hash is the SHA-256 of the token');
select is((select email from public.group_invitations where id = tests.invitation('main')), 'invitee@example.test',
          'emails are stored lower-case and trimmed');
select is((select count(*) from public.group_invitations where group_id = tests.gid('House') and email = 'invitee@example.test' and status = 'pending'),
          1::bigint, 're-inviting the same address keeps a single pending invitation');
select ok((select expires_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
           from public.group_invitations where id = tests.invitation('main')), 'invitations expire after 7 days');

select tests.authenticate_as('member');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), 'x@example.test', 'member') $$,
                 '42501', 'not_group_admin', 'members cannot create invitations');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), 'x@example.test', 'admin') $$,
                 '42501', 'not_group_admin', 'members cannot mint admin invitations');
select tests.authenticate_as('viewer');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), 'v@example.test', 'member') $$,
                 '42501', 'not_group_admin', 'viewers cannot create invitations');
select tests.authenticate_as('admin');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), 'x@example.test', 'admin') $$,
                 '22023', 'invalid_role', 'invitations cannot grant admin');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), 'not-an-email', 'member') $$,
                 '22023', 'invalid_email', 'malformed emails are rejected');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), repeat('a', 250) || '@example.test', 'member') $$,
                 '22023', 'invalid_email', 'emails longer than 254 characters are rejected');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('House'), 'member@example.test', 'viewer') $$,
                 '23505', 'already_member', 'approved members cannot be invited again');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('Other'), 'x@example.test', 'member') $$,
                 '42501', 'not_group_admin', 'an admin cannot invite to another admin''s group');
select throws_ok($$ select * from public.create_group_invitation(gen_random_uuid(), 'x@example.test', 'member') $$,
                 'P0002', 'group_not_found', 'inviting to an unknown group raises not found');

-- ---------------------------------------------------------------------------
-- No direct table writes; reads limited to the admin's pending invitations
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.group_invitations (group_id, inviter_id, email, role, token_hash)
                    values (tests.gid('House'), tests.uid('admin'), 'self@example.test', 'member', repeat('a', 64)) $$,
                 '42501', null, 'invitations cannot be inserted directly');
select throws_ok($$ update public.group_invitations set role = 'viewer', expires_at = '2999-01-01', email = 'other@example.test'
                    where id = tests.invitation('main') $$,
                 '42501', null, 'invitations cannot be updated directly');
select throws_ok($$ update public.group_invitations set group_id = tests.gid('Other'), status = 'pending' where id = tests.invitation('main') $$,
                 '42501', null, 'invitations cannot be moved to another group');
select throws_ok($$ delete from public.group_invitations where id = tests.invitation('main') $$,
                 '42501', null, 'invitations cannot be deleted directly');
select throws_ok($$ select token_hash from public.group_invitations $$, '42501', null, 'the token hash is not readable');
select is((select count(*) from public.group_invitations where group_id = tests.gid('House')), 1::bigint,
          'the admin lists the group''s pending invitations');

select tests.authenticate_as('member');
select is((select count(*) from public.group_invitations), 0::bigint, 'members cannot list invitations');
select tests.authenticate_as('viewer');
select is((select count(*) from public.group_invitations), 0::bigint, 'viewers cannot list invitations');
select throws_ok($$ insert into public.group_invitations (group_id, inviter_id, email, role, token_hash)
                    values (tests.gid('House'), tests.uid('viewer'), 'viewer2@example.test', 'member', repeat('b', 64)) $$,
                 '42501', null, 'viewers cannot insert invitations directly');
select tests.authenticate_as('other_admin');
select is((select count(*) from public.group_invitations where group_id = tests.gid('House')), 0::bigint,
          'admins of other groups cannot list this group''s invitations');

-- ---------------------------------------------------------------------------
-- Details (bound to the invited email)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('invitee');
select is((public.get_invitation_details(tests.token('main'))) ->> 'group_name', 'House', 'the invitee sees the group name');
select is((public.get_invitation_details(tests.token('main'))) ->> 'inviter_name', 'Admin', 'the invitee sees the inviter''s display name');
select is((public.get_invitation_details(tests.token('main'))) ->> 'status', 'pending', 'the invitee sees the status');
select ok(not (public.get_invitation_details(tests.token('main')) ? 'email'), 'details do not echo the email');
select throws_ok($$ select public.get_invitation_details('no-such-token') $$, 'P0002', 'invite_not_found', 'unknown tokens raise not found');
select tests.authenticate_as('stranger');
select throws_ok($$ select public.get_invitation_details(tests.token('main')) $$, '42501', 'invite_email_mismatch',
                 'another account cannot read the invitation');
reset role;
set local role anon;
select throws_ok($$ select public.get_invitation_details(tests.token('main')) $$, '42501', null, 'anon cannot read invitation details');
reset role;

-- ---------------------------------------------------------------------------
-- Accept
-- ---------------------------------------------------------------------------
select tests.authenticate_as('stranger');
select throws_ok($$ select public.accept_group_invitation(tests.token('main')) $$, '42501', 'invite_email_mismatch',
                 'an invitation cannot be accepted by another account');
select tests.authenticate_as('unconfirmed');
select throws_ok($$ select public.accept_group_invitation(tests.token('main')) $$, '42501', 'email_not_confirmed',
                 'an account without a confirmed email cannot accept');
select tests.authenticate_as('invitee');
select is((public.accept_group_invitation(tests.token('main'))) ->> 'role', 'member', 'the invitee accepts with the invited role');
reset role;
select is((select role || '/' || status from public.group_members where group_id = tests.gid('House') and user_id = tests.uid('invitee')),
          'member/approved', 'accepting creates an approved membership');
select is((select invited_by from public.group_members where group_id = tests.gid('House') and user_id = tests.uid('invitee')),
          tests.uid('admin'), 'the membership records the inviter');
select is((select status from public.group_invitations where id = tests.invitation('main')), 'accepted', 'the invitation is marked accepted');
select isnt((select responded_at from public.group_invitations where id = tests.invitation('main')), null, 'responded_at is set');
select is((select group_id from public.profiles where id = tests.uid('invitee')), tests.gid('House'), 'the joined group becomes active');
select tests.authenticate_as('invitee');
select throws_ok($$ select public.accept_group_invitation(tests.token('main')) $$, 'P0001', 'invite_already_used',
                 'an invitation can be used once');

-- An approved member accepting a stale invitation keeps their role.
reset role;
select tests.create_user('switcher');
select tests.invite('admin', 'House', 'switcher@example.test', 'viewer', 'stale');
select tests.add_member(tests.gid('House'), 'switcher', 'member');
select tests.authenticate_as('switcher');
select throws_ok($$ select public.accept_group_invitation(tests.token('stale')) $$, '23505', 'already_member',
                 'accepting while already a member raises');
reset role;
select is((select role from public.group_members where group_id = tests.gid('House') and user_id = tests.uid('switcher')), 'member',
          'an existing member''s role is not changed by an invitation');

-- A pending code request is converted by accepting the admin's invitation.
select tests.create_user('requester');
select tests.add_member(tests.gid('House'), 'requester', 'viewer', 'pending');
select tests.invite('admin', 'House', 'requester@example.test', 'member', 'convert');
select tests.authenticate_as('requester');
select lives_ok($$ select public.accept_group_invitation(tests.token('convert')) $$, 'a pending requester can accept an invitation');
reset role;
select is((select role || '/' || status from public.group_members where group_id = tests.gid('House') and user_id = tests.uid('requester')),
          'member/approved', 'the pending request becomes an approved membership with the invited role');

-- ---------------------------------------------------------------------------
-- Decline, revoke, expiry, replacement
-- ---------------------------------------------------------------------------
select tests.create_user('decliner');
select tests.invite('admin', 'House', 'decliner@example.test', 'member', 'decline');
select tests.authenticate_as('stranger');
select throws_ok($$ select public.decline_group_invitation(tests.token('decline')) $$, '42501', 'invite_email_mismatch',
                 'another account cannot decline the invitation');
select tests.authenticate_as('decliner');
select is((public.decline_group_invitation(tests.token('decline'))) ->> 'status', 'declined', 'the invitee declines');
select throws_ok($$ select public.accept_group_invitation(tests.token('decline')) $$, 'P0001', 'invite_declined',
                 'a declined invitation cannot be accepted');
select throws_ok($$ select public.decline_group_invitation(tests.token('decline')) $$, 'P0001', 'invite_declined',
                 'declining twice raises');

reset role;
select tests.create_user('revoked_user');
select tests.invite('admin', 'House', 'revoked_user@example.test', 'member', 'revoke');
select tests.authenticate_as('member');
select throws_ok($$ select public.revoke_group_invitation(tests.invitation('revoke')) $$, '42501', 'not_group_admin',
                 'a non-admin cannot revoke invitations');
select tests.authenticate_as('other_admin');
select throws_ok($$ select public.revoke_group_invitation(tests.invitation('revoke')) $$, '42501', 'not_group_admin',
                 'an admin of another group cannot revoke the invitation');
select throws_ok($$ select public.revoke_group_invitation(gen_random_uuid()) $$, 'P0002', 'invite_not_found',
                 'revoking an unknown invitation raises not found');
select tests.authenticate_as('admin');
select is((public.revoke_group_invitation(tests.invitation('revoke'))) ->> 'status', 'revoked', 'the admin revokes a pending invitation');
select throws_ok($$ select public.revoke_group_invitation(tests.invitation('revoke')) $$, 'P0001', 'invite_not_pending',
                 'revoking twice raises');
select tests.authenticate_as('revoked_user');
select throws_ok($$ select public.accept_group_invitation(tests.token('revoke')) $$, 'P0001', 'invite_revoked',
                 'a revoked invitation cannot be accepted');

reset role;
select tests.create_user('late');
select tests.invite('admin', 'House', 'late@example.test', 'member', 'expired');
update public.group_invitations set expires_at = now() - interval '1 minute' where id = tests.invitation('expired');
select tests.authenticate_as('late');
select is((public.get_invitation_details(tests.token('expired'))) ->> 'status', 'expired', 'details report an expired invitation');
select throws_ok($$ select public.accept_group_invitation(tests.token('expired')) $$, 'P0001', 'invite_expired',
                 'an expired invitation cannot be accepted');
select tests.authenticate_as('admin');
select is((select count(*) from public.group_invitations where id = tests.invitation('expired')), 0::bigint,
          'expired invitations are not listed');

reset role;
select tests.create_user('twice');
select tests.invite('admin', 'House', 'twice@example.test', 'viewer', 'first');
select tests.invite('admin', 'House', 'twice@example.test', 'member', 'second');
select tests.authenticate_as('twice');
select throws_ok($$ select public.accept_group_invitation(tests.token('first')) $$, 'P0001', 'invite_revoked',
                 're-inviting an address revokes the previous pending invitation');
select is((public.accept_group_invitation(tests.token('second'))) ->> 'role', 'member', 'the newest invitation works');

-- ---------------------------------------------------------------------------
-- Bans: removal withdraws pending invitations; a new invitation lifts the ban.
-- ---------------------------------------------------------------------------
reset role;
select tests.invite('admin', 'House', 'stranger@example.test', 'member', 'before_removal');
select tests.add_member(tests.gid('House'), 'stranger', 'viewer', 'pending');
select tests.authenticate_as('admin');
select public.remove_member(tests.gid('House'), tests.uid('stranger'));
reset role;
select is((select status from public.group_invitations where id = tests.invitation('before_removal')), 'revoked',
          'removing a user withdraws their pending invitations to the group');
select tests.invite('admin', 'House', 'stranger@example.test', 'viewer', 'after_removal');
select is((select count(*) from public.group_bans where group_id = tests.gid('House') and user_id = tests.uid('stranger')), 0::bigint,
          'an admin invitation lifts the ban');
select tests.authenticate_as('stranger');
select is((public.accept_group_invitation(tests.token('after_removal'))) ->> 'role', 'viewer', 'the re-invited user can join');

-- ---------------------------------------------------------------------------
-- Rate limits
-- ---------------------------------------------------------------------------
reset role;
select tests.invite('admin', 'House', 'popular@example.test', 'member', 'p' || i) from generate_series(1, 4) as i;
select tests.authenticate_as('other_admin');
select lives_ok($$ select * from public.create_group_invitation(tests.gid('Other'), 'popular@example.test', 'member') $$,
                'five invitations per recipient per day are allowed (across groups)');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('Other'), 'popular@example.test', 'viewer') $$,
                 'P0001', 'rate_limited', 'the sixth invitation to the same address in a day is refused');

reset role;
select tests.create_user('busy');
select tests.create_group_as('busy', 'Busy');
select tests.invite('busy', 'Busy', 'guest' || i || '@example.test', 'member', 'b' || i) from generate_series(1, 20) as i;
select tests.authenticate_as('busy');
select throws_ok($$ select * from public.create_group_invitation(tests.gid('Busy'), 'guest21@example.test', 'member') $$,
                 'P0001', 'rate_limited', 'an inviter is limited to 20 invitations per hour');

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------
select throws_ok($$ select public.purge_old_invitations() $$, '42501', null, 'clients cannot run the cleanup');
reset role;
update public.group_invitations set created_at = now() - interval '91 days' where id = tests.invitation('main');
select tests.invite('admin', 'House', 'stale-pending@example.test', 'member', 'stale_pending');
update public.group_invitations set expires_at = now() - interval '1 day' where id = tests.invitation('stale_pending');
set local role service_role;
select lives_ok($$ select public.purge_old_invitations() $$, 'service_role runs the cleanup');
reset role;
select is((select count(*) from public.group_invitations where id = tests.invitation('main')), 0::bigint,
          'answered invitations older than 90 days are deleted');
select is((select status from public.group_invitations where id = tests.invitation('stale_pending')), 'expired',
          'past-due pending invitations are marked expired');

select * from finish();
rollback;
