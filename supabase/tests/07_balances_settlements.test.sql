-- Group balances and settlements: the balance matrix (equal split, late joiner, departed payer,
-- viewers and pending members, leftover units, a zero-decimal currency, the group currency rule),
-- settle-up suggestions, and the settlement life cycle (record within the debt, payee-only
-- confirmation, voiding by a party or the admin, voided and pending amounts not counted) with an
-- append-only audit trail.
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

select plan(106);

select tests.create_user('alice');
select tests.create_user('bob');
select tests.create_user('carol');
select tests.create_user('dan');
select tests.create_user('erin');
select tests.create_user('vic');
select tests.create_user('pete');
select tests.create_user('outsider');

-- ===========================================================================
-- Balance matrix
-- ===========================================================================
select tests.create_group_as('alice', 'Trip', 'INR');
select tests.add_member(tests.gid('Trip'), 'bob', 'member');
select tests.add_member(tests.gid('Trip'), 'carol', 'member');
select tests.add_member(tests.gid('Trip'), 'erin', 'member');
select tests.add_member(tests.gid('Trip'), 'vic', 'viewer');
select tests.add_member(tests.gid('Trip'), 'pete', 'viewer', 'pending');

-- Equal split among admins and members.
select tests.add_expense('alice', 'Trip', 'Hotel', 1200);
select is(tests.net('Trip', 'alice'), 900::bigint, 'the payer is owed the others'' shares');
select is(tests.net('Trip', 'bob'), -300::bigint, 'a member owes an equal share');
select is(tests.net('Trip', 'erin'), -300::bigint, 'every member owes the same share');
select is((select count(*) from public.group_balance_rows(tests.gid('Trip')) where user_id in (tests.uid('vic'), tests.uid('pete'))),
          0::bigint, 'viewers and pending members have no balance');

-- A late joiner is only charged for later expenses.
select tests.add_member(tests.gid('Trip'), 'dan', 'member');
select tests.add_expense('bob', 'Trip', 'Dinner', 500);
select is(tests.net('Trip', 'dan'), -100::bigint, 'a late joiner is not charged for earlier expenses');
select is(tests.net('Trip', 'bob'), 100::bigint, 'paid minus owed: -300 + 500 - 100');
select is(tests.net('Trip', 'alice'), 800::bigint, 'the admin''s balance includes the later share');
select is((select sum(net_minor) from public.group_balance_rows(tests.gid('Trip'))), 0::numeric, 'balances sum to zero');

-- Suggestions on the current state: alice +800, bob +100, carol -400, erin -400, dan -100.
select tests.authenticate_as('vic');
select results_eq(
    $$ select from_user, to_user, amount_minor, currency from public.get_group_settle_suggestions(tests.gid('Trip')) $$,
    $$ values (least(tests.uid('carol'), tests.uid('erin')), tests.uid('alice'), 400::bigint, 'INR'),
              (greatest(tests.uid('carol'), tests.uid('erin')), tests.uid('alice'), 400::bigint, 'INR'),
              (tests.uid('dan'), tests.uid('bob'), 100::bigint, 'INR') $$,
    'settle-up suggestions match the largest debtors with the largest creditors');
select is((select count(*) from public.get_group_balances(tests.gid('Trip'))), 5::bigint,
          'a viewer can read the balances of every participant');
select is((select display_name || ':' || net_minor || ':' || currency from public.get_group_balances(tests.gid('Trip'))
           where user_id = tests.uid('alice')), 'Alice:800:INR', 'balances carry the display name and the group currency');
select is((select paid_minor || '/' || owed_minor || '/' || settled_out_minor || '/' || settled_in_minor
           from public.get_group_balances(tests.gid('Trip')) where user_id = tests.uid('bob')),
          '500/400/0/0', 'paid, owed and settled amounts are reported separately');
select is((select user_id from public.get_group_balances(tests.gid('Trip')) limit 1), tests.uid('alice'),
          'balances are ordered from the largest creditor');
select tests.authenticate_as('pete');
select throws_ok($$ select * from public.get_group_balances(tests.gid('Trip')) $$, '42501', 'not_group_member',
                 'a pending member cannot read balances');
select tests.authenticate_as('outsider');
select throws_ok($$ select * from public.get_group_balances(tests.gid('Trip')) $$, '42501', 'not_group_member',
                 'a non-member cannot read balances');
select throws_ok($$ select * from public.get_group_settle_suggestions(tests.gid('Trip')) $$, '42501', 'not_group_member',
                 'a non-member cannot read suggestions');
