-- Expense splits: the equal-split function (exact sums, deterministic remainder), which members take
-- part in a group expense, stability of existing splits when membership changes, re-splitting on an
-- amount change, a zero-decimal currency, and read-only access for group members.
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

grant execute on all functions in schema tests to anon, authenticated;

select plan(57);

-- ---------------------------------------------------------------------------
-- split_equal_shares
-- ---------------------------------------------------------------------------
create temporary table ids (n int primary key, id uuid not null);
insert into ids values
    (1, '00000000-0000-0000-0000-000000000001'),
    (2, '00000000-0000-0000-0000-000000000002'),
    (3, '00000000-0000-0000-0000-000000000003'),
    (4, '00000000-0000-0000-0000-000000000004');

select results_eq(
    $$ select user_id, share_minor from public.split_equal_shares(90, array(select id from ids where n <= 3), null) order by user_id $$,
    $$ values ('00000000-0000-0000-0000-000000000001'::uuid, 30::bigint),
              ('00000000-0000-0000-0000-000000000002'::uuid, 30::bigint),
              ('00000000-0000-0000-0000-000000000003'::uuid, 30::bigint) $$,
    'an evenly divisible total is split equally');

select results_eq(
    $$ select user_id, share_minor from public.split_equal_shares(100, array(select id from ids where n <= 3),
                                                                   '00000000-0000-0000-0000-000000000003') order by user_id $$,
    $$ values ('00000000-0000-0000-0000-000000000001'::uuid, 33::bigint),
              ('00000000-0000-0000-0000-000000000002'::uuid, 33::bigint),
              ('00000000-0000-0000-0000-000000000003'::uuid, 34::bigint) $$,
    'a single leftover unit goes to the payer');

select results_eq(
    $$ select user_id, share_minor from public.split_equal_shares(102, array(select id from ids order by n desc),
                                                                   '00000000-0000-0000-0000-000000000003') order by user_id $$,
    $$ values ('00000000-0000-0000-0000-000000000001'::uuid, 26::bigint),
              ('00000000-0000-0000-0000-000000000002'::uuid, 25::bigint),
              ('00000000-0000-0000-0000-000000000003'::uuid, 26::bigint),
              ('00000000-0000-0000-0000-000000000004'::uuid, 25::bigint) $$,
    'further leftover units go to the other members by ascending user id');

select results_eq(
    $$ select user_id, share_minor from public.split_equal_shares(2, array(select id from ids where n <= 3), '99999999-0000-0000-0000-000000000000') order by user_id $$,
    $$ values ('00000000-0000-0000-0000-000000000001'::uuid, 1::bigint),
              ('00000000-0000-0000-0000-000000000002'::uuid, 1::bigint),
              ('00000000-0000-0000-0000-000000000003'::uuid, 0::bigint) $$,
    'a payer outside the participants gets no priority');

select results_eq(
    $$ select user_id, share_minor from public.split_equal_shares(7, array(select id from ids order by random()), '00000000-0000-0000-0000-000000000002') order by user_id $$,
    $$ select user_id, share_minor from public.split_equal_shares(7, array(select id from ids order by n), '00000000-0000-0000-0000-000000000002') order by user_id $$,
    'the result does not depend on the order of the member list');

select is((select count(*) from public.split_equal_shares(10, array['00000000-0000-0000-0000-000000000001'::uuid,
                                                                     '00000000-0000-0000-0000-000000000001'::uuid], null)),
          1::bigint, 'duplicate member ids count once');

select is(
    (select count(*) from generate_series(1, 400) as t(total)
     cross join generate_series(1, 7) as k(n)
     cross join lateral (
         select sum(s.share_minor) as total_shares, max(s.share_minor) - min(s.share_minor) as spread, count(*) as cnt
         from public.split_equal_shares(t.total, array(select gen_random_uuid() from generate_series(1, k.n)), null) as s
     ) as r
     where r.total_shares <> t.total or r.spread > 1 or r.cnt <> k.n),
    0::bigint,
    'shares always sum exactly to the total and differ by at most one unit');

select throws_ok($$ select * from public.split_equal_shares(10, array[]::uuid[], null) $$, '22023', 'no_split_members',
                 'a split needs at least one participant');
select throws_ok($$ select * from public.split_equal_shares(-1, array['00000000-0000-0000-0000-000000000001'::uuid], null) $$,
                 '22023', 'invalid_amount', 'a negative total is rejected');
select is((select provolatile::text from pg_proc where oid = 'public.split_equal_shares(bigint, uuid[], uuid)'::regprocedure), 'i',
          'split_equal_shares is IMMUTABLE');
select ok((select prosrc from pg_proc where oid = 'public.split_equal_shares(bigint, uuid[], uuid)'::regprocedure)
          like '%-- Remainder distribution rule (deterministic)%',
          'the remainder rule is a clearly delimited block');

