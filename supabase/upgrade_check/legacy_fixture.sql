-- Legacy data for the upgrade check (run.sh). Loaded on top of the baseline migration only, i.e. the
-- schema the hosted project had before the migration series. It covers the shapes the upgrade has to
-- convert: mixed-case emails and currencies, over-long names and titles (also cut at a space), short
-- invite codes, numeric amounts, plaintext invitation tokens, invitations sent by a non-admin, an
-- active group the user does not belong to, a user without a profile, a group expense paid by a
-- user who already left the group, and fixed created_at/updated_at values.
--
-- It also reproduces the drift of databases first built from an older schema.sql: group_members
-- foreign keys pointing at auth.users and a 'viewer' role default.
\set ON_ERROR_STOP 1
BEGIN;

-- Drift from older schema versions.
ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_user_id_fkey;
ALTER TABLE public.group_members DROP CONSTRAINT IF EXISTS group_members_invited_by_fkey;
ALTER TABLE public.group_members ADD CONSTRAINT group_members_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE;
ALTER TABLE public.group_members ADD CONSTRAINT group_members_invited_by_fkey
    FOREIGN KEY (invited_by) REFERENCES auth.users (id) ON DELETE SET NULL;
ALTER TABLE public.group_members ALTER COLUMN role SET DEFAULT 'viewer';

-- Users (handle_new_user creates the profiles).
INSERT INTO auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_user_meta_data, phone, created_at, updated_at) VALUES
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'alice@example.com', now(), jsonb_build_object('full_name', '   ' || repeat('Alice Example ', 6) || '  '), NULL, now() - interval '400 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'Bob@Example.COM', now(), '{}'::jsonb, NULL, now() - interval '300 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'carol@example.com', now(), '{"name":"   "}'::jsonb, NULL, now() - interval '200 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'dave@example.com', now(), '{"full_name":"Dave"}'::jsonb, NULL, now() - interval '100 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'erin@example.com', now(), '{"full_name":"Erin"}'::jsonb, NULL, now() - interval '90 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'frank@example.com', NULL, '{"full_name":"Frank","avatar_url":"http://example.com/x.png"}'::jsonb, NULL, now() - interval '80 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000010', 'authenticated', 'authenticated', NULL, NULL, '{}'::jsonb, '+910000000000', now() - interval '70 days', now()),
 ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'noprofile@example.com', now(), '{}'::jsonb, NULL, now() - interval '60 days', now());
DELETE FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000011';
UPDATE public.profiles SET currency = 'usd', theme_mode = 'dark', ai_consent = true WHERE id = '00000000-0000-0000-0000-00000000000a';
UPDATE public.profiles SET currency = 'XYZ', display_name = '' WHERE id = '00000000-0000-0000-0000-00000000000c';
UPDATE public.profiles SET currency = ' eur ' WHERE id = '00000000-0000-0000-0000-00000000000e';
UPDATE public.profiles SET currency = 'JPY' WHERE id = '00000000-0000-0000-0000-00000000000f';

-- Groups.
INSERT INTO public.groups (id, name, invite_code, admin_id, created_at) VALUES
 ('10000000-0000-0000-0000-000000000001', '  Flat 4B  ', 'a1b2c3d4', '00000000-0000-0000-0000-00000000000a', now() - interval '350 days'),
 ('10000000-0000-0000-0000-000000000002', repeat('Trip ', 20), 'ABCD1234', '00000000-0000-0000-0000-00000000000e', now() - interval '80 days'),
 ('10000000-0000-0000-0000-000000000003', 'Two admins', 'abcd1234', '00000000-0000-0000-0000-00000000000e', now() - interval '70 days'),
 ('10000000-0000-0000-0000-000000000004', 'Small group', 'deadbeef', '00000000-0000-0000-0000-00000000000a', now() - interval '60 days'),
 ('10000000-0000-0000-0000-000000000005', 'Yen group', '0f0f0f0f', '00000000-0000-0000-0000-00000000000f', now() - interval '50 days');

-- Memberships (role given explicitly, as the old app did). The member of 'Small group' has no profile
-- (the upgrade backfills profiles for every auth user).
INSERT INTO public.group_members (group_id, user_id, role, invited_by, joined_at) VALUES
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'admin', NULL, now() - interval '350 days'),
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'member', '00000000-0000-0000-0000-00000000000a', now() - interval '300 days'),
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'viewer', '00000000-0000-0000-0000-00000000000a', now() - interval '200 days'),
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000010', 'member', NULL, now() - interval '10 days'),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000e', 'admin', NULL, now() - interval '80 days'),
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000e', 'admin', NULL, now() - interval '70 days'),
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000f', 'admin', NULL, now() - interval '69 days'),
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000b', 'member', NULL, now() - interval '68 days'),
 ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000011', 'member', '00000000-0000-0000-0000-000000000011', now() - interval '59 days'),
 ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000f', 'member', NULL, now() - interval '50 days'),
 ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000c', 'viewer', NULL, now() - interval '49 days');

-- Active groups: dave points at a group he is not a member of.
UPDATE public.profiles SET group_id = '10000000-0000-0000-0000-000000000001'
WHERE id IN ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b');
UPDATE public.profiles SET group_id = '10000000-0000-0000-0000-000000000002' WHERE id = '00000000-0000-0000-0000-00000000000d';