select throws_ok($$ select * from public.group_balance_rows(tests.gid('Trip')) $$, '42501', null,
                 'the internal balance function is not callable by clients');
reset role;

-- A departed payer is still credited.
select tests.add_expense('erin', 'Trip', 'Fuel', 1000);
select is(tests.net('Trip', 'erin'), 400::bigint, 'a payer is credited with what the others owe them');
select tests.remove_member(tests.gid('Trip'), 'erin');
select is(tests.net('Trip', 'erin'), 400::bigint, 'a payer who left the group keeps their credit');
select tests.authenticate_as('alice');
select is((select display_name || ':' || net_minor from public.get_group_balances(tests.gid('Trip')) where user_id = tests.uid('erin')),
          'Erin:400', 'a member who left is still listed with their balance');
select is((select count(*) from public.get_group_settle_suggestions(tests.gid('Trip')) where tests.uid('erin') in (from_user, to_user)),
          0::bigint, 'suggestions only involve current members');
reset role;
select tests.add_expense('alice', 'Trip', 'After erin', 400);
select is((select count(*) from public.expense_splits where expense_id = tests.eid('After erin') and user_id = tests.uid('erin')),
          0::bigint, 'a member who left is not charged for new expenses');

-- A deleted account is shown as one "Former member" row.
delete from auth.users where id = tests.uid('erin');
select tests.authenticate_as('alice');
select is((select display_name || ':' || net_minor from public.get_group_balances(tests.gid('Trip')) where user_id is null),
          'Former member:400', 'a deleted account''s balance is kept as a former member');
select is((select sum(net_minor) from public.get_group_balances(tests.gid('Trip'))), 0::numeric,
          'balances still sum to zero with a former member');
reset role;

-- Leftover minor units are deterministic and exact.
select tests.add_expense('dan', 'Trip', 'Snacks', 101);
select is((select sum(share_minor) from public.expense_splits where expense_id = tests.eid('Snacks')), 101::numeric,
          'an uneven amount is fully split');
select is(tests.share('Snacks', 'dan'), 26::bigint, 'the payer takes the first leftover unit');
select is((select count(*) from public.expense_splits where expense_id = tests.eid('Snacks') and share_minor = 25), 3::bigint,
          'the other participants owe the base share');

-- A currency without minor units.
select tests.create_group_as('alice', 'Tokyo', 'JPY');
select tests.add_member(tests.gid('Tokyo'), 'bob', 'member');
select tests.add_member(tests.gid('Tokyo'), 'carol', 'member');
select tests.add_expense('bob', 'Tokyo', 'Ramen', 1000);
select is(tests.net('Tokyo', 'bob'), 666::bigint, 'JPY: the payer is owed 1000 - 334 yen');
select is(tests.net('Tokyo', 'alice'), -333::bigint, 'JPY: members owe whole yen');
select tests.authenticate_as('carol');
select is((select distinct currency from public.get_group_balances(tests.gid('Tokyo'))), 'JPY', 'JPY balances are reported in yen');
select throws_ok($$ insert into public.expenses (user_id, group_id, title, amount_minor, category, currency)
                    values (auth.uid(), tests.gid('Tokyo'), 'Wrong currency', 100, 'Food', 'INR') $$,
                 '22023', 'currency_mismatch', 'an expense in another currency is rejected by the group');
select throws_ok($$ select public.record_settlement(tests.gid('Tokyo'), tests.uid('bob'), 334) $$,
                 'P0001', 'settlement_exceeds_debt', 'a JPY settlement cannot exceed the debt in yen');
select lives_ok($$ select public.record_settlement(tests.gid('Tokyo'), tests.uid('bob'), 333) $$,
                'a JPY settlement for the exact debt is accepted');
reset role;
select is((select currency::text from public.settlements where group_id = tests.gid('Tokyo')), 'JPY', 'settlements use the group currency');
select throws_ok($$ insert into public.settlements (group_id, from_user, to_user, amount_minor, currency)
                    values (tests.gid('Tokyo'), tests.uid('alice'), tests.uid('bob'), 10, 'INR') $$,
                 '22023', 'currency_mismatch', 'a settlement in another currency is rejected even for privileged writers');