-- ---------------------------------------------------------------------------
-- Splits written for group expenses
-- ---------------------------------------------------------------------------
select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_user('vic');
select tests.create_user('pete');
select tests.create_user('dan');
select tests.create_user('outsider');
select tests.create_group_as('alice', 'Flat', 'INR');
select tests.add_member(tests.gid('Flat'), 'bob', 'member');
select tests.add_member(tests.gid('Flat'), 'carol', 'member');
select tests.add_member(tests.gid('Flat'), 'vic', 'viewer');
select tests.add_member(tests.gid('Flat'), 'pete', 'viewer', 'pending');

select tests.authenticate_as('alice');
select lives_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                   values (auth.uid(), tests.gid('Flat'), 'Dinner', 1000, 'Food') $$, 'a group expense is added');
reset role;
insert into tests.expenses (name, id) select 'Dinner', id from public.expenses where title = 'Dinner';

select is((select count(*) from public.expense_splits where expense_id = tests.eid('Dinner')), 3::bigint,
          'admins and members take part in the split');
select is((select sum(share_minor) from public.expense_splits where expense_id = tests.eid('Dinner')), 1000::numeric,
          'the shares add up to the amount');
select is(tests.share('Dinner', 'alice'), 334::bigint, 'the payer absorbs the leftover unit');
select is(tests.share('Dinner', 'bob'), 333::bigint, 'a member owes an equal share');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Dinner') and user_id = tests.uid('vic')), 0::bigint,
          'viewers are not charged');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Dinner') and user_id = tests.uid('pete')), 0::bigint,
          'pending members are not charged');
select is((select count(distinct group_id) from public.expense_splits where expense_id = tests.eid('Dinner')), 1::bigint,
          'split rows carry the expense group');

-- A late joiner is not charged for earlier expenses.
select tests.add_member(tests.gid('Flat'), 'dan', 'member');
select tests.add_expense('bob', 'Flat', 'Taxi', 1000);
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Dinner') and user_id = tests.uid('dan')), 0::bigint,
          'a member who joins later is not added to earlier splits');
select is(tests.share('Taxi', 'dan'), 250::bigint, 'a member who joined is charged for later expenses');

-- An amount change re-splits among the same participants.
select tests.authenticate_as('alice');
select lives_ok($$ update public.expenses set amount_minor = 1001 where title = 'Dinner' $$, 'the payer can change the amount');
reset role;
select is((select sum(share_minor) from public.expense_splits where expense_id = tests.eid('Dinner')), 1001::numeric,
          'the new amount is fully split');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Dinner')), 3::bigint,
          'the participants stay the same after an amount change');
select is(tests.share('Dinner', 'alice'), 334::bigint, 'the payer still receives the first leftover unit');
select is((select share_minor from public.expense_splits where expense_id = tests.eid('Dinner')
           and user_id = (select min(user_id::text)::uuid from public.expense_splits
                          where expense_id = tests.eid('Dinner') and user_id <> tests.uid('alice'))),
          334::bigint, 'the next leftover unit goes to the lowest other user id');
select tests.authenticate_as('alice');
select lives_ok($$ update public.expenses set title = 'Team dinner' where title = 'Dinner' $$, 'a title edit is allowed');
reset role;
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Dinner')), 3::bigint,
          'edits that keep the amount leave the splits alone');

-- Leaving the group keeps existing splits; a deleted account becomes a former member.
select tests.remove_member(tests.gid('Flat'), 'carol');
select is(tests.share('Taxi', 'carol'), 250::bigint, 'a member who leaves keeps their share of earlier expenses');
select tests.add_expense('alice', 'Flat', 'After carol', 300);
select is((select count(*) from public.expense_splits where expense_id = tests.eid('After carol') and user_id = tests.uid('carol')), 0::bigint,
          'a former member is not charged for new expenses');
delete from auth.users where id = tests.uid('dan');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Taxi') and user_id is null), 1::bigint,
          'a deleted account''s share is kept without a user');
select is((select sum(share_minor) from public.expense_splits where expense_id = tests.eid('Taxi')), 1000::numeric,
          'shares still add up after an account is deleted');

-- ---------------------------------------------------------------------------
-- Amount and payer edits re-split among the participants frozen at creation
-- ---------------------------------------------------------------------------
select tests.create_user('late');
select tests.create_group_as('alice', 'Cabin', 'INR');
select tests.add_member(tests.gid('Cabin'), 'bob', 'member');
select tests.add_member(tests.gid('Cabin'), 'carol', 'member');
select tests.add_expense('bob', 'Cabin', 'Firewood', 900);
select tests.remove_member(tests.gid('Cabin'), 'carol');
select tests.add_member(tests.gid('Cabin'), 'late', 'member');
select tests.add_expense('alice', 'Cabin', 'Groceries after', 600);
select tests.authenticate_as('bob');
select lives_ok($$ update public.expenses set amount_minor = 1000 where id = tests.eid('Firewood') $$,
                'the payer edits the amount after one member left and another joined');
