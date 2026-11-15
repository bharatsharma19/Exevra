# Supabase backend

The database schema lives in **`migrations/`** and is the single source of truth. Each migration is
idempotent and safe to apply to a database that already holds user data.

| Path | Purpose |
|---|---|
| `migrations/` | Ordered SQL migrations (`YYYYMMDDHHMMSS_name.sql`). Never edit one that has been applied to the hosted project; add a new one. |
| `tests/` | pgTAP tests (access control, money, splits, balances, settlements, insights, AI, account deletion, schema-wide checks), run with `supabase test db`. |
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
supabase stop
```

CLI v3 commands target the local stack unless `--remote` is given.

## Hosted project

The hosted database was originally built by running the old `schema.sql` by hand. The first
migration (`20261115000000_baseline.sql`) reproduces that file exactly, so the hosted project only
needs to record it as applied before the remaining migrations are pushed:

```sh
supabase link --project-ref <project-ref>
supabase db pull --remote --schema public   # writes the hosted schema as a new migration file
# Compare that file with migrations/20261115000000_baseline.sql and resolve any drift, then delete
# the pulled file (it must not be pushed).
supabase migration repair --remote --status applied 20261115000000
supabase db push --remote --dry-run         # lists the migrations after the baseline
supabase db push --remote
```

Take a backup (or enable PITR) before pushing. After pushing, run the Security and Performance
Advisors in the dashboard.

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
role and then `auth.admin.deleteUser(user_id)`. The function hands over or deletes the groups the user
administers, voids their pending settlements, and deletes their memberships, personal expenses, AI
data, invitations and profile. Shared group history stays and shows the user as "Former member". A
trigger on `auth.users` runs the same function before any user is deleted, so deleting a user from the
dashboard is also safe for the other members of their groups.

### Auth settings to mirror in the dashboard

Site URL `com.exevra.app://auth-callback`; redirect URLs `com.exevra.app://auth-callback` and
`https://exevra.app/auth/callback`; email confirmations on; minimum password length 8 with lower,
upper case letters and digits; phone provider off; custom SMTP for auth emails; the three templates in
`email_templates/`.
