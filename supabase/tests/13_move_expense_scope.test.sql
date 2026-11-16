-- move_expense_scope(p_expense_id, p_group_id): atomic move of an expense between personal and group
-- scope or between groups. Only the payer may move; the target group must accept the caller's
-- expenses (approved admin or member) and use the expense currency; a group expense shared with a
-- departed member stays where it is (P0001 expense_locked_member_left). The new row gets a server id
-- and its splits come from the normal trigger.
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

create table tests.moved (name text primary key, row public.expenses);
grant all on tests.moved to authenticated;

select plan(42);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_user('vic');
select tests.create_user('pete');
select tests.create_user('outsider');
select tests.create_group_as('alice', 'Flat', 'INR');
select tests.add_member(tests.gid('Flat'), 'bob', 'member');
select tests.add_member(tests.gid('Flat'), 'carol', 'member');
select tests.add_member(tests.gid('Flat'), 'vic', 'viewer');
select tests.add_member(tests.gid('Flat'), 'pete', 'viewer', 'pending');
select tests.create_group_as('bob', 'Trip', 'INR');
select tests.add_member(tests.gid('Trip'), 'alice', 'member');
select tests.create_group_as('alice', 'Euro', 'EUR');
select tests.create_group_as('carol', 'Watch', 'INR');
select tests.add_member(tests.gid('Watch'), 'alice', 'viewer');
select tests.create_group_as('carol', 'Queue', 'INR');
select tests.add_member(tests.gid('Queue'), 'alice', 'viewer', 'pending');

update public.profiles set currency = 'INR' where id = tests.uid('alice');
select tests.add_expense('alice', null, 'Lunch', 900, '2026-03-01T12:00:00Z', 'Food');
update public.expenses set note = 'with the team', receipt_url = 'https://example.test/r.png' where id = tests.eid('Lunch');

-- ===========================================================================
-- Personal -> group
-- ===========================================================================
select tests.authenticate_as('alice');
insert into tests.moved select 'lunch_flat', public.move_expense_scope(tests.eid('Lunch'), tests.gid('Flat'));
reset role;
select is((select (row).group_id from tests.moved where name = 'lunch_flat'), tests.gid('Flat'), 'the expense now belongs to the group');
select isnt((select (row).id from tests.moved where name = 'lunch_flat'), tests.eid('Lunch'), 'the moved expense has a new server id');
select is((select count(*) from public.expenses where id = tests.eid('Lunch')), 0::bigint, 'the personal row is gone');
select is((select e.title || '|' || e.category || '|' || e.note || '|' || e.amount_minor || '|' || e.currency || '|' || e.spent_at
                  || '|' || e.receipt_url || '|' || e.user_id
           from public.expenses as e where e.id = (select (row).id from tests.moved where name = 'lunch_flat')),
          'Lunch|Food|with the team|900|INR|' || '2026-03-01T12:00:00Z'::timestamptz || '|https://example.test/r.png|' || tests.uid('alice'),
          'title, category, note, amount, currency, date, receipt and payer are kept');
select is((select array_agg(s.user_id::text || ':' || s.share_minor order by s.user_id)
           from public.expense_splits as s where s.expense_id = (select (row).id from tests.moved where name = 'lunch_flat')),
          (select array_agg(u.id::text || ':300' order by u.id) from tests.users as u where u.name in ('alice', 'bob', 'carol')),
          'the group expense is split among the current admins and members (no viewers, no pending)');
select is(tests.net('Flat', 'bob'), -300::bigint, 'the group balances include the moved expense');

-- ===========================================================================
-- Group -> other group
-- ===========================================================================
select tests.authenticate_as('alice');
insert into tests.moved select 'lunch_trip', public.move_expense_scope((select (row).id from tests.moved where name = 'lunch_flat'), tests.gid('Trip'));
reset role;
select is((select (row).group_id from tests.moved where name = 'lunch_trip'), tests.gid('Trip'), 'the expense moved to the other group');
select is((select count(*) from public.expenses where id = (select (row).id from tests.moved where name = 'lunch_flat')), 0::bigint,
          'it left the first group');
