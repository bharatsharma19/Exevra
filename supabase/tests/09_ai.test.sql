-- AI assistant support: the spending context holds only the caller's own share and only their
-- groups, in their time zone; the request quota (daily and per minute) and usage completion; and
-- AI answer reports (insert own, read own, never changed).
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

select plan(87);

select tests.create_user('ann');
select tests.create_user('ben');
select tests.create_user('cat');
select tests.create_user('dan');
update public.profiles set ai_consent = true where id in (tests.uid('ann'), tests.uid('ben'), tests.uid('dan'));

select tests.create_group_as('ann', 'Trip', 'INR');
select tests.add_member(tests.gid('Trip'), 'ben');
select tests.create_group_as('ben', 'Band', 'INR');
select tests.add_member(tests.gid('Band'), 'cat');

select tests.add_expense('ann', null, 'Groceries', 30000, '2026-03-31T19:00:00Z', 'Food', 'INR');
select tests.add_expense('ann', null, 'Taxi', 5000, '2026-04-10T10:00:00Z', 'Transport', 'USD');
select tests.add_expense('ann', null, 'Old purchase', 1000, '2025-01-01T10:00:00Z', 'Shopping', 'INR');
select tests.add_expense('ben', 'Trip', 'Hotel', 100000, '2026-04-05T10:00:00Z', 'Housing');
select tests.add_expense('ben', null, 'Private gift', 99999, '2026-04-06T10:00:00Z', 'Shopping', 'INR');
select tests.add_expense('cat', 'Band', 'Concert', 60000, '2026-04-07T10:00:00Z', 'Entertainment');

create table tests.ctx (name text primary key, doc jsonb);
grant all on tests.ctx to authenticated;

-- ===========================================================================
-- get_ai_spending_context: only the caller's own share, only their groups
-- ===========================================================================
select tests.authenticate_as('ann');
insert into tests.ctx values ('ann', public.get_ai_spending_context('Asia/Kolkata', 30, '2026-04-15T12:00:00Z'));
insert into tests.ctx values ('ann_utc', public.get_ai_spending_context('UTC', 30, '2026-04-15T12:00:00Z'));
insert into tests.ctx values ('ann_default', public.get_ai_spending_context(null, 30, '2026-04-15T12:00:00Z'));
reset role;

select is((select doc->>'primary_currency' from tests.ctx where name = 'ann'), 'INR', 'primary currency is the profile currency');
select is((select doc->>'timezone' from tests.ctx where name = 'ann'), 'Asia/Kolkata', 'the requested time zone is used');
select is((select doc->>'start_date' from tests.ctx where name = 'ann'), '2026-03-17', 'the window starts p_days-1 local days before today');
select is((select doc->>'end_date' from tests.ctx where name = 'ann'), '2026-04-15', 'the window ends today (local)');
select is((select doc->'currencies'->0->>'currency' from tests.ctx where name = 'ann'), 'INR', 'the primary currency block comes first');
select is((select (doc->'currencies'->0->>'total_minor')::bigint from tests.ctx where name = 'ann'), 80000::bigint,
          'INR total = own personal expense + own share of the group expense');
select is((select (doc->'currencies'->0->>'personal_total_minor')::bigint from tests.ctx where name = 'ann'), 30000::bigint,
          'personal part counts in full');
select is((select (doc->'currencies'->0->>'group_share_total_minor')::bigint from tests.ctx where name = 'ann'), 50000::bigint,
          'group part is only the caller''s share (half of 100000)');
select is((select (doc->'currencies'->0->>'expense_count')::bigint from tests.ctx where name = 'ann'), 2::bigint,
          'two INR entries in the window');
select is((select doc->'currencies'->1->>'currency' from tests.ctx where name = 'ann'), 'USD', 'another currency gets its own block');
select is((select (doc->'currencies'->1->>'total_minor')::bigint from tests.ctx where name = 'ann'), 5000::bigint,
          'USD amounts are not added to INR');
select is((select doc->'currencies'->0->'categories'->0->>'category' from tests.ctx where name = 'ann'), 'Housing',
          'categories ordered by own total');