-- Expenses.
INSERT INTO public.expenses (id, user_id, group_id, title, amount, category, date, notes, receipt_url) VALUES
 ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', NULL, 'Coffee', 10.005, 'food', now() - interval '3 days', NULL, NULL),
 ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', NULL, repeat('x', 200), 0.01, 'Groceries', now() - interval '2 days', repeat('n', 600), 'not a url'),
 ('20000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000b', NULL, '  padded title  ', 99999.99, ' TRANSPORT ', now() + interval '400 days', NULL, NULL),
 ('20000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000c', NULL, 'Max amount', 999999999.99, '', now() - interval '5 years', '', NULL),
 ('20000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', 'Rent', 1000.00, 'Housing', now() - interval '20 days', NULL, NULL),
 ('20000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', 'Dinner', 100.00, 'Dining', now() - interval '15 days', NULL, NULL),
 ('20000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-00000000000d', '10000000-0000-0000-0000-000000000001', 'Paid by a former member', 33.33, 'Utilities', now() - interval '30 days', NULL, NULL),
 ('20000000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000004', 'Small group expense', 5.00, 'Other', now() - interval '40 days', NULL, NULL),
 ('20000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-00000000000f', '10000000-0000-0000-0000-000000000005', 'Sushi', 1234.00, 'Food', now() - interval '4 days', NULL, NULL),
 ('20000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000001', 'Paid by a viewer', 10.00, 'Shopping', now() - interval '1 days', NULL, NULL),
 ('20000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000e', NULL, 'Tiny', 0.01, 'Personal', now(), NULL, NULL),
 ('20000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003', 'Two admins expense', 10.00, 'Food', now() - interval '1 day', NULL, NULL),
 ('20000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-00000000000a', NULL, repeat('a', 119) || ' ' || repeat('b', 80), 1.00, 'Other', now() - interval '1 day', repeat('n', 499) || ' ' || repeat('m', 20), NULL);

-- Settlements.
INSERT INTO public.settlements (id, group_id, payer_id, payee_id, amount, date, notes) VALUES
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a', 50.00, now() - interval '5 days', repeat('s', 300)),
 ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-00000000000a', 0.01, now() - interval '6 days', NULL),
 ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000a', 999.99, now() - interval '7 days', ''),
 ('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000f', 12.00, now() - interval '1 days', NULL);

-- Invitations (plaintext tokens, as the old schema stored them). Invitation ...0a was sent by bob,
-- who is a member (not the admin) of 'Flat 4B'.
INSERT INTO public.group_invitations (id, group_id, inviter_id, email, role, token, status, expires_at, accepted_at) VALUES
 ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Newbie@Example.com', 'member', 'legacytokenpending1', 'pending', now() + interval '5 days', NULL),
 ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'newbie@example.com', 'viewer', 'legacytokenpending2', 'pending', now() + interval '6 days', NULL),
 ('40000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', ' late@example.com ', 'admin', 'legacytokenpendingadmin', 'pending', now() - interval '1 day', NULL),
 ('40000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'bob@example.com', 'member', 'legacytokenaccepted', 'accepted', now() - interval '290 days', now() - interval '300 days'),
 ('40000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'x@example.com', 'member', 'legacytokendeclined', 'declined', now() - interval '100 days', NULL),
 ('40000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'y@example.com', 'viewer', 'legacytokenexpired', 'expired', now() - interval '200 days', NULL),
 ('40000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'z@example.com', 'member', 'legacytokenrevoked', 'revoked', now() + interval '1 days', NULL),
 ('40000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000e', 'not-an-email', 'member', 'legacytokenbademail', 'pending', now() + interval '3 days', NULL),
 ('40000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000e', repeat('a', 300) || '@example.com', 'member', 'legacytokenlongemail', 'pending', now() + interval '3 days', NULL),
 ('40000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'carol@example.com', 'member', 'legacytokenmemberinvite', 'pending', now() + interval '3 days', NULL),
 ('40000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000f', 'old@example.com', 'member', 'legacytokenold', 'declined', now() - interval '200 days', NULL);
UPDATE public.group_invitations SET created_at = now() - interval '200 days' WHERE id = '40000000-0000-0000-0000-00000000000b';

-- Fixed timestamps, so the check can tell whether the upgrade rewrote them.
ALTER TABLE public.profiles DISABLE TRIGGER USER;
ALTER TABLE public.groups DISABLE TRIGGER USER;
ALTER TABLE public.expenses DISABLE TRIGGER USER;
UPDATE public.profiles SET created_at = '2025-01-01 00:00:00+00', updated_at = '2025-01-02 00:00:00+00';
UPDATE public.groups SET created_at = '2025-01-01 00:00:00+00', updated_at = '2025-01-02 00:00:00+00';
UPDATE public.expenses SET created_at = '2025-01-01 00:00:00+00', updated_at = '2025-01-02 00:00:00+00';
ALTER TABLE public.profiles ENABLE TRIGGER USER;
ALTER TABLE public.groups ENABLE TRIGGER USER;
ALTER TABLE public.expenses ENABLE TRIGGER USER;

COMMIT;
