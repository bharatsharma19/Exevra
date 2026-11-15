-- Assertions on a database upgraded from the baseline with legacy_fixture.sql (run.sh). pgTAP, run
-- in a transaction that is rolled back.
\set ON_ERROR_STOP 1
begin;
set local client_min_messages = warning;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- Timestamps of existing rows are kept: the conversion is not a user edit.
select is((select count(*) from public.expenses where updated_at <> '2025-01-02 00:00:00+00'), 0::bigint,
          'expenses.updated_at of legacy rows is unchanged by the upgrade');
select is((select count(*) from public.expenses where created_at <> '2025-01-01 00:00:00+00'), 0::bigint,
          'expenses.created_at of legacy rows is unchanged by the upgrade');
select is((select count(*) from public.groups where updated_at <> '2025-01-02 00:00:00+00'), 0::bigint,
          'groups.updated_at of legacy rows is unchanged by the upgrade');
select is((select count(*) from public.profiles
           where created_at = '2025-01-01 00:00:00+00' and updated_at <> '2025-01-02 00:00:00+00'), 0::bigint,
          'profiles.updated_at of legacy rows is unchanged by the upgrade (backfilled profiles are new rows)');

-- Money conversion (no clamping; rounding to the currency's minor unit only).
select is((select amount_minor from public.expenses where id = '20000000-0000-0000-0000-000000000001'), 1001::bigint,
          'a two-decimal amount becomes minor units');
select is((select amount_minor from public.expenses where id = '20000000-0000-0000-0000-000000000004'), 99999999999::bigint,
          'the largest legacy amount converts exactly');
select is((select amount_minor || ' ' || currency from public.expenses where id = '20000000-0000-0000-0000-000000000009'),
          '1234 JPY', 'a group expense in a zero-decimal currency converts exactly');
select is((select amount_minor || ' ' || currency from public.settlements where id = '30000000-0000-0000-0000-000000000004'),
          '12 JPY', 'a settlement in a zero-decimal currency converts exactly');

-- Active-group pointers only point at groups the user is an approved member of.
select is((select group_id from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), null::uuid,
          'an active group the user does not belong to is cleared');
select is((select group_id from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
          '10000000-0000-0000-0000-000000000001'::uuid, 'a valid active group is kept');
select is((select count(*) from public.profiles as p
           where p.group_id is not null
             and not exists (select 1 from public.group_members as gm
                             where gm.group_id = p.group_id and gm.user_id = p.id and gm.status = 'approved')),
          0::bigint, 'no profile points at a group without an approved membership');

-- Invitations: only invitations sent by the current admin stay pending.
select is((select status from public.group_invitations where id = '40000000-0000-0000-0000-00000000000a'), 'revoked',
          'a pending invitation sent by a non-admin member is revoked');
select is((select status from public.group_invitations where id = '40000000-0000-0000-0000-000000000002'), 'pending',
          'the newest pending invitation from the admin stays pending');
select is((select status from public.group_invitations where id = '40000000-0000-0000-0000-000000000001'), 'revoked',
          'an older duplicate pending invitation is revoked');
select is((select count(*) from public.group_invitations as gi
           where gi.status = 'pending'
             and not exists (select 1 from public.groups as g where g.id = gi.group_id and g.admin_id = gi.inviter_id)),
          0::bigint, 'every pending invitation was sent by the group''s current admin');
select is(public.hash_invitation_token('legacytokenpending2'),
          (select token_hash from public.group_invitations where id = '40000000-0000-0000-0000-000000000002'),
          'a legacy token still matches its stored hash');

-- group_members matches a fresh install, whatever schema.sql version the database started from.
select is((select confrelid::regclass::text || ' ' || confdeltype::text from pg_constraint
           where conrelid = 'public.group_members'::regclass and conname = 'group_members_user_id_fkey'),
          'profiles c', 'group_members.user_id references profiles ON DELETE CASCADE');
select is((select confrelid::regclass::text || ' ' || confdeltype::text from pg_constraint
           where conrelid = 'public.group_members'::regclass and conname = 'group_members_invited_by_fkey'),
          'profiles n', 'group_members.invited_by references profiles ON DELETE SET NULL');
select is((select column_default from information_schema.columns
           where table_schema = 'public' and table_name = 'group_members' and column_name = 'role'),
          '''member''::text', 'group_members.role defaults to member');
select is((select count(*) from public.group_members as gm
           where not exists (select 1 from public.profiles as p where p.id = gm.user_id)), 0::bigint,
          'every membership belongs to a profile (missing profiles are backfilled)');

-- Membership invariants after the upgrade.
select is((select count(*) from public.groups as g
           where (select count(*) from public.group_members as gm where gm.group_id = g.id and gm.role = 'admin') <> 1
              or not exists (select 1 from public.group_members as gm
                             where gm.group_id = g.id and gm.user_id = g.admin_id and gm.role = 'admin')),
          0::bigint, 'every group has exactly one admin row, matching groups.admin_id');
select is((select sum(net_minor) from public.groups as g, public.group_balance_rows(g.id)), 0::numeric,
          'balances of every group sum to zero');

select * from finish();
rollback;
