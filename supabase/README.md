# Supabase backend

The database schema lives in **`migrations/`** and is the single source of truth. Each migration is
idempotent and safe to apply to a database that already holds user data.

| Path | Purpose |
|---|---|
| `migrations/` | Ordered SQL migrations (`YYYYMMDDHHMMSS_name.sql`). Never edit one that has been applied to the hosted project; add a new one. |
| `tests/` | pgTAP tests (access control, money, splits, balances, settlements, insights, AI, account deletion, schema-wide checks), run with `supabase test db`. |
| `upgrade_check/` | Upgrade-path check: legacy data on the baseline schema, then every later migration (`upgrade_check/run.sh`, local only). |
| `config.toml` | Local stack configuration (Supabase CLI v3). Hosted auth settings are configured in the dashboard. |
| `email_templates/` | Auth email templates (confirmation, password recovery code, email change). |
| `seed.sql` | Local-only seed data (applied by `supabase db reset`). |
| `schema.sql` | Comment-only pointer to this file (the project README still links to it). Not a schema. |

## Local development

Requires Docker and the Supabase CLI v3.

```sh
supabase start -x studio,imgproxy,logflare,vector,supavisor,storage-api
supabase db reset     # drop the local database and apply every migration from scratch
supabase test db      # run the pgTAP tests in supabase/tests/
supabase db advisors  # security and performance advisors against the local database
supabase/upgrade_check/run.sh  # upgrade path from the baseline with legacy data (ends with a clean reset)
supabase stop
```

CLI v3 commands target the local stack unless `--remote` is given.

## Hosted project

The hosted database was originally built by running the old `schema.sql` by hand. The first
migration (`20261115000000_baseline.sql`) reproduces that file exactly, so the hosted project only
needs to record it as applied before the remaining migrations are pushed.

### 1. Plan the release order (old app builds stop working)

The migrations change the API the app uses: amounts become `amount_minor` integers, membership,
settlement and invitation writes go through RPCs only, and `groups` is readable by listed columns
only. No app build works against both schemas. As soon as the push finishes, builds released before
this change fail on expense and group writes (for example an insert with `amount` fails because the
column no longer exists, and `select('*')` on `groups` is refused). Treat the push as a cutover:

1. Have the new build approved in Play Console and ready to roll out (staged rollout held, or
   internal track promoted at the cutover time); prepare a forced-update prompt for older versions.
2. Pick a quiet window, take a backup (or confirm PITR is on).
3. Push the migrations (steps 2 to 4 below).
4. Roll the new build out to everyone and enable the forced update immediately afterwards.

### 2. Check for drift (read-only)

Compare the hosted `public` schema with the baseline. These commands do not write to the hosted
migration history. (Do not use `supabase db pull` for this: in CLI v3 it writes a migration with the
difference to the local migrations and records it in the hosted history.)

```sh
supabase link --project-ref <project-ref>
supabase db dump --remote --schema public -f /tmp/hosted_public.sql
supabase db reset --version 20261115000000 --no-seed   # local database = baseline only
supabase db dump --schema public -f /tmp/baseline_public.sql
diff -u /tmp/baseline_public.sql /tmp/hosted_public.sql
supabase db reset                                       # back to the full local schema
```

Known drift from older `schema.sql` versions (`group_members` foreign keys to `auth.users`, a
`'viewer'` role default) is normalised by the migrations. Resolve anything else before pushing.

### 3. Pre-flight data check

Amounts are converted to minor units without clamping; an amount that would become less than one
minor unit or more than 100,000,000,000 stops the push with `legacy_amount_out_of_range` (listing the
row ids). Over-long or padded text (titles, notes, names) needs no action: it is trimmed and cut to
the new limits, with no whitespace left at the cut. Each migration is its own transaction, so a stop
part-way leaves the earlier ones applied: run this query in the SQL editor first and correct or
delete the rows it lists deliberately:

