-- Expenses: integer minor-unit amounts with a currency, server-generated id and timestamps, field
-- limits, the group currency rule, who may read, add, edit and delete, and payer account removal.
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

grant execute on all functions in schema tests to anon, authenticated;

select plan(76);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('vic');
select tests.create_user('pete');
select tests.create_user('outsider');
select tests.create_group_as('alice', 'Flat', 'INR');
select tests.create_group_as('outsider', 'Elsewhere', 'EUR');
select tests.add_member(tests.gid('Flat'), 'bob', 'member');
select tests.add_member(tests.gid('Flat'), 'vic', 'viewer');
select tests.add_member(tests.gid('Flat'), 'pete', 'viewer', 'pending');

-- ---------------------------------------------------------------------------
-- Currency helper
-- ---------------------------------------------------------------------------
select is(public.currency_minor_units('JPY'), 0, 'JPY has no minor units');
select is(public.currency_minor_units('KRW'), 0, 'KRW has no minor units');
select is(public.currency_minor_units('IDR'), 2, 'IDR has two minor units (ISO 4217)');
select is(public.currency_minor_units('INR'), 2, 'INR has two minor units');
select is(public.currency_minor_units('XYZ'), null, 'unsupported currencies have no exponent');

-- ---------------------------------------------------------------------------
-- Server-controlled fields on insert
-- ---------------------------------------------------------------------------
select tests.authenticate_as('alice');
select throws_ok($$ insert into public.expenses (id, user_id, title, amount_minor, category)
                    values ('00000000-0000-0000-0000-0000000000aa', tests.uid('alice'), 'Chosen id', 100, 'Food') $$,
                 '42501', null, 'clients cannot choose an expense id');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, created_at)
                    values (tests.uid('alice'), 'Backdated', 100, 'Food', '2000-01-01') $$,
                 '42501', null, 'clients cannot set created_at');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at, note)
                   values (tests.uid('alice'), '  Lunch  ', 12345, 'food', '2026-03-01T10:00:00Z', '   ') $$,
                'a personal expense can be added');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, currency, category)
                   values (tests.uid('alice'), 'Souvenir', 2500, 'usd', 'Shopping') $$,
                'a personal expense may use any supported currency');
reset role;

select is((select title from public.expenses where user_id = tests.uid('alice') and amount_minor = 12345), 'Lunch',
          'the title is trimmed');
select is((select category from public.expenses where title = 'Lunch'), 'Food', 'the category is normalised to the app list');
select is((select note from public.expenses where title = 'Lunch'), null, 'a blank note is stored as NULL');
select is((select currency::text from public.expenses where title = 'Lunch'), 'INR',
          'a personal expense without a currency uses the profile currency');
select is((select currency::text from public.expenses where title = 'Souvenir'), 'USD', 'the currency is upper-cased');
select is((select spent_at from public.expenses where title = 'Lunch'), '2026-03-01T10:00:00Z'::timestamptz,
          'spent_at keeps the chosen instant');
select is((select created_at = now() and updated_at = now() from public.expenses where title = 'Lunch'), true,
          'created_at and updated_at are server-set');

-- Even a privileged writer cannot choose the id or timestamps.
insert into public.expenses (id, user_id, title, amount_minor, category, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000000bb', tests.uid('alice'), 'Service row', 100, 'Other', '2000-01-01', '2000-01-01');
select is((select count(*) from public.expenses where id = '00000000-0000-0000-0000-0000000000bb'), 0::bigint,
          'a supplied id is replaced by a server-generated one');
select is((select created_at = now() from public.expenses where title = 'Service row'), true,
          'a supplied created_at is replaced by the server time');
update public.expenses set created_at = '2000-01-01', id = gen_random_uuid() where title = 'Service row';
select is((select created_at = now() from public.expenses where title = 'Service row'), true,
          'created_at cannot be changed by an update');
select is((select count(*) from public.expenses where title = 'Service row' and id = '00000000-0000-0000-0000-0000000000bb'), 0::bigint,
          'the id cannot be changed by an update');

-- ---------------------------------------------------------------------------
-- Field limits (title, note, category, amount, currency)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('alice');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (auth.uid(), repeat('x', 1000), 1, 'Food') $$, '23514', null, 'titles longer than 120 characters are rejected');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                   values (auth.uid(), repeat('x', 120), 1, 'Food') $$, 'a 120-character title is accepted');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (auth.uid(), '   ', 1, 'Food') $$, '23514', null, 'a blank title is rejected');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, note)
                    values (auth.uid(), 't', 1, 'Food', repeat('n', 5000)) $$, '23514', null, 'notes longer than 500 characters are rejected');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (auth.uid(), 't', 1, repeat('c', 200)) $$, '23514', null, 'categories outside the app list are rejected');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (auth.uid(), 't', 0, 'Food') $$, '23514', null, 'a zero amount is rejected');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (auth.uid(), 't', -5, 'Food') $$, '23514', null, 'a negative amount is rejected');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (auth.uid(), 't', 100000000001, 'Food') $$, '23514', null, 'amounts above the maximum are rejected');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                   values (auth.uid(), 'Max', 100000000000, 'Food') $$, 'the maximum amount is accepted');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, currency)
                    values (auth.uid(), 't', 1, 'Food', 'XYZ') $$, '23514', null, 'unsupported currencies are rejected');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, receipt_url)
                    values (auth.uid(), 't', 1, 'Food', 'http://example.test/r.png') $$, '23514', null, 'receipt URLs must be https');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                    values (tests.uid('bob'), 'For someone else', 1, 'Food') $$, '42501', null,
                 'an expense cannot be added in another user''s name');

