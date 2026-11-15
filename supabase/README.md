# Supabase backend

The database schema lives in **`migrations/`** and is the single source of truth. Each migration is
idempotent and safe to apply to a database that already holds user data.

| Path | Purpose |
|---|---|
| `migrations/` | Ordered SQL migrations (`YYYYMMDDHHMMSS_name.sql`). Never edit one that has been applied to the hosted project; add a new one. |
| `tests/` | pgTAP tests for access control and data rules, run with `supabase test db`. |
| `config.toml` | Local stack configuration (Supabase CLI v3). Hosted auth settings are configured in the dashboard. |
| `email_templates/` | Auth email templates (confirmation, password recovery code, email change). |
| `seed.sql` | Local-only seed data (applied by `supabase db reset`). |
| `schema.sql` | Pointer to this file; kept so old links do not mislead. |

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

`public.purge_old_invitations()` (service role only) marks overdue invitations as expired, deletes
answered or expired invitations older than 90 days and clears old invite-code attempt records. If the
`pg_cron` extension is enabled, the invitations migration schedules it daily; otherwise enable
`pg_cron` and run:

```sql
select cron.schedule('purge-old-invitations', '17 3 * * *', 'select public.purge_old_invitations();');
```

### Auth settings to mirror in the dashboard

Site URL `com.exevra.app://auth-callback`; redirect URLs `com.exevra.app://auth-callback` and
`https://exevra.app/auth/callback`; email confirmations on; minimum password length 8 with lower,
upper case letters and digits; phone provider off; custom SMTP for auth emails; the three templates in
`email_templates/`.