-- ===========================================================================
-- Settlements
-- ===========================================================================
select tests.create_group_as('alice', 'House', 'INR');
select tests.add_member(tests.gid('House'), 'bob', 'member');
select tests.add_member(tests.gid('House'), 'carol', 'member');
select tests.add_member(tests.gid('House'), 'vic', 'viewer');
select tests.add_member(tests.gid('House'), 'pete', 'viewer', 'pending');
select tests.add_expense('bob', 'House', 'Groceries', 3000);
-- bob +2000, alice -1000, carol -1000

-- Direct writes are not possible.
select tests.authenticate_as('alice');
select throws_ok($$ insert into public.settlements (group_id, from_user, to_user, amount_minor)
                    values (tests.gid('House'), tests.uid('bob'), tests.uid('outsider'), 500) $$,
                 '42501', null, 'settlements cannot be inserted directly, even by the admin');

-- Parameter and membership checks.
select tests.authenticate_as('vic');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 10) $$,
                 'P0001', 'settlement_exceeds_debt', 'a viewer without a debt cannot record a settlement');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 10, repeat('x', 100000)) $$,
                 '22023', 'invalid_note', 'notes longer than 200 characters are rejected');
select tests.authenticate_as('carol');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('outsider'), 10) $$,
                 'P0002', 'member_not_found', 'the payee must be a member of the group');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('pete'), 10) $$,
                 'P0002', 'member_not_found', 'the payee must be an approved member');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('carol'), 10) $$,
                 '22023', 'invalid_target', 'a settlement to oneself is rejected');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 0) $$,
                 '22023', 'invalid_amount', 'a zero amount is rejected');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('alice'), 10) $$,
                 'P0001', 'settlement_exceeds_debt', 'paying someone who is not owed money is rejected');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 1001) $$,
                 'P0001', 'settlement_exceeds_debt', 'paying more than the debt is rejected');
select tests.authenticate_as('pete');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 10) $$,
                 '42501', 'not_group_member', 'a pending member cannot record settlements');
select tests.authenticate_as('outsider');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 10) $$,
                 '42501', 'not_group_member', 'a non-member cannot record settlements');
reset role;
select is((select count(*) from public.settlements where group_id = tests.gid('House')), 0::bigint, 'nothing was recorded');

-- Record and confirm.
select tests.settle('s1', 'carol', 'House', 'bob', 600);
select is((select status || ':' || from_user::text || ':' || to_user::text || ':' || amount_minor || ':' || currency
           from public.settlements where id = tests.sid('s1')),
          'pending:' || tests.uid('carol') || ':' || tests.uid('bob') || ':600:INR', 'a recorded settlement is pending');
select is((select created_by from public.settlements where id = tests.sid('s1')), tests.uid('carol'), 'created_by is the caller');
select is(tests.net('House', 'carol'), -1000::bigint, 'a pending settlement does not change the balance');
select tests.authenticate_as('carol');
select throws_ok($$ select public.record_settlement(tests.gid('House'), tests.uid('bob'), 401) $$,
                 'P0001', 'settlement_exceeds_debt', 'pending settlements count against the remaining debt');
select throws_ok($$ select public.confirm_settlement(tests.sid('s1')) $$,
                 '42501', 'not_settlement_payee', 'the payer cannot confirm their own settlement');
select tests.authenticate_as('alice');
select throws_ok($$ select public.confirm_settlement(tests.sid('s1')) $$,
                 '42501', 'not_settlement_payee', 'the admin cannot confirm for the payee');
select tests.authenticate_as('bob');
select throws_ok($$ update public.settlements set status = 'confirmed', confirmed_at = now() where id = tests.sid('s1') $$,
                 '42501', null, 'settlements cannot be updated directly');
select lives_ok($$ select public.confirm_settlement(tests.sid('s1')) $$, 'the payee confirms the settlement');
select throws_ok($$ select public.confirm_settlement(tests.sid('s1')) $$,
                 'P0001', 'settlement_not_pending', 'a settlement is confirmed only once');
reset role;
select is((select status from public.settlements where id = tests.sid('s1')), 'confirmed', 'the settlement is confirmed');
select ok((select confirmed_at is not null from public.settlements where id = tests.sid('s1')), 'confirmed_at is set');
select is(tests.net('House', 'carol'), -400::bigint, 'a confirmed settlement reduces the payer''s debt');
select is(tests.net('House', 'bob'), 1400::bigint, 'a confirmed settlement reduces the payee''s credit');

-- Void by the payer.
select tests.settle('s2', 'carol', 'House', 'bob', 400);
select tests.authenticate_as('vic');
select throws_ok($$ select public.void_settlement(tests.sid('s2'), 'not mine') $$,
                 '42501', 'not_settlement_party', 'someone outside the settlement cannot void it');