```sql
with conv as (
    select 'expenses' as source, e.id, e.amount,
           upper(btrim(coalesce(case when e.group_id is null then po.currency else pa.currency end, 'INR'))) as currency
    from public.expenses as e
    left join public.profiles as po on po.id = e.user_id
    left join public.groups as g on g.id = e.group_id
    left join public.profiles as pa on pa.id = g.admin_id
    union all
    select 'settlements', s.id, s.amount, upper(btrim(coalesce(pa.currency, 'INR')))
    from public.settlements as s
    join public.groups as g on g.id = s.group_id
    left join public.profiles as pa on pa.id = g.admin_id
)
select source, id, amount, currency
from conv
where round(amount * case when currency in ('JPY', 'KRW') then 1 else 100 end) not between 1 and 100000000000;
```

Two further clean-ups need no action but are worth knowing (each is reported as a `NOTICE` in the
migration output, with a count):

- Old amounts are `NUMERIC(12,2)`, so two-decimal currencies convert exactly. An amount with a
  fractional part in a zero-decimal currency (JPY, KRW) is rounded half away from zero to whole units
  (1000.50 JPY becomes 1001, 999.49 JPY becomes 999), `legacy_zero_decimal_rounded`. To correct them
  by hand first, list them with the query above, replacing the `where` clause by
  `where currency in ('JPY', 'KRW') and amount <> trunc(amount)`.
- An expense dated `infinity` or `-infinity` gets its `created_at` as date
  (`legacy_infinite_spent_at`). Other dates before 2000 or more than a year ahead are kept
  (`legacy_spent_at_out_of_range` counts them); new and changed dates must lie in that range.

### 4. Record the baseline and push

```sh
supabase migration repair --remote --status applied 20261115000000
supabase db push --remote --dry-run         # lists the migrations after the baseline
supabase db push --remote
```

Default privileges: from the second migration on, tables, sequences and functions created by
`postgres` in `public` grant nothing to `anon` or `authenticated`, and functions `postgres` creates in
any schema are not executable by `PUBLIC`. Every privilege the app needs is granted explicitly in the
migration that creates the object, so a new table or function in a later migration needs its own
`GRANT`. (`supabase_admin`'s default privileges cannot be changed by `postgres` on the hosted project;
only platform operations create objects as that role.)

After pushing, run the Security and Performance Advisors in the dashboard and confirm that client
roles cannot create temporary objects (both values must be `false`):

```sql
select has_database_privilege('authenticated', current_database(), 'TEMP'),
       has_database_privilege('anon', current_database(), 'TEMP');
```

### Scheduled cleanup

Two maintenance functions are callable by the service role only:

| Function | What it does | pg_cron job |
|---|---|---|
| `public.purge_old_invitations()` | marks overdue invitations as expired, deletes answered or expired invitations older than 90 days and old invite-code attempt records | `purge-old-invitations`, daily 03:17 UTC |
| `public.purge_old_ai_usage()` | deletes AI usage records older than 180 days | `purge-old-ai-usage`, daily 03:37 UTC |

If the `pg_cron` extension is enabled when the migrations run, the jobs are scheduled automatically.
Otherwise enable `pg_cron` (Dashboard > Database > Extensions) and run:

```sql
select cron.schedule('purge-old-invitations', '17 3 * * *', 'select public.purge_old_invitations();');
select cron.schedule('purge-old-ai-usage', '37 3 * * *', 'select public.purge_old_ai_usage();');
```

### Account deletion

The `delete-account` Edge Function calls `public.prepare_account_deletion(user_id)` with the service
role and then `auth.admin.deleteUser(user_id)`. A call for a user who is already gone (a retry after
`deleteUser` succeeded) changes nothing and returns `already_deleted: true`. The function hands over
or deletes the groups the user
administers, voids their pending settlements, and deletes their memberships, personal expenses, AI
data, invitations and profile. Shared group history stays and shows the user as "Former member". A
trigger on `auth.users` runs the same function before any user is deleted, so deleting a user from the
dashboard is also safe for the other members of their groups.

### Auth settings to mirror in the dashboard

Site URL `com.exevra.app://auth-callback`; redirect URLs `com.exevra.app://auth-callback` and
`https://exevra.app/auth/callback`; email confirmations on; minimum password length 8 with lower,
upper case letters and digits; phone provider off; custom SMTP for auth emails; the three templates in
`email_templates/`.
Email OTP length 8 and email OTP expiry 900 s (Authentication > Providers > Email), matching
`config.toml`; consider turning on CAPTCHA protection (Authentication > Attack Protection) for
sign-up, sign-in and password reset.
