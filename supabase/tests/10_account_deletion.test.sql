-- Account deletion: admin rights pass to the longest-standing member, a group with no other member
-- is deleted, personal data (expenses, AI data, invitations, profile) is removed, and shared group
-- history stays with the user shown as a former member, so balances still sum to zero. Only
-- service_role may run it; it is idempotent; deleting the auth user by any path runs it first.
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

select plan(56);

select tests.create_user('ann');
select tests.create_user('ben');
select tests.create_user('max');
select tests.create_user('pat');
select tests.create_user('dee');
select tests.create_user('eve');
select tests.create_user('fay');

-- Flat: ann administers it; ben joined before max; pat is still pending; dee was invited by ann.
select tests.create_group_as('ann', 'Flat', 'INR');
select tests.add_member(tests.gid('Flat'), 'ben', 'member', 'approved', now() - interval '10 days');
select tests.add_member(tests.gid('Flat'), 'max', 'member', 'approved', now() - interval '5 days');
select tests.add_member(tests.gid('Flat'), 'pat', 'viewer', 'pending');
select tests.add_member(tests.gid('Flat'), 'dee', 'viewer', 'approved', now() - interval '1 day');
select set_config('exevra.membership_rpc', 'on', true);
update public.group_members set invited_by = tests.uid('ann') where group_id = tests.gid('Flat') and user_id = tests.uid('dee');
select set_config('exevra.membership_rpc', 'off', true);
-- Club: ben administers it, ann is a member.
select tests.create_group_as('ben', 'Club', 'INR');
select tests.add_member(tests.gid('Club'), 'ann');
-- Solo: ann is the only approved member (pat only asked to join).
select tests.create_group_as('ann', 'Solo', 'INR');
select tests.add_member(tests.gid('Solo'), 'pat', 'viewer', 'pending');
-- Third: ben's group, with a pending invitation for ann's address and a ban on ann.
select tests.create_group_as('ben', 'Third', 'INR');

select tests.add_expense('ben', 'Flat', 'Rent', 900);
select tests.add_expense('ann', 'Flat', 'Power', 600);
select tests.add_expense('max', 'Flat', 'Wifi', 300);
select tests.add_expense('ann', 'Club', 'Dinner', 1000);
select tests.add_expense('ben', 'Club', 'Lunch', 400);
select tests.add_expense('ann', 'Solo', 'Solo thing', 100);
select tests.add_expense('ann', null, 'Ann personal', 500);
select tests.add_expense('ben', null, 'Ben personal', 700);

-- Club: ben owes ann 300; he pays 100 (confirmed) and has 50 more pending.
select tests.settle('paid', 'ben', 'Club', 'ann', 100);
select tests.set_claims('ann');
select public.confirm_settlement(tests.sid('paid'));
select tests.settle('in_flight', 'ben', 'Club', 'ann', 50);

-- AI usage, a report, invitations both ways, a ban.
select tests.set_claims('ann');
select public.consume_ai_quota(10, 5);
insert into public.ai_reports (user_id, reason, message_excerpt) values (tests.uid('ann'), 'other', 'x');
select public.create_group_invitation(tests.gid('Flat'), 'friend@example.test', 'member');
select tests.set_claims('ben');
select public.create_group_invitation(tests.gid('Third'), 'ann@example.test', 'viewer');
insert into public.group_bans (group_id, user_id, banned_by) values (tests.gid('Third'), tests.uid('ann'), tests.uid('ben'));

create table tests.result (name text primary key, doc jsonb);
grant usage on schema tests to service_role;
grant all on tests.result to service_role;
grant execute on all functions in schema tests to service_role;

-- ===========================================================================
-- Who may run it
-- ===========================================================================
select tests.authenticate_as('ann');
select throws_ok(format($$ select public.prepare_account_deletion(%L) $$, tests.uid('ann')), '42501', null,
                 'a signed-in user cannot run account deletion directly');
reset role;
select ok(not has_function_privilege('authenticated', 'public.prepare_account_deletion(uuid)', 'execute'),
          'authenticated has no EXECUTE on prepare_account_deletion');
select ok(not has_function_privilege('anon', 'public.prepare_account_deletion(uuid)', 'execute'),
          'anon has no EXECUTE on prepare_account_deletion');