-- ---------------------------------------------------------------------------
-- spent_at range: finite, not before 2000-01-01 in any time zone, at most a year ahead
-- ---------------------------------------------------------------------------
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at)
                    values (auth.uid(), 't', 1, 'Food', 'infinity') $$, '22023', 'invalid_date', 'spent_at cannot be infinity');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at)
                    values (auth.uid(), 't', 1, 'Food', '-infinity') $$, '22023', 'invalid_date', 'spent_at cannot be -infinity');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at)
                    values (auth.uid(), 't', 1, 'Food', '1999-12-31T09:59:59Z') $$, '22023', 'invalid_date',
                 'spent_at before 2000-01-01 is rejected');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at)
                   values (auth.uid(), 'Millennium', 1, 'Food', '2000-01-01T00:00:00+14') $$,
                'local midnight of 2000-01-01 is accepted in every time zone');
select throws_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at)
                    values (auth.uid(), 't', 1, 'Food', now() + interval '1 year 1 day') $$, '22023', 'invalid_date',
                 'spent_at more than a year ahead is rejected');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, category, spent_at)
                   values (auth.uid(), 'Planned', 1, 'Food', now() + interval '364 days') $$, 'a date within the next year is accepted');
select throws_ok($$ update public.expenses set spent_at = 'infinity' where title = 'Planned' $$, '22023', 'invalid_date',
                 'an update cannot move spent_at to infinity');
select throws_ok($$ update public.expenses set spent_at = '1990-01-01T00:00:00Z' where title = 'Planned' $$, '22023', 'invalid_date',
                 'an update cannot move spent_at before 2000');
-- A legacy row outside the range stays editable as long as its date is not changed.
reset role;
alter table public.expenses disable trigger trigger_expenses_before_write;
insert into public.expenses (id, user_id, title, amount_minor, currency, category, spent_at)
values (gen_random_uuid(), tests.uid('alice'), 'Legacy 1995', 100, 'INR', 'Other', '1995-06-01T00:00:00Z');
select throws_ok($$ insert into public.expenses (id, user_id, title, amount_minor, currency, category, spent_at)
                    values (gen_random_uuid(), tests.uid('alice'), 'Unbounded', 100, 'INR', 'Other', 'infinity') $$,
                 '23514', null, 'a CHECK keeps infinite dates out even when the trigger is bypassed');
alter table public.expenses enable trigger trigger_expenses_before_write;
select tests.authenticate_as('alice');
select lives_ok($$ update public.expenses set title = 'Legacy 1995 edited', spent_at = spent_at where title = 'Legacy 1995' $$,
                'a legacy expense dated before 2000 can still be edited when its date is unchanged');

-- ---------------------------------------------------------------------------
-- Group expenses and the group currency
-- ---------------------------------------------------------------------------
select lives_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                   values (auth.uid(), tests.gid('Flat'), 'Rent', 3000000, 'Housing') $$,
                'the admin can add a group expense');
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category, currency)
                    values (auth.uid(), tests.gid('Flat'), 'Wrong currency', 100, 'Food', 'USD') $$,
                 '22023', 'currency_mismatch', 'a group expense in another currency is rejected');
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                    values (auth.uid(), tests.gid('Elsewhere'), 'Not my group', 100, 'Food') $$,
                 '42501', null, 'expenses cannot be added to a group the caller does not belong to');
select throws_ok($$ update public.expenses set currency = 'USD' where title = 'Rent' $$,
                 '22023', 'currency_mismatch', 'a group expense cannot be moved to another currency');
reset role;
select is((select currency::text from public.expenses where title = 'Rent'), 'INR',
          'a group expense without a currency takes the group currency');

select tests.authenticate_as('bob');
select lives_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                   values (auth.uid(), tests.gid('Flat'), 'Groceries', 4000, 'Food') $$, 'a member can add a group expense');
select lives_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                   values (auth.uid(), tests.gid('Flat'), 'Snacks', 900, 'Food') $$, 'a member can add another group expense');
select lives_ok($$ insert into public.expenses (user_id, title, amount_minor, category)
                   values (auth.uid(), 'Bob personal', 700, 'Personal') $$, 'a member can add a personal expense');