select is((select (doc->'currencies'->0->'categories'->0->>'total_minor')::bigint from tests.ctx where name = 'ann'), 50000::bigint,
          'category total uses the share');
select is((select jsonb_path_query_array(doc, '$.currencies[0].months[*].month') from tests.ctx where name = 'ann'),
          '["2026-03", "2026-04"]'::jsonb, 'every local month of the window is listed');
select is((select jsonb_path_query_array(doc, '$.currencies[0].months[*].total_minor') from tests.ctx where name = 'ann'),
          '[0, 80000]'::jsonb, '2026-03-31T19:00Z is April in Asia/Kolkata');
select is((select jsonb_path_query_array(doc, '$.currencies[0].months[*].total_minor') from tests.ctx where name = 'ann_utc'),
          '[30000, 50000]'::jsonb, 'the same expense is March in UTC');
select is((select doc->>'timezone' from tests.ctx where name = 'ann_default'), 'Asia/Kolkata',
          'a NULL time zone falls back to the profile time zone');

select is((select jsonb_array_length(doc->'recent_expenses') from tests.ctx where name = 'ann'), 3, 'recent list holds the caller''s entries in the window');
select is((select jsonb_path_query_array(doc, '$.recent_expenses[*].title') from tests.ctx where name = 'ann'),
          '["Taxi", "Hotel", "Groceries"]'::jsonb, 'recent entries newest first');
select is((select doc->'recent_expenses'->1 from tests.ctx where name = 'ann'),
          jsonb_build_object('date', '2026-04-05', 'title', 'Hotel', 'category', 'Housing', 'amount_minor', 50000,
                             'currency', 'INR', 'is_group_share', true, 'group_name', 'Trip'),
          'a group entry shows the own share and the group name');
select is((select doc->'recent_expenses'->2->>'date' from tests.ctx where name = 'ann'), '2026-04-01', 'recent dates are local dates');
select is((select doc->'recent_expenses'->2->'group_name' from tests.ctx where name = 'ann'), 'null'::jsonb,
          'a personal entry has no group name');
select is((select doc->'groups' from tests.ctx where name = 'ann'),
          '[{"name": "Trip", "currency": "INR", "role": "admin"}]'::jsonb, 'only the caller''s own groups are listed');
select ok((select doc::text not like '%Private gift%' and doc::text not like '%Concert%' and doc::text not like '%Band%'
                  and doc::text not like '%Old purchase%' from tests.ctx where name = 'ann'),
          'no other member''s personal expense, no foreign group, nothing outside the window');
select ok((select doc::text not like '%' || tests.uid('ben')::text || '%' and doc::text not like '%@example.test%'
           from tests.ctx where name = 'ann'),
          'no other user ids or email addresses');

-- Ben paid the hotel: his share is still half, not the amount he paid.
select tests.authenticate_as('ben');
select is(jsonb_path_query_first(public.get_ai_spending_context('Asia/Kolkata', 30, '2026-04-15T12:00:00Z'),
                                  '$.recent_expenses[*] ? (@.title == "Hotel").amount_minor'),
          '50000'::jsonb, 'the payer''s context counts their share, not the amount paid');
reset role;

-- Recent list is capped at 15.
select tests.add_expense('dan', null, 'Coffee ' || i, 100 + i, '2026-04-01T10:00:00Z'::timestamptz + i * interval '1 hour', 'Food', 'INR')
from generate_series(1, 20) as i;
select tests.authenticate_as('dan');
select is(jsonb_array_length(public.get_ai_spending_context('UTC', 90, '2026-04-15T12:00:00Z')->'recent_expenses'), 15,
          'at most 15 recent entries');
select is((public.get_ai_spending_context('UTC', 90, '2026-04-15T12:00:00Z')->'currencies'->0->>'expense_count')::bigint, 20::bigint,
          'totals still cover every entry');