select tests.authenticate_as('carol');
select throws_ok($$ select public.void_settlement(tests.sid('s2'), repeat('r', 201)) $$,
                 '22023', 'invalid_reason', 'void reasons are at most 200 characters');
select lives_ok($$ select public.void_settlement(tests.sid('s2'), 'Paid in cash instead') $$, 'the payer can void a pending settlement');
select throws_ok($$ select public.void_settlement(tests.sid('s2'), 'again') $$,
                 'P0001', 'settlement_already_voided', 'a settlement is voided only once');
select tests.authenticate_as('bob');
select throws_ok($$ select public.confirm_settlement(tests.sid('s2')) $$,
                 'P0001', 'settlement_not_pending', 'a voided settlement cannot be confirmed');
reset role;
select is((select status || ':' || voided_by::text || ':' || void_reason from public.settlements where id = tests.sid('s2')),
          'voided:' || tests.uid('carol') || ':Paid in cash instead', 'the void records who, and why');
select is(tests.net('House', 'carol'), -400::bigint, 'a voided settlement does not count');

-- Void by the payee.
select tests.settle('s3', 'carol', 'House', 'bob', 300);
select tests.authenticate_as('bob');
select lives_ok($$ select public.void_settlement(tests.sid('s3'), null) $$, 'the payee can void a settlement');
reset role;

-- Void by the admin (not a party), including a confirmed settlement.
select tests.settle('s4', 'carol', 'House', 'bob', 100);
select tests.authenticate_as('bob');
select lives_ok($$ select public.confirm_settlement(tests.sid('s4')) $$, 'the payee confirms another settlement');
reset role;
select is(tests.net('House', 'carol'), -300::bigint, 'the confirmed settlement counts');
select tests.authenticate_as('alice');
select lives_ok($$ select public.void_settlement(tests.sid('s4'), 'Entered twice') $$, 'the group admin can void a confirmed settlement');
reset role;
select is(tests.net('House', 'carol'), -400::bigint, 'voiding a confirmed settlement restores the debt');
select is((select settled_out_minor from public.group_balance_rows(tests.gid('House')) where user_id = tests.uid('carol')), 600::bigint,
          'only confirmed settlements are counted as settled');

-- Suggestions account for pending settlements.
select tests.settle('s5', 'alice', 'House', 'bob', 250);
select tests.authenticate_as('bob');
select results_eq(
    $$ select from_user, to_user, amount_minor from public.get_group_settle_suggestions(tests.gid('House')) order by amount_minor desc $$,
    $$ values (tests.uid('alice'), tests.uid('bob'), 750::bigint), (tests.uid('carol'), tests.uid('bob'), 400::bigint) $$,
    'suggestions subtract amounts already pending');
reset role;

-- Server-controlled fields even for privileged writers.
insert into public.settlements (id, group_id, from_user, to_user, amount_minor, status, created_at, confirmed_at)
values ('00000000-0000-0000-0000-0000000000cc', tests.gid('House'), tests.uid('alice'), tests.uid('bob'), 1, 'confirmed', '2000-01-01', now());
select is((select count(*) from public.settlements where id = '00000000-0000-0000-0000-0000000000cc'), 0::bigint,
          'a supplied settlement id is replaced');
select is((select count(*) from public.settlements where group_id = tests.gid('House') and created_at < '2001-01-01'), 0::bigint,
          'a supplied created_at is replaced');
select throws_ok($$ insert into public.settlements (group_id, from_user, to_user, amount_minor, status)
                    values (tests.gid('House'), tests.uid('alice'), tests.uid('bob'), 1, 'settled') $$,
                 '23514', null, 'unknown statuses are rejected');
select throws_ok($$ insert into public.settlements (group_id, from_user, to_user, amount_minor)
                    values (tests.gid('House'), tests.uid('alice'), tests.uid('alice'), 1) $$,
                 '23514', null, 'payer and payee must differ');

-- ===========================================================================
-- Audit trail
-- ===========================================================================
select is((select array_agg(action order by action) from public.settlement_events where settlement_id = tests.sid('s1')),
          array['confirmed', 'recorded'], 's1 has a recorded and a confirmed event');
select is((select array_agg(action::text order by action) from public.settlement_events where settlement_id = tests.sid('s2')),
          array['recorded', 'voided'], 's2 has a recorded and a voided event');