select ok(has_function_privilege('service_role', 'public.prepare_account_deletion(uuid)', 'execute'),
          'service_role may run prepare_account_deletion');
select ok(to_regprocedure('public.delete_user_account()') is null, 'the client-callable delete_user_account is gone');

-- ===========================================================================
-- Prepare (service_role, as the Edge Function does)
-- ===========================================================================
set local role service_role;
select lives_ok(format($$ insert into tests.result values ('first', public.prepare_account_deletion(%L)) $$, tests.uid('ann')),
                'service_role prepares the account for deletion');
reset role;

select is((select doc->'groups_deleted' from tests.result where name = 'first'), jsonb_build_array(tests.gid('Solo')),
          'a group with no other approved member is deleted');
select is((select doc->'admin_transferred' from tests.result where name = 'first'),
          jsonb_build_array(jsonb_build_object('group_id', tests.gid('Flat'), 'new_admin_id', tests.uid('ben'))),
          'the administered group with members is handed over');
select is((select (doc->>'settlements_voided')::int from tests.result where name = 'first'), 1, 'one pending settlement voided');
select is((select (doc->>'personal_expenses_deleted')::int from tests.result where name = 'first'), 1, 'one personal expense deleted');
select is((select (doc->>'memberships_removed')::int from tests.result where name = 'first'), 2,
          'memberships removed: the handed-over admin row and the plain membership');
select is((select (doc->>'ai_usage_events_deleted')::int from tests.result where name = 'first'), 1, 'AI usage deleted');
select is((select (doc->>'ai_reports_deleted')::int from tests.result where name = 'first'), 1, 'AI reports deleted');
select is((select (doc->>'invitations_deleted')::int from tests.result where name = 'first'), 2, 'sent and received invitations deleted');
select is((select (doc->>'profile_deleted')::boolean from tests.result where name = 'first'), true, 'profile deleted');

select is((select admin_id from public.groups where id = tests.gid('Flat')), tests.uid('ben'),
          'admin passes to the longest-standing approved member');
select is((select role from public.group_members where group_id = tests.gid('Flat') and user_id = tests.uid('ben')), 'admin',
          'the successor''s membership row says admin');
select is((select count(*) from public.group_members where group_id = tests.gid('Flat') and role = 'admin'), 1::bigint,
          'still exactly one admin');
select is((select role from public.group_members where group_id = tests.gid('Flat') and user_id = tests.uid('max')), 'member',
          'other members keep their role');
select is((select count(*) from public.groups where id = tests.gid('Solo')), 0::bigint, 'the sole-member group is gone');
select is((select count(*) from public.expenses where title = 'Solo thing'), 0::bigint, 'with its expenses');
select is((select count(*) from public.group_members where user_id = tests.uid('pat')), 1::bigint,
          'a pending request elsewhere is untouched (only the deleted group''s request went with it)');
select is((select count(*) from public.group_members where user_id = tests.uid('ann')), 0::bigint, 'no memberships remain');
select is((select admin_id from public.groups where id = tests.gid('Club')), tests.uid('ben'), 'groups administered by others are unchanged');
select is((select count(*) from public.expenses where user_id = tests.uid('ann') and group_id is null), 0::bigint,
          'personal expenses are deleted');
select is((select count(*) from public.expenses where title = 'Ben personal'), 1::bigint, 'other users'' personal expenses are untouched');
select is((select count(*) from public.profiles where id = tests.uid('ann')), 0::bigint, 'the profile is deleted');
select is((select count(*) from public.group_bans where user_id = tests.uid('ann')), 0::bigint, 'bans on the user are deleted');
select is((select row(status, void_reason)::text from public.settlements where id = tests.sid('in_flight')), '(voided,account_deleted)',
          'a pending settlement with the user is voided');
select is((select count(*) from public.settlement_events where settlement_id = tests.sid('in_flight') and action = 'voided'), 1::bigint,
          'the void is recorded in the audit trail');
select is((select status from public.settlements where id = tests.sid('paid')), 'confirmed', 'confirmed settlements are kept as they are');

set local role service_role;
select lives_ok(format($$ insert into tests.result values ('second', public.prepare_account_deletion(%L)) $$, tests.uid('ann')),
                'running it again succeeds');