select is((select count(*) from public.expenses where title in ('Lunch', 'Souvenir')), 0::bigint,
          'personal expenses of other users are not visible');
select is((select count(*) from public.expenses where group_id = tests.gid('Flat')), 3::bigint,
          'a member sees every expense of the group');
-- Edits by a non-payer change nothing.
update public.expenses set title = 'Changed by bob' where title = 'Rent';
delete from public.expenses where title = 'Rent';
reset role;
select is((select count(*) from public.expenses where title = 'Rent'), 1::bigint,
          'a member cannot edit or delete an expense paid by someone else');

select tests.authenticate_as('bob');
select lives_ok($$ update public.expenses set title = 'Weekly groceries', amount_minor = 4200 where title = 'Groceries' $$,
                'the payer can edit their group expense');
select throws_ok($$ update public.expenses set user_id = tests.uid('alice') where title = 'Weekly groceries' $$,
                 '42501', null, 'the payer cannot be changed');
select throws_ok($$ update public.expenses set group_id = null where title = 'Weekly groceries' $$,
                 '42501', null, 'the group cannot be changed');
select throws_ok($$ update public.expenses set created_at = '2000-01-01' where title = 'Weekly groceries' $$,
                 '42501', null, 'created_at cannot be updated by clients');
select lives_ok($$ delete from public.expenses where title = 'Snacks' $$, 'the payer can delete their group expense');
reset role;
select is((select count(*) from public.expenses where title = 'Snacks'), 0::bigint, 'the payer''s delete removed the row');

select throws_ok($$ update public.expenses set group_id = null where title = 'Rent' $$, '22023', 'expense_group_immutable',
                 'group_id is immutable even for privileged writers');

-- Viewers and pending members
select tests.authenticate_as('vic');
select is((select count(*) from public.expenses where group_id = tests.gid('Flat')), 2::bigint, 'a viewer can read group expenses');
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                    values (auth.uid(), tests.gid('Flat'), 'Viewer spend', 100, 'Food') $$,
                 '42501', null, 'a viewer cannot add group expenses');
select tests.authenticate_as('pete');
select is((select count(*) from public.expenses where group_id = tests.gid('Flat')), 0::bigint,
          'a pending member cannot read group expenses');
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category)
                    values (auth.uid(), tests.gid('Flat'), 'Pending spend', 100, 'Food') $$,
                 '42501', null, 'a pending member cannot add group expenses');
select tests.authenticate_as('outsider');
select is((select count(*) from public.expenses where group_id = tests.gid('Flat') or user_id = tests.uid('alice')), 0::bigint,
          'a non-member sees no expenses of the group or its members');

-- The admin may delete any group expense.
select tests.authenticate_as('alice');
select lives_ok($$ delete from public.expenses where title = 'Weekly groceries' $$, 'the admin can delete a member''s group expense');
reset role;
select is((select count(*) from public.expenses where title = 'Weekly groceries'), 0::bigint, 'the admin''s delete removed the row');

-- ---------------------------------------------------------------------------
-- Payer account deleted: group expenses kept as "Former member", personal expenses removed
-- ---------------------------------------------------------------------------
select tests.add_expense('bob', 'Flat', 'Bob paid', 600);
delete from auth.users where id = tests.uid('bob');
select is((select user_id from public.expenses where id = tests.eid('Bob paid')), null,
          'a deleted payer''s group expense is kept with no payer');
select is((select count(*) from public.expenses where title = 'Bob personal'), 0::bigint,
          'a deleted user''s personal expenses are removed');

-- ---------------------------------------------------------------------------
-- Schema hygiene
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'expenses'),
          'expenses are published for realtime');
select ok(not (has_table_privilege('anon', 'public.expenses', 'select') or has_table_privilege('anon', 'public.expenses', 'insert')
               or has_table_privilege('anon', 'public.expenses', 'update') or has_table_privilege('anon', 'public.expenses', 'delete')),
          'anon has no privileges on expenses');
select has_index('public', 'expenses', 'idx_expenses_group_spent', array['group_id', 'spent_at', 'id'],
                 'group feed keyset index exists');
select has_index('public', 'expenses', 'idx_expenses_user_spent', array['user_id', 'spent_at', 'id'],
                 'user feed keyset index exists');
select is((select count(*) from pg_policies where schemaname = 'public' and tablename = 'expenses'
           and (not ('authenticated' = any (roles)) or array_length(roles, 1) <> 1)), 0::bigint,
          'every expenses policy applies to authenticated only');
select is((select count(*) from pg_policies where schemaname = 'public' and tablename = 'expenses' and cmd = 'UPDATE'
           and (qual is null or with_check is null)), 0::bigint,
          'the expenses UPDATE policy has USING and WITH CHECK');
select is(public.expense_categories(),
          array['Food', 'Transport', 'Housing', 'Entertainment', 'Healthcare', 'Utilities', 'Shopping', 'Personal', 'Education', 'Other'],
          'the category list matches the app');

select * from finish();
rollback;