-- Validation and consent.
select throws_ok($$ select public.get_ai_spending_context('Mars/Base', 30) $$, '22023', 'invalid_timezone', 'unknown time zones are rejected');
select throws_ok($$ select public.get_ai_spending_context('UTC', 0) $$, '22023', 'invalid_range', 'p_days must be at least 1');
select throws_ok($$ select public.get_ai_spending_context('UTC', 367) $$, '22023', 'invalid_range', 'p_days is capped at 366');
select throws_ok($$ select public.get_ai_spending_context('UTC', null) $$, '22023', 'invalid_range', 'p_days cannot be NULL');
select throws_ok($$ select public.get_ai_spending_context('UTC', 90, 'infinity') $$, '22023', 'invalid_date', 'p_as_of cannot be infinity');
select throws_ok($$ select public.get_ai_spending_context('UTC', 90, '-infinity') $$, '22023', 'invalid_date', 'p_as_of cannot be -infinity');
select throws_ok($$ select public.get_ai_spending_context('UTC', 366, '1999-12-31T09:00:00Z') $$, '22023', 'invalid_date',
                 'p_as_of cannot be before 2000');
select throws_ok($$ select public.get_ai_spending_context('UTC', 366, now() + interval '400 days') $$, '22023', 'invalid_date',
                 'p_as_of cannot be more than a year ahead');
select is((public.get_ai_spending_context('UTC', 366, '2000-06-15T00:00:00Z')->>'start_date'), '1999-06-16',
          'the earliest accepted reference instant still works');
select tests.authenticate_as('cat');
select throws_ok($$ select public.get_ai_spending_context('UTC', 30) $$, 'P0001', 'consent_required',
                 'no spending context without AI consent (the business key the ai-chat function maps to consent_required)');
reset role;
select ok(not has_function_privilege('anon', 'public.get_ai_spending_context(text, integer, timestamptz)', 'execute'),
          'anon cannot request a spending context');
select is((select prosecdef from pg_proc where oid = 'public.get_ai_spending_context(text, integer, timestamptz)'::regprocedure),
          false, 'the spending context runs as the caller (RLS applies)');

-- ===========================================================================
-- consume_ai_quota: per-minute and daily limits
-- ===========================================================================
create table tests.events (name text primary key, id uuid);
grant all on tests.events to authenticated;

select tests.authenticate_as('ann');
insert into tests.events values ('e1', public.consume_ai_quota(3, 2));
insert into tests.events values ('e2', public.consume_ai_quota(3, 2));
select isnt((select id from tests.events where name = 'e1'), null, 'a request under both limits gets a reservation id');
select throws_ok($$ select public.consume_ai_quota(3, 2) $$, 'P0001', 'rate_limited', 'a third request within a minute is rate limited');
reset role;
select is((select count(*) from public.ai_usage_events where user_id = tests.uid('ann')), 2::bigint,
          'a refused request records nothing');
update public.ai_usage_events set created_at = now() - interval '61 seconds' where user_id = tests.uid('ann');

select tests.authenticate_as('ann');
insert into tests.events values ('e3', public.consume_ai_quota(3, 2));
select isnt((select id from tests.events where name = 'e3'), null, 'after a minute the next request is allowed');
select throws_ok($$ select public.consume_ai_quota(3, 2) $$, 'P0001', 'quota_exceeded', 'the daily limit is enforced');
select throws_ok($$ select public.consume_ai_quota(3, 60) $$, 'P0001', 'quota_exceeded',
                 'the daily limit applies whatever the per-minute limit');
select tests.authenticate_as('ben');
select lives_ok($$ select public.consume_ai_quota(3, 2) $$, 'another user has their own quota');
reset role;
update public.ai_usage_events set created_at = created_at - interval '1 day' where user_id = tests.uid('ann');
select tests.authenticate_as('ann');
select lives_ok($$ select public.consume_ai_quota(3, 2) $$, 'the daily quota resets on the next UTC day');

select throws_ok($$ select public.consume_ai_quota(0, 1) $$, '22023', 'invalid_limit', 'the daily limit must be positive');
select throws_ok($$ select public.consume_ai_quota(5000, 1) $$, '22023', 'invalid_limit', 'the daily limit is capped');
select throws_ok($$ select public.consume_ai_quota(10, 0) $$, '22023', 'invalid_limit', 'the per-minute limit must be positive');
select throws_ok($$ select public.consume_ai_quota(10, 500) $$, '22023', 'invalid_limit', 'the per-minute limit is capped');