select is((select count(*) from public.expense_splits where expense_id = (select (row).id from tests.moved where name = 'lunch_flat')), 0::bigint,
          'its old splits are gone');
select is((select array_agg(s.user_id::text || ':' || s.share_minor order by s.user_id)
           from public.expense_splits as s where s.expense_id = (select (row).id from tests.moved where name = 'lunch_trip')),
          (select array_agg(u.id::text || ':450' order by u.id) from tests.users as u where u.name in ('alice', 'bob')),
          'it is split among the members of the new group');
select is(tests.net('Flat', 'bob'), 0::bigint, 'the first group''s balances no longer include it');
select is((select sum(net_minor) from public.group_balance_rows(tests.gid('Trip'))), 0::numeric, 'the new group''s balances sum to zero');

-- ===========================================================================
-- Group -> personal
-- ===========================================================================
select tests.authenticate_as('alice');
insert into tests.moved select 'lunch_back', public.move_expense_scope((select (row).id from tests.moved where name = 'lunch_trip'), null);
reset role;
select is((select (row).group_id from tests.moved where name = 'lunch_back'), null::uuid, 'the expense is personal again');
select is((select e.title || '|' || e.amount_minor || '|' || e.currency || '|' || e.note || '|' || e.user_id from public.expenses as e
           where e.id = (select (row).id from tests.moved where name = 'lunch_back')),
          'Lunch|900|INR|with the team|' || tests.uid('alice'), 'the personal expense keeps its fields');
select is((select count(*) from public.expense_splits where expense_id = (select (row).id from tests.moved where name = 'lunch_back')),
          0::bigint, 'a personal expense has no splits');
select is((select count(*) from public.group_balance_rows(tests.gid('Trip')) where net_minor <> 0), 0::bigint,
          'the group balances are back to zero');
select tests.authenticate_as('bob');
select is((select count(*) from public.expenses where id = (select (row).id from tests.moved where name = 'lunch_back')), 0::bigint,
          'the former group members no longer see it');
reset role;

-- A group expense in another currency can still become personal.
select tests.add_expense('alice', 'Euro', 'Croissant', 450);
select tests.authenticate_as('alice');
select is((public.move_expense_scope(tests.eid('Croissant'), null)).currency::text, 'EUR',
          'a group expense keeps its currency when it becomes personal');
reset role;

-- ===========================================================================
-- Currency, target and permission checks
-- ===========================================================================
select tests.add_expense('alice', null, 'Museum', 2000, now(), 'Entertainment', 'EUR');
select tests.add_expense('bob', 'Flat', 'Bob taxi', 300);
select tests.add_expense('alice', 'Flat', 'Alice taxi', 300);
select tests.authenticate_as('alice');
select throws_ok($$ select public.move_expense_scope(tests.eid('Museum'), tests.gid('Flat')) $$,
                 '22023', 'currency_mismatch', 'the expense currency must equal the target group currency');
select is((select count(*) from public.expenses where id = tests.eid('Museum')), 1::bigint, 'a refused move leaves the expense in place');
select is((public.move_expense_scope(tests.eid('Museum'), tests.gid('Euro'))).group_id, tests.gid('Euro'),
          'a matching currency moves');
select throws_ok($$ select public.move_expense_scope(tests.eid('Alice taxi'), tests.gid('Flat')) $$,
                 '22023', 'invalid_target', 'moving to the group it is already in is refused');
select throws_ok(format($$ select public.move_expense_scope(%L, null) $$, (select (row).id from tests.moved where name = 'lunch_back')),
                 '22023', 'invalid_target', 'a personal expense is already personal');
select throws_ok($$ select public.move_expense_scope(tests.eid('Alice taxi'), tests.gid('Watch')) $$,
                 '42501', 'not_group_member', 'a viewer cannot move an expense into the group');
