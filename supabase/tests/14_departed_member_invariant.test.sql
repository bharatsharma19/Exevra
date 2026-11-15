-- Once someone is no longer an approved member of a group (left, removed, banned, or anonymised by
-- account deletion), nothing may change their balance in that group except deleting the whole group:
--   * a confirmed settlement with a departed or former party cannot be voided, and a pending one with
--     such a party cannot be confirmed (P0001 settlement_locked_member_left);
--   * leaving or being removed (also with p_force) voids the member's pending settlements in that
--     group, both directions, with an audit event (reason member_left / member_removed);
--   * the payer of a group expense is always an approved admin or member when it is written
--     (42501 payer_not_member), and only an account deletion can set it to NULL.
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

-- Inserts a settlement row directly (fixture only: data a race or an older version could leave).
create or replace function tests.raw_settlement(p_name text, p_group text, p_from text, p_to text, p_amount bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_id uuid;
begin
    insert into public.settlements (group_id, from_user, to_user, amount_minor, status, created_by)
    values (tests.gid(p_group), case when p_from is null then null else tests.uid(p_from) end,
            case when p_to is null then null else tests.uid(p_to) end, p_amount, 'pending',
            case when p_from is null then null else tests.uid(p_from) end)
    returning id into v_id;
    insert into tests.settlements (name, id) values (p_name, v_id);
    return v_id;
end;
$$;

create or replace function tests.settlement_state(p_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$ select s.status || '/' || coalesce(s.void_reason, '-') from public.settlements as s where s.id = tests.sid(p_name) $$;

grant execute on all functions in schema tests to anon, authenticated;

select plan(51);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_user('dan');
select tests.create_user('erin');
select tests.create_user('fay');
select tests.create_user('gus');
select tests.create_user('ivy');
select tests.create_user('jon');
select tests.create_user('kim');
select tests.create_user('lee');
select tests.create_user('mo');
select tests.create_user('ned');

-- ===========================================================================
-- 1. Confirmed settlements with a departed party cannot be voided.
-- ===========================================================================
select tests.create_group_as('alice', 'Trip', 'INR');
select tests.add_member(tests.gid('Trip'), 'bob', 'member');
select tests.add_member(tests.gid('Trip'), 'carol', 'member');
select tests.add_expense('alice', 'Trip', 'Hotel', 900);
select tests.settle('s1', 'bob', 'Trip', 'alice', 300);
select tests.authenticate_as('alice');
select public.confirm_settlement(tests.sid('s1'));
select tests.authenticate_as('bob');
select is((public.leave_group(tests.gid('Trip')))->>'left', 'true', 'bob settles and leaves');
reset role;
select is(tests.net('Trip', 'bob'), 0::bigint, 'bob left with a zero balance');

select tests.authenticate_as('alice');
select throws_ok($$ select public.void_settlement(tests.sid('s1'), 'oops') $$,
                 'P0001', 'settlement_locked_member_left',
                 'the admin cannot void a confirmed settlement paid by a member who left');
reset role;
select is(tests.settlement_state('s1'), 'confirmed/-', 'the settlement stays confirmed');
select is(tests.net('Trip', 'bob'), 0::bigint, 'and bob''s balance is unchanged');
select is((select count(*) from public.settlement_events where settlement_id = tests.sid('s1') and action = 'voided'),
          0::bigint, 'no void was recorded');

-- Settlements among current members keep the old rules.
select tests.settle('s2', 'carol', 'Trip', 'alice', 300);
select tests.authenticate_as('carol');
select lives_ok($$ select public.void_settlement(tests.sid('s2'), 'not yet') $$, 'a party can still void a pending settlement');
reset role;
select tests.settle('s3', 'carol', 'Trip', 'alice', 300);
select tests.authenticate_as('alice');
select lives_ok($$ select public.confirm_settlement(tests.sid('s3')) $$, 'the payee confirms a settlement among members');
select lives_ok($$ select public.void_settlement(tests.sid('s3'), 'entered twice') $$,
                'and a confirmed settlement among current members can still be voided');
reset role;
select is(tests.settlement_state('s3'), 'voided/entered twice', 'it is voided');

-- A former member (deleted account) counts as departed.
select tests.create_group_as('erin', 'Loft', 'INR');
select tests.add_member(tests.gid('Loft'), 'dan', 'member');
select tests.add_expense('erin', 'Loft', 'Paint', 200);
select tests.settle('l1', 'dan', 'Loft', 'erin', 100);
select tests.authenticate_as('erin');
select public.confirm_settlement(tests.sid('l1'));
reset role;
delete from auth.users where id = tests.uid('dan');
select is((select from_user from public.settlements where id = tests.sid('l1')), null::uuid, 'the payer is now a former member');
select tests.authenticate_as('erin');
select throws_ok($$ select public.void_settlement(tests.sid('l1'), 'gone') $$,
                 'P0001', 'settlement_locked_member_left',
                 'a confirmed settlement with a former member cannot be voided either');
reset role;
select is(tests.settlement_state('l1'), 'confirmed/-', 'it stays confirmed');
select is(tests.net('Loft', null), 0::bigint, 'the former member''s balance is unchanged');

-- ===========================================================================
-- 2. Pending settlements of a departing member are voided; confirming one is refused.
-- ===========================================================================
select tests.create_group_as('erin', 'Flat', 'INR');
select tests.add_member(tests.gid('Flat'), 'fay', 'member');
select tests.add_member(tests.gid('Flat'), 'gus', 'member');
select tests.add_expense('erin', 'Flat', 'Rent', 900);
select tests.add_expense('gus', 'Flat', 'Wifi', 300);
select tests.settle('p1', 'fay', 'Flat', 'erin', 300);
select tests.settle('p2', 'gus', 'Flat', 'erin', 100);
select tests.authenticate_as('erin');
select throws_ok($$ select public.remove_member(tests.gid('Flat'), tests.uid('fay')) $$,
                 'P0001', 'outstanding_balance', 'a member with a pending settlement needs p_force');
select is((public.remove_member(tests.gid('Flat'), tests.uid('fay'), true))->>'removed', 'true',
          'the admin removes fay with p_force');
reset role;
select is(tests.settlement_state('p1'), 'voided/member_removed', 'fay''s pending settlement is voided');
select is((select voided_by from public.settlements where id = tests.sid('p1')), tests.uid('erin'),
          'voided by the admin who removed her');
select is((select details from public.settlement_events where settlement_id = tests.sid('p1') and action = 'voided'),
          '{"reason": "member_removed", "previous_status": "pending"}'::jsonb, 'the void is in the audit trail');
select is((select actor from public.settlement_events where settlement_id = tests.sid('p1') and action = 'voided'),
          tests.uid('erin'), 'with the admin as actor');
select tests.authenticate_as('erin');
select throws_ok($$ select public.confirm_settlement(tests.sid('p1')) $$,
                 'P0001', 'settlement_not_pending', 'the payee can no longer confirm it');
reset role;
select is(tests.net('Flat', 'fay'), -400::bigint, 'fay''s balance stays as it was when she was removed');
select is(tests.settlement_state('p2'), 'pending/-', 'other members'' pending settlements are untouched');

-- Both directions: a pending settlement TO the departing member is voided too.
select tests.add_member(tests.gid('Flat'), 'kim', 'member');
select tests.raw_settlement('p3', 'Flat', 'gus', 'kim', 50);
select tests.authenticate_as('erin');
select is((public.remove_member(tests.gid('Flat'), tests.uid('kim'), true))->>'removed', 'true', 'the admin removes kim');
reset role;
select is(tests.settlement_state('p3'), 'voided/member_removed', 'a pending settlement to the removed member is voided');

-- Any other removal path (here: the membership row deleted directly) voids with member_left.
select tests.remove_member(tests.gid('Flat'), 'gus');
select is(tests.settlement_state('p2'), 'voided/member_left', 'a departure by any path voids the pending settlements');
select is((select details->>'reason' from public.settlement_events where settlement_id = tests.sid('p2') and action = 'voided'),
          'member_left', 'with reason member_left in the audit trail');

-- A pending settlement left behind with a departed party (older data, a race) cannot be confirmed.
select tests.raw_settlement('p4', 'Flat', 'fay', 'erin', 10);
select tests.raw_settlement('p5', 'Flat', null, 'erin', 10);
select tests.authenticate_as('erin');
select throws_ok($$ select public.confirm_settlement(tests.sid('p4')) $$,
                 'P0001', 'settlement_locked_member_left', 'confirming a settlement from a departed member is refused');
select throws_ok($$ select public.confirm_settlement(tests.sid('p5')) $$,
                 'P0001', 'settlement_locked_member_left', 'and from a former member');
select lives_ok($$ select public.void_settlement(tests.sid('p4'), 'stale') $$, 'such a pending settlement can still be voided');
reset role;
select is(tests.net('Flat', 'fay'), -400::bigint, 'fay''s balance never changed');

-- Account deletion voids the user's pending settlements (both directions).
select tests.create_group_as('ivy', 'Club', 'INR');
select tests.add_member(tests.gid('Club'), 'jon', 'member');
select tests.add_member(tests.gid('Club'), 'mo', 'member');
select tests.add_expense('mo', 'Club', 'Nets', 600);
select tests.settle('c1', 'jon', 'Club', 'mo', 100);
select tests.settle('c2', 'ivy', 'Club', 'mo', 100);
select tests.raw_settlement('c3', 'Club', 'ivy', 'jon', 5);
delete from auth.users where id = tests.uid('jon');
select is(tests.settlement_state('c1'), 'voided/account_deleted', 'the deleted user''s outgoing pending settlement is voided');
select is(tests.settlement_state('c3'), 'voided/account_deleted', 'and the incoming one');
select is(tests.settlement_state('c2'), 'pending/-', 'a settlement between remaining members stays pending');

-- ===========================================================================
-- 3. Payer integrity: the payer of a group expense is an approved admin or member.
-- ===========================================================================
select tests.create_user('ola');
select tests.create_user('pia');
select tests.create_group_as('ola', 'Camp', 'INR');
select tests.add_member(tests.gid('Camp'), 'pia', 'member');
select tests.add_member(tests.gid('Camp'), 'kim', 'viewer');
select tests.add_member(tests.gid('Camp'), 'lee', 'viewer', 'pending');
select tests.add_member(tests.gid('Camp'), 'ned', 'member');
select tests.remove_member(tests.gid('Camp'), 'ned');

select throws_ok($$ select tests.add_expense('kim', 'Camp', 'By viewer', 100) $$,
                 '42501', 'payer_not_member', 'a viewer cannot be the payer, even for the table owner');
select throws_ok($$ select tests.add_expense('lee', 'Camp', 'By pending', 100) $$,
                 '42501', 'payer_not_member', 'nor a pending member');
select throws_ok($$ select tests.add_expense('mo', 'Camp', 'By stranger', 100) $$,
                 '42501', 'payer_not_member', 'nor a non-member');
select throws_ok($$ select tests.add_expense('ned', 'Camp', 'By departed', 100) $$,
                 '42501', 'payer_not_member', 'nor a member who was removed');
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                    values (null, tests.gid('Camp'), 'By nobody', 100, 'Food') $$,
                 '42501', 'payer_not_member', 'nor nobody');
select set_config('tests.camp', tests.gid('Camp')::text, true);
select set_config('tests.kim', tests.uid('kim')::text, true);
set local role service_role;
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                    values (current_setting('tests.kim')::uuid, current_setting('tests.camp')::uuid, 'SR viewer', 100, 'Food') $$,
                 '42501', 'payer_not_member', 'the service role cannot charge a viewer as payer');