reset role;
select is((select doc - 'user_id' from tests.result where name = 'second'),
          '{"admin_transferred": [], "groups_deleted": [], "settlements_voided": 0, "memberships_removed": 0,
            "personal_expenses_deleted": 0, "ai_usage_events_deleted": 0, "ai_reports_deleted": 0,
            "invitations_deleted": 0, "profile_deleted": false}'::jsonb,
          'the second run finds nothing left to change');

-- ===========================================================================
-- auth.admin.deleteUser: shared history stays, anonymised
-- ===========================================================================
select lives_ok(format($$ delete from auth.users where id = %L $$, tests.uid('ann')), 'the auth user can then be deleted');
select is((select count(*) from auth.users where id = tests.uid('ann')), 0::bigint, 'the auth user is gone');

select is((select count(*) from public.expenses where group_id = tests.gid('Flat') and title in ('Rent', 'Wifi')), 2::bigint,
          'other members'' group expenses are untouched');
select is((select user_id from public.expenses where title = 'Power'), null, 'a group expense the user paid is kept with no payer');
select is((select sum(share_minor) from public.expense_splits where expense_id = tests.eid('Rent')), 900::numeric,
          'splits still sum to the amount');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Rent') and user_id is null), 1::bigint,
          'the user''s share is kept as a former member''s share');
select is((select count(*) from public.settlements where group_id = tests.gid('Club')), 2::bigint, 'settlements are kept');
select is((select to_user from public.settlements where id = tests.sid('paid')), null, 'the settlement is anonymised');
select is((select count(*) from public.expenses where title = 'Dinner' and user_id is null), 1::bigint,
          'group expenses in a group the user did not administer are kept too');

select tests.authenticate_as('ben');
select is((select sum(net_minor) from public.get_group_balances(tests.gid('Flat'))), 0::numeric, 'Flat balances still sum to zero');
select is((select sum(net_minor) from public.get_group_balances(tests.gid('Club'))), 0::numeric, 'Club balances still sum to zero');
select is((select net_minor from public.get_group_balances(tests.gid('Club')) where user_id is null), 200::bigint,
          'the former member keeps their balance (300 owed to them, 100 settled)');
select is((select display_name from public.get_group_balances(tests.gid('Club')) where user_id is null), 'Former member',
          'and is shown as a former member');
reset role;

select is((select count(*) from public.ai_usage_events where user_id = tests.uid('ann')), 0::bigint, 'no AI usage left');
select is((select count(*) from public.ai_reports where user_id = tests.uid('ann')), 0::bigint, 'no AI reports left');
select is((select count(*) from public.group_invitations where email = 'ann@example.test' or email = 'friend@example.test'), 0::bigint,
          'no invitations to or from the user left');
select is((select invited_by from public.group_members where group_id = tests.gid('Flat') and user_id = tests.uid('dee')), null,
          'a member the user invited stays, without the inviter reference');

set local role service_role;
select throws_ok(format($$ select public.prepare_account_deletion(%L) $$, tests.uid('ann')), 'P0002', 'user_not_found',
                 'after the auth user is gone the function reports it');
select throws_ok($$ select public.prepare_account_deletion(null) $$, '22023', 'invalid_target', 'a NULL id is rejected');
reset role;

-- ===========================================================================
-- Deleting an auth user by any other path runs the same preparation
-- ===========================================================================
select tests.create_group_as('eve', 'Garden', 'INR');
select tests.add_member(tests.gid('Garden'), 'fay');
select tests.add_expense('fay', 'Garden', 'Seeds', 400);
select lives_ok(format($$ delete from auth.users where id = %L $$, tests.uid('eve')),
                'an admin can be deleted without calling the function first');
select is((select admin_id from public.groups where id = tests.gid('Garden')), tests.uid('fay'),
          'the group survives and passes to the remaining member');
select is((select count(*) from public.expenses where title = 'Seeds'), 1::bigint, 'with its expenses');
select ok(exists (select 1 from pg_trigger where tgname = 'on_auth_user_deleted' and tgrelid = 'auth.users'::regclass),
          'auth.users has the deletion trigger');

select * from finish();
rollback;