select throws_ok($$ select public.move_expense_scope(tests.eid('Alice taxi'), tests.gid('Queue')) $$,
                 '42501', 'not_group_member', 'a pending member cannot move an expense into the group');
select throws_ok(format($$ select public.move_expense_scope(tests.eid('Alice taxi'), %L) $$, gen_random_uuid()),
                 'P0002', 'group_not_found', 'an unknown target group is refused');
select throws_ok($$ select public.move_expense_scope(tests.eid('Bob taxi'), null) $$,
                 '42501', 'not_expense_payer', 'only the payer can move a group expense, even the admin cannot');
select throws_ok(format($$ select public.move_expense_scope(%L, null) $$, gen_random_uuid()),
                 'P0002', 'expense_not_found', 'an unknown expense is refused');
select throws_ok($$ select public.move_expense_scope(null, null) $$,
                 'P0002', 'expense_not_found', 'a missing expense id is refused');
select tests.authenticate_as('bob');
select throws_ok(format($$ select public.move_expense_scope(%L, tests.gid('Trip')) $$, (select (row).id from tests.moved where name = 'lunch_back')),
                 'P0002', 'expense_not_found', 'another user''s personal expense is not visible');
select tests.authenticate_as('outsider');
select throws_ok($$ select public.move_expense_scope(tests.eid('Bob taxi'), null) $$,
                 'P0002', 'expense_not_found', 'a group expense of a group the caller is not in is not visible');
reset role;

-- A payer demoted to viewer can no longer move the expense out of the group.
select tests.add_member(tests.gid('Flat'), 'outsider', 'member');
select tests.add_expense('outsider', 'Flat', 'Outsider pizza', 400);
select tests.authenticate_as('alice');
select public.set_member_role(tests.gid('Flat'), tests.uid('outsider'), 'viewer');
select tests.authenticate_as('outsider');
select throws_ok($$ select public.move_expense_scope(tests.eid('Outsider pizza'), null) $$,
                 '42501', 'not_group_member', 'a payer who is now a viewer cannot move the expense');
reset role;

-- ===========================================================================
-- Locked: a participant left the group
-- ===========================================================================
select tests.add_expense('alice', 'Flat', 'Groceries', 900);
select tests.remove_member(tests.gid('Flat'), 'carol');
select tests.authenticate_as('alice');
select throws_ok($$ select public.move_expense_scope(tests.eid('Groceries'), null) $$,
                 'P0001', 'expense_locked_member_left', 'a locked group expense cannot become personal');
select throws_ok($$ select public.move_expense_scope(tests.eid('Groceries'), tests.gid('Trip')) $$,
                 'P0001', 'expense_locked_member_left', 'nor move to another group');
reset role;
select is((select group_id from public.expenses where id = tests.eid('Groceries')), tests.gid('Flat'), 'the locked expense stays put');
select is(tests.share('Groceries', 'carol'), 300::bigint, 'the departed member''s share is unchanged');

-- ===========================================================================
-- Privileges and the immutability rule for direct writes
-- ===========================================================================
select ok(has_function_privilege('authenticated', 'public.move_expense_scope(uuid, uuid)', 'execute'), 'authenticated can call it');
select ok(not has_function_privilege('anon', 'public.move_expense_scope(uuid, uuid)', 'execute'), 'anon cannot');
select ok(not has_function_privilege('service_role', 'public.move_expense_scope(uuid, uuid)', 'execute'),
          'it is granted to authenticated only');
select is((select prosecdef from pg_proc where oid = 'public.move_expense_scope(uuid, uuid)'::regprocedure), true,
          'it runs as definer (one transaction across the RLS-protected rows)');
select is((select pg_get_function_result(oid) from pg_proc where oid = 'public.move_expense_scope(uuid, uuid)'::regprocedure),
          'expenses', 'it returns the resulting expense row');
select throws_ok($$ update public.expenses set group_id = null where id = tests.eid('Alice taxi') $$,
                 '22023', 'expense_group_immutable', 'a direct group_id change is still refused');

select * from finish();
rollback;