-- finish_ai_usage
select is((public.finish_ai_usage((select id from tests.events where name = 'e3'), 'claude', 'claude-haiku-5-5', 'ok', 840, 1200, 300)).status,
          'ok', 'the owner completes a reserved event');
reset role;
select is((select row(provider, model, latency_ms, input_tokens, output_tokens, finished_at is not null)::text
           from public.ai_usage_events where id = (select id from tests.events where name = 'e3')),
          '(claude,claude-haiku-5-5,840,1200,300,t)', 'provider, model, latency and tokens are stored');
select tests.authenticate_as('ann');
select throws_ok($$ select public.finish_ai_usage((select id from tests.events where name = 'e3'), 'claude', 'm', 'failed') $$,
                 'P0001', 'usage_event_finished', 'a finished event cannot be changed');
select throws_ok($$ select public.finish_ai_usage((select id from tests.events where name = 'e2'), 'claude', 'm', 'reserved') $$,
                 '22023', 'invalid_status', 'the outcome must be a final status');
select throws_ok($$ select public.finish_ai_usage((select id from tests.events where name = 'e2'), 'claude', 'm', 'ok', -1) $$,
                 '22023', 'invalid_metrics', 'negative metrics are rejected');
select throws_ok($$ select public.finish_ai_usage((select id from tests.events where name = 'e2'), 'Bad Provider!', 'm', 'ok') $$,
                 '22023', 'invalid_provider', 'provider names are short identifiers');
select tests.authenticate_as('ben');
select throws_ok($$ select public.finish_ai_usage((select id from tests.events where name = 'e2'), 'claude', 'm', 'ok') $$,
                 'P0002', 'usage_event_not_found', 'a user cannot complete another user''s event');
select throws_ok($$ select public.finish_ai_usage(gen_random_uuid(), 'claude', 'm', 'ok') $$,
                 'P0002', 'usage_event_not_found', 'an unknown event is reported');

-- Every outcome the ai-chat Edge Function reports is accepted (provider and model may be NULL
-- when the request failed before any provider was called).
reset role;
insert into public.ai_usage_events (user_id) select tests.uid('dan') from generate_series(1, 7);
select tests.authenticate_as('dan');
select is((select array_agg((public.finish_ai_usage(e.id, case when s.st = 'error' then null else 'gemini' end,
                                                    case when s.st = 'error' then null else 'gemini-3.8-flash' end,
                                                    s.st, 12, null, null)).status order by s.n)
           from (select id, row_number() over (order by id) as n from public.ai_usage_events
                 where user_id = auth.uid() and status = 'reserved') as e
           join unnest(array['ok', 'truncated', 'declined', 'interrupted', 'failed', 'aborted', 'error'])
                with ordinality as s (st, n) using (n)),
          array['ok', 'truncated', 'declined', 'interrupted', 'failed', 'aborted', 'error'],
          'finish_ai_usage accepts every status the ai-chat function sends');
reset role;
-- PostgREST matches RPC arguments by name: these are the names the Edge Functions send.
select is((select array_agg(p.proname || '(' || array_to_string(p.proargnames[1:p.pronargs], ',') || ')' order by p.proname)
           from pg_proc as p
           where p.pronamespace = 'public'::regnamespace
             and p.proname in ('consume_ai_quota', 'finish_ai_usage', 'get_ai_spending_context')),
          array['consume_ai_quota(p_daily_limit,p_per_minute)',
                'finish_ai_usage(p_event_id,p_provider,p_model,p_status,p_latency_ms,p_input_tokens,p_output_tokens)',
                'get_ai_spending_context(p_tz,p_days,p_as_of)'],
          'the AI RPCs have the argument names the ai-chat function sends');
select is((select prorettype::regtype::text from pg_proc where oid = 'public.consume_ai_quota(integer, integer)'::regprocedure),
          'uuid', 'consume_ai_quota returns the reserved event id as a plain uuid');
select tests.authenticate_as('ben');

-- Table access
select is((select count(*) from public.ai_usage_events), 1::bigint, 'a user reads only their own usage events');
select tests.authenticate_as('ann');
select is((select count(*) from public.ai_usage_events where user_id <> tests.uid('ann')), 0::bigint,
          'other users'' usage events are invisible');