reset role;
select lives_ok($$ select tests.add_expense('pia', 'Camp', 'Tent', 300) $$, 'an approved member can be the payer');
select lives_ok($$ select tests.add_expense('ola', 'Camp', 'Stove', 300) $$, 'and the admin');

select throws_ok($$ update public.expenses set user_id = tests.uid('kim') where id = tests.eid('Tent') $$,
                 '42501', 'payer_not_member', 'the payer cannot change to a viewer');
select throws_ok($$ update public.expenses set user_id = tests.uid('ned') where id = tests.eid('Tent') $$,
                 '42501', 'payer_not_member', 'nor to a departed member');
select throws_ok($$ update public.expenses set user_id = null where id = tests.eid('Tent') $$,
                 '42501', 'payer_not_member', 'nor be cleared by a direct update');
select set_config('tests.tent', tests.eid('Tent')::text, true);
set local role service_role;
select throws_ok($$ update public.expenses set user_id = null where id = current_setting('tests.tent')::uuid $$,
                 '42501', 'payer_not_member', 'not even by the service role');
reset role;
select lives_ok($$ update public.expenses set user_id = tests.uid('ola') where id = tests.eid('Tent') $$,
                'a privileged writer can still move the payer to another approved member');
select is(tests.share('Tent', 'ola'), 150::bigint, 'and the amount is re-split among the same participants');

-- Account deletion still clears the payer through the foreign key.
select tests.add_expense('pia', 'Camp', 'Fuel', 90);
select lives_ok($$ delete from auth.users where id = tests.uid('pia') $$, 'a payer''s account can be deleted');
select is((select user_id from public.expenses where id = tests.eid('Fuel')), null::uuid,
          'the expense she paid is kept with a former-member payer');
select is((select sum(net_minor) from public.group_balance_rows(tests.gid('Camp'))), 0::numeric, 'balances still sum to zero');

select * from finish();
rollback;
