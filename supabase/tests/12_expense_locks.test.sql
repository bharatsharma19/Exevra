-- Group expenses charged to people who are no longer approved members are locked: their amount and
-- payer cannot change and they cannot be deleted (P0001 expense_locked_member_left), because either
-- would change a departed member's balance. Text, category and date edits stay allowed; deleting the
-- whole group still removes them. Members who were only demoted, and expenses among current members,
-- are not affected.
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

select plan(42);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_user('dan');
select tests.create_user('erin');

-- ===========================================================================
-- The reported scenario: alice pays 1000 split with bob; bob settles 500 and leaves.
-- ===========================================================================
select tests.create_group_as('alice', 'Trip', 'INR');
select tests.add_member(tests.gid('Trip'), 'bob', 'member');
select tests.add_expense('alice', 'Trip', 'E1', 1000);
select is(tests.net('Trip', 'bob'), -500::bigint, 'bob owes half of E1');
select tests.settle('s1', 'bob', 'Trip', 'alice', 500);
select tests.authenticate_as('alice');
select public.confirm_settlement(tests.sid('s1'));
select tests.authenticate_as('bob');
select is((public.leave_group(tests.gid('Trip')))->>'left', 'true', 'a settled member can still leave');
reset role;
select is(tests.net('Trip', 'bob'), 0::bigint, 'bob left with a zero balance');
select is(tests.net('Trip', 'alice'), 0::bigint, 'alice is settled too');

select tests.authenticate_as('alice');
select throws_ok($$ update public.expenses set amount_minor = 2000 where id = tests.eid('E1') $$,
                 'P0001', 'expense_locked_member_left', 'the amount of an expense shared with a departed member is locked');
select throws_ok($$ update public.expenses set amount_minor = 500 where id = tests.eid('E1') $$,
                 'P0001', 'expense_locked_member_left', 'lowering it is refused as well');
select throws_ok($$ delete from public.expenses where id = tests.eid('E1') $$,
                 'P0001', 'expense_locked_member_left', 'the expense cannot be deleted by its payer, who is also the admin');
select lives_ok($$ update public.expenses set title = 'E1 renamed', category = 'Transport', note = 'kept',
                       spent_at = now() - interval '1 day' where id = tests.eid('E1') $$,
                'title, category, note and date edits stay allowed');
select lives_ok($$ update public.expenses set amount_minor = amount_minor where id = tests.eid('E1') $$,
                'writing the same amount back is not a change');
reset role;
select is((select title || '/' || category || '/' || amount_minor from public.expenses where id = tests.eid('E1')),
          'E1 renamed/Transport/1000', 'the allowed edits were applied and the amount is unchanged');
select is(tests.share('E1', 'bob'), 500::bigint, 'bob''s share is unchanged');
select is(tests.net('Trip', 'bob'), 0::bigint, 'bob''s balance is unchanged');
select is(tests.net('Trip', 'alice'), 0::bigint, 'alice''s balance is unchanged');

-- Privileged writers are held to the same rule.
select throws_ok($$ update public.expenses set amount_minor = 2000 where id = tests.eid('E1') $$,
                 'P0001', 'expense_locked_member_left', 'the table owner cannot change the amount either');
select throws_ok($$ update public.expenses set user_id = tests.uid('carol') where id = tests.eid('E1') $$,
                 'P0001', 'expense_locked_member_left', 'nor the payer');
select set_config('tests.e1', tests.eid('E1')::text, true);
set local role service_role;
select throws_ok($$ delete from public.expenses where id = current_setting('tests.e1')::uuid $$,
                 'P0001', 'expense_locked_member_left', 'the service role cannot delete it');
reset role;
select is((select count(*) from public.expenses where id = tests.eid('E1')), 1::bigint, 'E1 still exists');

-- An expense among current members only stays fully editable.
select tests.add_member(tests.gid('Trip'), 'carol', 'member');
select tests.add_expense('alice', 'Trip', 'E2', 600);
select tests.authenticate_as('alice');
select lives_ok($$ update public.expenses set amount_minor = 800 where id = tests.eid('E2') $$,
                'an expense among current members can change its amount');
reset role;
select is(tests.share('E2', 'carol'), 400::bigint, 'and is re-split as before');
select tests.authenticate_as('carol');
select is((select count(*) from public.expenses where group_id = tests.gid('Trip')), 2::bigint, 'carol sees both expenses');
reset role;
select tests.authenticate_as('alice');
select lives_ok($$ delete from public.expenses where id = tests.eid('E2') $$, 'and can be deleted');
reset role;
select is((select sum(net_minor) from public.group_balance_rows(tests.gid('Trip'))), 0::numeric,
          'the remaining members'' balances still sum to zero');
select is((select count(*) from public.group_balance_rows(tests.gid('Trip')) where net_minor <> 0), 0::bigint,
          'and everybody is still settled');