select is((select actor from public.settlement_events where settlement_id = tests.sid('s1') and action = 'confirmed'),
          tests.uid('bob'), 'the confirm event records the payee as actor');
select is((select actor from public.settlement_events where settlement_id = tests.sid('s4') and action = 'voided'),
          tests.uid('alice'), 'the void event records the admin as actor');
select is((select details->>'previous_status' from public.settlement_events where settlement_id = tests.sid('s4') and action = 'voided'),
          'confirmed', 'the void event records the previous status');
select is((select details->>'amount_minor' from public.settlement_events where settlement_id = tests.sid('s1') and action = 'recorded'),
          '600', 'the record event carries the amount');

select tests.authenticate_as('vic');
select is((select count(*) from public.settlement_events where group_id = tests.gid('House')), 10::bigint,
          'group members (viewers included) can read the audit trail');
select is((select count(*) from public.settlements where group_id = tests.gid('House')), 6::bigint,
          'group members (viewers included) can read settlements');
select tests.authenticate_as('bob');
select throws_ok($$ insert into public.settlement_events (settlement_id, group_id, actor, action)
                    values (tests.sid('s1'), tests.gid('House'), auth.uid(), 'confirmed') $$, '42501', null,
                 'clients cannot add audit events');
select throws_ok($$ update public.settlement_events set action = 'voided' where settlement_id = tests.sid('s1') $$, '42501', null,
                 'clients cannot change audit events');
select throws_ok($$ delete from public.settlement_events where settlement_id = tests.sid('s1') $$, '42501', null,
                 'clients cannot delete audit events');
select tests.authenticate_as('pete');
select is((select count(*) from public.settlement_events), 0::bigint, 'pending members cannot read the audit trail');
select is((select count(*) from public.settlements), 0::bigint, 'pending members cannot read settlements');
select tests.authenticate_as('outsider');
select is((select count(*) from public.settlement_events), 0::bigint, 'non-members cannot read the audit trail');
reset role;

set local role service_role;
select throws_ok($$ update public.settlement_events set details = '{}' where settlement_id = tests.sid('s1') $$, '42501', null,
                 'the service role cannot change audit events');
select throws_ok($$ delete from public.settlement_events where settlement_id = tests.sid('s1') $$, '42501', null,
                 'the service role cannot delete audit events');
reset role;
select throws_ok($$ update public.settlement_events set details = '{}' where settlement_id = tests.sid('s1') $$,
                 '42501', 'settlement_events_append_only', 'audit events are immutable even for the table owner');
select throws_ok($$ delete from public.settlement_events where settlement_id = tests.sid('s1') $$,
                 '42501', 'settlement_events_append_only', 'audit events cannot be deleted by the table owner');
select is((select count(*) from public.settlement_events where settlement_id = tests.sid('s1')), 2::bigint, 'the audit rows are intact');

-- A deleted account keeps the history (user columns cleared); a deleted group removes it.
delete from auth.users where id = tests.uid('carol');
select is((select count(*) from public.settlements where group_id = tests.gid('House') and from_user is null), 4::bigint,
          'settlements of a deleted account are kept without the user');
select is((select count(*) from public.settlement_events where group_id = tests.gid('House')), 10::bigint,
          'audit events of a deleted account are kept');
select is((select count(*) from public.settlement_events where group_id = tests.gid('House') and actor is null), 5::bigint,
          'the deleted account is no longer named as actor');
select tests.authenticate_as('alice');
select lives_ok($$ delete from public.groups where id = tests.gid('House') $$, 'the admin can delete the group');
reset role;
select is((select count(*) from public.settlement_events where group_id = tests.gid('House')), 0::bigint,
          'deleting the group removes its audit trail');

-- ===========================================================================
-- Hygiene
-- ===========================================================================
select ok(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'settlements'),
          'settlements are published for realtime');
select is((select array_agg(c.relname::text order by c.relname) from pg_class as c
           where c.relnamespace = 'public'::regnamespace and c.relname in ('settlements', 'settlement_events', 'expense_splits')
             and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
                  or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))),
          null, 'anon has no privileges on settlements, audit events or splits');
select is((select count(*) from pg_policies where schemaname = 'public' and tablename in ('settlements', 'settlement_events')
           and cmd <> 'SELECT'), 0::bigint, 'settlements and audit events have no write policies');
select ok(to_regprocedure('public.record_settlement(uuid, uuid, numeric, text)') is null, 'the old settlement RPC is gone');

select * from finish();
rollback;