reset role;
select is((select array_agg(user_id order by user_id) from public.expense_splits where expense_id = tests.eid('Firewood')),
          (select array_agg(id order by id) from tests.users where name in ('alice', 'bob', 'carol')),
          'an amount edit keeps exactly the participants frozen at creation');
select is(tests.share('Firewood', 'carol'), 333::bigint, 'a member who left is re-split with the original participants');
select is(tests.share('Firewood', 'bob'), 334::bigint, 'the payer still takes the leftover unit');
select is(tests.share('Firewood', 'late'), null::bigint, 'a member who joined later is never added by an edit');
select tests.authenticate_as('alice');
select lives_ok($$ update public.expenses set amount_minor = 601 where id = tests.eid('Groceries after') $$,
                'an expense added after a member left is edited');
reset role;
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Groceries after') and user_id = tests.uid('carol')),
          0::bigint, 'a member who left before the expense is never added by an edit');
select is((select sum(share_minor) from public.expense_splits where expense_id = tests.eid('Groceries after')), 601::numeric,
          'the edited amount is fully split');

-- A new payer (privileged writers only): same participants, the leftover unit follows the payer.
update public.expenses set user_id = tests.uid('alice') where id = tests.eid('Firewood');
select is((select array_agg(user_id order by user_id) from public.expense_splits where expense_id = tests.eid('Firewood')),
          (select array_agg(id order by id) from tests.users where name in ('alice', 'bob', 'carol')),
          'a payer change keeps the same participants');
select is(tests.share('Firewood', 'alice'), 334::bigint, 'the new payer takes the leftover unit');
select is(tests.share('Firewood', 'bob'), 333::bigint, 'the previous payer no longer does');

-- An expense without split rows (possible only for legacy data) never draws in the current members.
delete from public.expense_splits where expense_id = tests.eid('Groceries after');
update public.expenses set amount_minor = 700 where id = tests.eid('Groceries after');
select is((select array_agg(user_id::text || ':' || share_minor) from public.expense_splits where expense_id = tests.eid('Groceries after')),
          array[tests.uid('alice')::text || ':700'], 'an expense without split rows is charged to its payer, not to current members');
select is((select sum(net_minor) from public.group_balance_rows(tests.gid('Cabin'))), 0::numeric,
          'balances still sum to zero after the edits');

-- A group expense never becomes personal, nor the other way round.
select throws_ok(format($$ update public.expenses set group_id = null where id = %L $$, tests.eid('Firewood')),
                 '22023', 'expense_group_immutable', 'a group expense cannot become personal');
select tests.add_expense('alice', null, 'Solo', 100);
select throws_ok(format($$ update public.expenses set group_id = %L where id = %L $$, tests.gid('Cabin'), tests.eid('Solo')),
                 '22023', 'expense_group_immutable', 'a personal expense cannot become a group expense');

-- A currency without minor units.
select tests.create_group_as('alice', 'Tokyo', 'JPY');
select tests.add_member(tests.gid('Tokyo'), 'bob', 'member');
select tests.add_member(tests.gid('Tokyo'), 'vic', 'member');
select tests.add_expense('bob', 'Tokyo', 'Ramen', 1000);
select is((select currency::text from public.expenses where id = tests.eid('Ramen')), 'JPY', 'the JPY group expense is in yen');
select is((select array_agg(share_minor order by share_minor desc) from public.expense_splits where expense_id = tests.eid('Ramen')),
          array[334, 333, 333]::bigint[], 'whole yen are split with the payer taking the leftover yen');

-- Personal expenses have no splits.
select tests.add_expense('alice', null, 'Personal lunch', 500);
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Personal lunch')), 0::bigint,
          'personal expenses are not split');

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
select tests.authenticate_as('bob');
select is((select count(*) from public.expense_splits where group_id = tests.gid('Flat')), 10::bigint,
          'members can read the splits of their group');
select throws_ok($$ insert into public.expense_splits (expense_id, slot, group_id, user_id, share_minor)
                    values (tests.eid('Taxi'), 9, tests.gid('Flat'), auth.uid(), 0) $$, '42501', null, 'splits cannot be inserted directly');
select throws_ok($$ update public.expense_splits set share_minor = 0 where expense_id = tests.eid('Taxi') $$, '42501', null,
                 'splits cannot be changed directly');
select throws_ok($$ delete from public.expense_splits where expense_id = tests.eid('Taxi') $$, '42501', null,
                 'splits cannot be deleted directly');
select tests.authenticate_as('pete');
select is((select count(*) from public.expense_splits), 0::bigint, 'pending members cannot read splits');
select tests.authenticate_as('outsider');
select is((select count(*) from public.expense_splits), 0::bigint, 'non-members cannot read splits');
reset role;

delete from public.expenses where id = tests.eid('Taxi');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Taxi')), 0::bigint,
          'deleting an expense removes its splits');

select * from finish();
rollback;