-- A member who leaves later locks the expenses they share, also when the payer is the one leaving.
select tests.add_expense('carol', 'Trip', 'E3', 300);
select tests.settle('s2', 'alice', 'Trip', 'carol', 150);
select tests.authenticate_as('carol');
select public.confirm_settlement(tests.sid('s2'));
select is((public.leave_group(tests.gid('Trip')))->>'left', 'true', 'the payer of E3 settles and leaves');
reset role;
select is((select user_id from public.expenses where id = tests.eid('E3')), tests.uid('carol'), 'the departed payer stays the payer');
select tests.authenticate_as('alice');
select throws_ok($$ delete from public.expenses where id = tests.eid('E3') $$,
                 'P0001', 'expense_locked_member_left', 'the admin cannot delete an expense paid by a departed member');
reset role;

-- ===========================================================================
-- A demoted member (viewer) is still an approved member: nothing is locked.
-- ===========================================================================
select tests.create_group_as('alice', 'Flat', 'INR');
select tests.add_member(tests.gid('Flat'), 'dan', 'member');
select tests.add_expense('alice', 'Flat', 'Rent', 1000);
select tests.authenticate_as('alice');
select public.set_member_role(tests.gid('Flat'), tests.uid('dan'), 'viewer');
select lives_ok($$ update public.expenses set amount_minor = 1200 where id = tests.eid('Rent') $$,
                'a participant who became a viewer does not lock the expense');
reset role;
select is(tests.share('Rent', 'dan'), 600::bigint, 'the viewer keeps their re-split share');

-- ===========================================================================
-- Anonymised users (account deleted, user_id NULL) count as departed.
-- ===========================================================================
select tests.create_group_as('erin', 'Loft', 'INR');
select tests.add_member(tests.gid('Loft'), 'dan', 'member');
select tests.add_member(tests.gid('Loft'), 'carol', 'member');
select tests.add_expense('carol', 'Loft', 'Paint', 300);
select tests.add_expense('dan', 'Loft', 'Brushes', 90);
select tests.add_expense('erin', 'Loft', 'Snacks', 30);
delete from auth.users where id = tests.uid('dan');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Paint') and user_id is null), 1::bigint,
          'the deleted account''s share is kept without a user');
select tests.authenticate_as('carol');
select throws_ok($$ update public.expenses set amount_minor = 600 where id = tests.eid('Paint') $$,
                 'P0001', 'expense_locked_member_left', 'a former member''s share locks the amount');
select throws_ok($$ delete from public.expenses where id = tests.eid('Paint') $$,
                 'P0001', 'expense_locked_member_left', 'and the deletion');
select lives_ok($$ update public.expenses set title = 'Wall paint' where id = tests.eid('Paint') $$, 'a rename is still fine');
select tests.authenticate_as('erin');
select throws_ok($$ delete from public.expenses where id = tests.eid('Brushes') $$,
                 'P0001', 'expense_locked_member_left', 'an expense paid by a former member cannot be deleted by the admin');
reset role;
select throws_ok($$ update public.expenses set amount_minor = 60 where id = tests.eid('Brushes') $$,
                 'P0001', 'expense_locked_member_left', 'nor re-priced by a privileged writer');
select is((select sum(net_minor) from public.group_balance_rows(tests.gid('Loft'))), 0::numeric,
          'balances still sum to zero');

-- Legacy expense without split rows: the payer alone is the participant.
select tests.create_group_as('erin', 'Shed', 'INR');
select tests.add_member(tests.gid('Shed'), 'carol', 'member');
select tests.add_expense('carol', 'Shed', 'Old tools', 100);
delete from public.expense_splits where expense_id = tests.eid('Old tools');
select tests.remove_member(tests.gid('Shed'), 'carol');
select throws_ok($$ update public.expenses set amount_minor = 200 where id = tests.eid('Old tools') $$,
                 'P0001', 'expense_locked_member_left', 'a departed payer locks an expense without split rows');

-- ===========================================================================
-- Deleting the whole group still removes locked expenses.
-- ===========================================================================
select tests.authenticate_as('alice');
select is((public.delete_group(tests.gid('Trip')))->>'deleted', 'true', 'the admin deletes a group with locked expenses');
reset role;
select is((select count(*) from public.expenses where id in (tests.eid('E1'), tests.eid('E3'))), 0::bigint,
          'the locked expenses went with the group');
select tests.authenticate_as('erin');
select is((public.leave_group(tests.gid('Shed')))->>'group_deleted', 'true',
          'the last member leaving deletes a group with a locked expense');
reset role;
select is((select count(*) from public.expenses where id = tests.eid('Old tools')), 0::bigint, 'and the expense with it');

-- Account deletion of the last member deletes their group with its locked expenses.
select tests.create_user('fay');
select tests.create_group_as('fay', 'Den', 'INR');
select tests.add_member(tests.gid('Den'), 'carol', 'member');
select tests.add_expense('fay', 'Den', 'Lamp', 200);
select tests.remove_member(tests.gid('Den'), 'carol');
select lives_ok($$ delete from auth.users where id = tests.uid('fay') $$, 'the last member''s account is deleted');
select is((select count(*) from public.expenses where id = tests.eid('Lamp')), 0::bigint,
          'the group and its locked expense are gone');

select * from finish();
rollback;