select throws_ok($$ insert into public.ai_usage_events (user_id) values (auth.uid()) $$, '42501', null,
                 'clients cannot insert usage events directly');
select throws_ok($$ update public.ai_usage_events set status = 'failed' $$, '42501', null,
                 'clients cannot update usage events directly');
select throws_ok($$ delete from public.ai_usage_events $$, '42501', null, 'clients cannot delete usage events');
select throws_ok($$ select public.purge_old_ai_usage() $$, '42501', null, 'clients cannot run the usage cleanup');
reset role;
update public.ai_usage_events set created_at = now() - interval '181 days' where id = (select id from tests.events where name = 'e1');
set local role service_role;
select is((public.purge_old_ai_usage())->>'deleted', '1', 'service_role purges usage events older than 180 days');
reset role;
select ok(not has_function_privilege('anon', 'public.consume_ai_quota(integer, integer)', 'execute')
          and not has_function_privilege('anon', 'public.finish_ai_usage(uuid, text, text, text, integer, integer, integer)', 'execute'),
          'anon cannot use the quota functions');
select ok(exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'ai_usage_events'
                  and indexdef like '%(user_id, created_at DESC)%'), 'quota lookups are indexed');

-- ===========================================================================
-- ai_reports: insert own only, read own only, never changed
-- ===========================================================================
select tests.authenticate_as('ann');
select lives_ok($$ insert into public.ai_reports (provider, reason, message_excerpt, note)
                   values ('claude', 'inaccurate', 'The total was wrong.', '  wrong month  ') $$,
                'a user reports an answer (user_id defaults to the caller)');
select is((select user_id from public.ai_reports), tests.uid('ann'), 'the report belongs to the caller');
select is((select note from public.ai_reports), 'wrong month', 'the note is trimmed');
select throws_ok(format($$ insert into public.ai_reports (user_id, reason, message_excerpt) values (%L, 'other', 'x') $$, tests.uid('ben')),
                 '42501', null, 'a report cannot be filed in another user''s name');
select throws_ok($$ insert into public.ai_reports (id, reason, message_excerpt) values (gen_random_uuid(), 'other', 'x') $$,
                 '42501', null, 'the report id is server-generated');
select throws_ok($$ insert into public.ai_reports (created_at, reason, message_excerpt) values (now() - interval '1 year', 'other', 'x') $$,
                 '42501', null, 'the report time is server-set');
select throws_ok($$ insert into public.ai_reports (reason, message_excerpt) values ('spam', 'x') $$,
                 '23514', null, 'the reason must be one of the listed values');
select throws_ok($$ insert into public.ai_reports (reason, message_excerpt) values ('other', repeat('x', 2001)) $$,
                 '23514', null, 'the excerpt is limited to 2000 characters');
select throws_ok($$ insert into public.ai_reports (reason, message_excerpt) values ('other', '') $$,
                 '23514', null, 'the excerpt cannot be empty');
select throws_ok($$ insert into public.ai_reports (reason, message_excerpt, note) values ('other', 'x', repeat('n', 501)) $$,
                 '23514', null, 'the note is limited to 500 characters');
select throws_ok($$ update public.ai_reports set reason = 'other' $$, '42501', null, 'reports cannot be edited');
select throws_ok($$ delete from public.ai_reports $$, '42501', null, 'reports cannot be deleted by clients');
select tests.authenticate_as('ben');
select is((select count(*) from public.ai_reports), 0::bigint, 'other users cannot read a report');
reset role;
insert into public.ai_reports (user_id, reason, message_excerpt)
select tests.uid('ann'), 'other', 'filler ' || i from generate_series(1, 29) as i;
select tests.authenticate_as('ann');
select throws_ok($$ insert into public.ai_reports (reason, message_excerpt) values ('other', 'one more') $$,
                 'P0001', 'rate_limited', 'at most 30 reports per user per day');
reset role;
select is((select array_agg(c.relname::text order by c.relname) from pg_class as c
           where c.relnamespace = 'public'::regnamespace and c.relname in ('ai_reports', 'ai_usage_events')
             and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
                  or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))),
          null, 'anon has no privileges on the AI tables');

select * from finish();
rollback;
