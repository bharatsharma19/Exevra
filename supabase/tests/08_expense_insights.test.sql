-- Spending insights: personal scope (own expenses plus own share of group expenses, per currency),
-- group scope, day and month buckets in the caller's IANA time zone with zero-filled days, the
-- Asia/Kolkata and America/Los_Angeles midnight boundaries, access checks and parameter validation.
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

-- Series value of one bucket in one currency block.
create or replace function tests.bucket_total(p_insights jsonb, p_currency text, p_bucket text)
returns bigint
language sql
immutable
set search_path = ''
as $$
    select (s->>'total_minor')::bigint
    from jsonb_array_elements(p_insights->'currencies') as c,
         jsonb_array_elements(c->'series') as s
    where c->>'currency' = p_currency and s->>'bucket' = p_bucket
$$;

create or replace function tests.block(p_insights jsonb, p_currency text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
    select c from jsonb_array_elements(p_insights->'currencies') as c where c->>'currency' = p_currency
$$;

grant execute on all functions in schema tests to anon, authenticated;

select plan(44);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('vic');
select tests.create_user('pete');
select tests.create_user('outsider');
select tests.create_group_as('alice', 'Flat', 'INR');
select tests.add_member(tests.gid('Flat'), 'bob', 'member');
select tests.add_member(tests.gid('Flat'), 'vic', 'viewer');
select tests.add_member(tests.gid('Flat'), 'pete', 'viewer', 'pending');
select tests.create_group_as('bob', 'Tokyo', 'JPY');
select tests.add_member(tests.gid('Tokyo'), 'alice', 'member');

-- Personal expenses around midnight in India (UTC+05:30).
select tests.add_expense('alice', null, 'Just after midnight IST', 1000, '2026-03-31T19:00:00Z', 'Food');
select tests.add_expense('alice', null, 'Just before midnight IST', 500, '2026-03-31T18:00:00Z', 'Transport');
select tests.add_expense('alice', null, 'Late evening in LA', 200, '2026-04-01T06:00:00Z', 'Food');
select tests.add_expense('alice', null, 'Trip souvenir', 2000, '2026-03-30T12:00:00Z', 'Shopping', 'USD');
select tests.add_expense('alice', null, 'Long ago', 999, '2025-01-15T12:00:00Z', 'Other');
-- Group expenses: alice's share counts in her personal view.
select tests.add_expense('bob', 'Flat', 'Groceries', 1000, '2026-03-30T10:00:00Z', 'Food');
select tests.add_expense('alice', 'Flat', 'Internet', 3000, '2026-03-29T10:00:00Z', 'Utilities');
select tests.add_expense('bob', 'Tokyo', 'Ramen', 1001, '2026-03-28T10:00:00Z', 'Food');
-- Someone else's personal expense never shows up.
select tests.add_expense('bob', null, 'Bob personal', 7777, '2026-03-31T10:00:00Z', 'Food');

create temporary table r (name text primary key, v jsonb);
grant select, insert on r to authenticated;

select tests.authenticate_as('alice');
insert into r values
    ('week_kolkata', public.get_expense_insights('personal', null, 'week', 'Asia/Kolkata', '2026-04-01T06:30:00Z')),
    ('week_utc', public.get_expense_insights('personal', null, 'week', 'UTC', '2026-04-01T06:30:00Z')),
    ('week_la', public.get_expense_insights('personal', null, 'week', 'America/Los_Angeles', '2026-04-01T06:30:00Z')),
    ('month_kolkata', public.get_expense_insights('personal', null, 'month', 'Asia/Kolkata', '2026-04-01T06:30:00Z')),
    ('year_kolkata', public.get_expense_insights('personal', null, 'year', 'Asia/Kolkata', '2026-04-01T06:30:00Z')),
    ('year_utc', public.get_expense_insights('personal', null, 'year', 'UTC', '2026-04-01T06:30:00Z')),
    ('default_tz', public.get_expense_insights('personal', null, 'week', null, '2026-04-01T06:30:00Z')),
    ('group_week', public.get_expense_insights('group', tests.gid('Flat'), 'week', 'Asia/Kolkata', '2026-04-01T06:30:00Z'));
reset role;

-- Asia/Kolkata midnight boundary
select is(tests.bucket_total((select v from r where name = 'week_kolkata'), 'INR', '2026-04-01'), 1200::bigint,
          'Kolkata: 2026-03-31T19:00Z belongs to 2026-04-01 local (with 06:00Z)');
select is(tests.bucket_total((select v from r where name = 'week_kolkata'), 'INR', '2026-03-31'), 500::bigint,
          'Kolkata: 2026-03-31T18:00Z belongs to 2026-03-31 local');
select is(tests.bucket_total((select v from r where name = 'week_utc'), 'INR', '2026-03-31'), 1500::bigint,
          'UTC: both evening expenses fall on 2026-03-31');
select is(tests.bucket_total((select v from r where name = 'week_utc'), 'INR', '2026-04-01'), 200::bigint,
          'UTC: 06:00Z falls on 2026-04-01');
select is((select v->>'start_date' || '..' || (v->>'end_date') from r where name = 'week_kolkata'), '2026-03-26..2026-04-01',
          'Kolkata: the week is the 7 local days ending today');
select is((select (v->>'range_start')::timestamptz from r where name = 'week_kolkata'), '2026-03-25T18:30:00Z'::timestamptz,
          'Kolkata: the window starts at local midnight');

-- America/Los_Angeles (UTC-07:00 in April 2026)
select is((select v->>'end_date' from r where name = 'week_la'), '2026-03-31', 'LA: today is still 2026-03-31 locally');
select is(tests.bucket_total((select v from r where name = 'week_la'), 'INR', '2026-03-31'), 1700::bigint,
          'LA: 18:00Z, 19:00Z and next-day 06:00Z all fall on 2026-03-31');
select is((select (v->>'range_end')::timestamptz from r where name = 'week_la'), '2026-04-01T07:00:00Z'::timestamptz,
          'LA: the window ends at local midnight');
select is((select (v->>'range_start')::timestamptz from r where name = 'week_la'), '2026-03-25T07:00:00Z'::timestamptz,
          'LA: the window starts at local midnight');

-- Zero-filled day buckets
select is((select jsonb_array_length(tests.block(v, 'INR')->'series') from r where name = 'week_kolkata'), 7,
          'a week has 7 day buckets');
select is((select jsonb_array_length(tests.block(v, 'INR')->'series') from r where name = 'month_kolkata'), 30,
          'a month has 30 day buckets');
select is((select jsonb_array_length(tests.block(v, 'USD')->'series') from r where name = 'week_kolkata'), 7,
          'every currency block is zero-filled');
select is(tests.bucket_total((select v from r where name = 'week_kolkata'), 'INR', '2026-03-27'), 0::bigint,
          'days without expenses are present with zero');
select is((select tests.block(v, 'INR')->'series'->0->>'bucket' from r where name = 'month_kolkata'), '2026-03-03',
          'the month starts 29 days before today');
select is((select v->>'bucket' from r where name = 'month_kolkata'), 'day', 'week and month use day buckets');

-- Month buckets for a year
select is((select jsonb_array_length(tests.block(v, 'INR')->'series') from r where name = 'year_kolkata'), 12,
          'a year has 12 month buckets');
select is((select tests.block(v, 'INR')->'series'->0->>'bucket' from r where name = 'year_kolkata'), '2025-05',
          'the year starts 11 months before the current month');
select is(tests.bucket_total((select v from r where name = 'year_kolkata'), 'INR', '2026-04'), 1200::bigint,
          'Kolkata: the 19:00Z expense on March 31 is counted in April');
select is(tests.bucket_total((select v from r where name = 'year_utc'), 'INR', '2026-04'), 200::bigint,
          'UTC: the same expense is counted in March');
select is((select (tests.block(v, 'INR')->>'total_minor')::bigint from r where name = 'year_kolkata'),
          (select (tests.block(v, 'INR')->>'total_minor')::bigint from r where name = 'year_utc'),
          'the time zone moves expenses between buckets without changing the total');

-- Personal scope: own expenses plus own share of group expenses, per currency
select is((select (tests.block(v, 'INR')->>'total_minor')::bigint from r where name = 'week_kolkata'), 3700::bigint,
          'personal INR total = 1000 + 500 + 200 + share 500 of Groceries + share 1500 of Internet');
select is((select (tests.block(v, 'INR')->>'expense_count')::int from r where name = 'week_kolkata'), 5,
          'group expenses count once in the personal view');
select is((select (tests.block(v, 'USD')->>'total_minor')::bigint from r where name = 'week_kolkata'), 2000::bigint,
          'other currencies are reported separately');
select is((select (tests.block(v, 'JPY')->>'total_minor')::bigint || '/' || (tests.block(v, 'JPY')->>'minor_units')
           from r where name = 'week_kolkata'), '500/0', 'the JPY share is reported in yen with 0 decimals');
select is((select v->'currencies'->0->>'currency' from r where name = 'week_kolkata'), 'INR',
          'the profile currency comes first');
select is((select v->>'primary_currency' from r where name = 'week_kolkata'), 'INR', 'the primary currency is the profile currency');
select is((select tests.block(v, 'INR')->'categories'->0->>'category' || ':' || (tests.block(v, 'INR')->'categories'->0->>'total_minor')
           from r where name = 'week_kolkata'), 'Food:1700', 'categories are totalled and sorted by amount');
select is((select (tests.block(v, 'INR')->'categories'->0->>'percentage')::numeric from r where name = 'week_kolkata'), 45.95,
          'category percentages are relative to the currency total');
select is((select tests.block(v, 'INR')->'highest'->>'title' from r where name = 'week_kolkata'), 'Internet',
          'the highest entry uses the caller''s share');
select is((select tests.block(v, 'INR')->'highest'->>'amount_minor' from r where name = 'week_kolkata'), '1500',
          'the highest entry reports the share, not the full amount');
select is((select tests.block(v, 'INR')->>'average_daily_minor' from r where name = 'week_kolkata'), '529',
          'the daily average is the total over the number of days');
select is((select v->>'timezone' from r where name = 'default_tz'), 'Asia/Kolkata', 'without p_tz the profile time zone is used');

-- Group scope: whole group totals
select is((select (tests.block(v, 'INR')->>'total_minor')::bigint from r where name = 'group_week'), 4000::bigint,
          'group scope totals every group expense');
select is((select jsonb_array_length(v->'currencies') from r where name = 'group_week'), 1, 'group scope uses the group currency only');

select tests.authenticate_as('vic');
select lives_ok($$ select public.get_expense_insights('group', tests.gid('Flat'), 'month', 'Asia/Kolkata') $$,
                'a viewer can read group insights');
select tests.authenticate_as('pete');
select throws_ok($$ select public.get_expense_insights('group', tests.gid('Flat'), 'month', 'Asia/Kolkata') $$,
                 '42501', 'not_group_member', 'a pending member cannot read group insights');
select tests.authenticate_as('outsider');
select throws_ok($$ select public.get_expense_insights('group', tests.gid('Flat'), 'month', 'Asia/Kolkata') $$,
                 '42501', 'not_group_member', 'a non-member cannot read group insights');
select is((select (tests.block(public.get_expense_insights('personal', null, 'year', 'UTC'), 'INR')->>'total_minor')::bigint), 0::bigint,
          'another user''s personal insights contain none of these expenses');

-- Validation
select throws_ok($$ select public.get_expense_insights('personal', null, 'week', 'Mars/Olympus_Mons') $$,
                 '22023', 'invalid_timezone', 'unknown time zones are rejected');
select throws_ok($$ select public.get_expense_insights('everyone', null, 'week', 'UTC') $$,
                 '22023', 'invalid_scope', 'unknown scopes are rejected');
select throws_ok($$ select public.get_expense_insights('personal', null, 'decade', 'UTC') $$,
                 '22023', 'invalid_timeframe', 'unknown timeframes are rejected');
select throws_ok($$ select public.get_expense_insights('group', null, 'week', 'UTC') $$,
                 '22023', 'invalid_group', 'group scope needs a group');
reset role;

select is((select prosecdef from pg_proc where oid = 'public.get_expense_insights(text, uuid, text, text, timestamptz)'::regprocedure),
          false, 'insights run with the caller''s privileges');

select * from finish();
rollback;
