# Exevra

**Expense & Split Tracker**: track your own spending, share costs with a group, settle up, and
ask an assistant about your money.

Exevra is a Flutter app for Android phones (iOS is planned) backed by Supabase. It is built for
India first (INR and Indian number formatting by default) and also supports other common
currencies. The interface is designed for phones in portrait.

Designed & developed by Bharat Sharma.

## Features

- **Personal expenses.** Add, edit and delete expenses with a title, amount, currency,
  category, date and time, and an optional note.
- **Groups with equal splits.** Create a group, invite people by email or with an invite code,
  and add shared expenses. Each group expense is split equally among the group's members at the
  time it is added. Members can be admins, members or read-only viewers.
- **Balances and settlements.** See who owes whom, with suggested transfers to settle up. A
  payment someone records counts only after the person who received it confirms it, and either
  side can void a mistake.
- **Insights.** Spending by category and over time (week, month or year), calculated in your
  own time zone.
- **AI assistant.** Ask questions about your spending in plain language. Answers come from
  Anthropic's Claude, with Google's Gemini as a fallback. The assistant is off until you agree to
  share a spending summary, and its answers are general information, not financial advice.
- **App lock.** Optional fingerprint, face or device-credential lock. The app content is hidden
  in the app switcher while locked.
- **Light and dark themes.** Follows the system setting, or pick one.

## Screenshots

_Screenshots will be added before the first public release._

## Architecture

| Layer | Technology |
| --- | --- |
| App | Flutter (Dart), Riverpod for state, go_router for navigation |
| Database | Supabase Postgres with row-level security on every table |
| Business rules | Postgres functions (RPCs) for anything that must be atomic or checked on the server: groups and membership, invitations, splits, balances, settlements, insights, AI quota and account deletion |
| Server-side code | Supabase Edge Functions (Deno): `ai-chat`, `send-invite`, `delete-account` |
| Auth | Supabase Auth: email and password (with email codes for verification and password reset), Google sign-in; Sign in with Apple is prepared for iOS |
| Email | Resend, for group invitations (and, optionally, for auth email through Supabase SMTP settings) |
| Crash reporting | Sentry, off unless a DSN is configured; personal data is scrubbed before sending |

The app holds no secrets. It only knows the Supabase URL and the public anon key, and everything
it can read or change is limited by row-level security. Keys for the AI providers and for email
live in Supabase secrets and are used only by the Edge Functions.

```text
Flutter app ──(anon key + user session)──► Supabase
                                            ├─ Postgres (RLS, RPCs)
                                            └─ Edge Functions
                                                 ├─ ai-chat ────────► Anthropic (Claude), then Google (Gemini)
                                                 ├─ send-invite ────► Resend
                                                 └─ delete-account
```

## Local setup

Requirements:

- Flutter **3.44.x** (3.44.8 in CI; Dart 3.12)
- JDK 21 and the Android SDK (for Android builds)
- Docker, the Supabase CLI **3.1** and Deno **2.x** (for the local backend)

```sh
git clone <this repository>
cd <repository folder>
flutter pub get

# Build configuration (gitignored). Fill in your Supabase URL and anon key.
cp config/dev.example.json config/dev.json

flutter run --dart-define-from-file=config/dev.json
```

All configuration is read at build time with `--dart-define-from-file`. The keys are described in
[`config/README.md`](config/README.md):

| Key | Required | Purpose |
| --- | --- | --- |
| `SUPABASE_URL` | yes | Your project URL |
| `SUPABASE_ANON_KEY` | yes | The anon (publishable) key, never the service-role key |
| `APP_LINK_HOST` | no | Host for invite links (default `exevra.app`) |
| `SENTRY_DSN` | no | Crash reporting; empty turns it off |
| `GOOGLE_WEB_CLIENT_ID` | no | Google sign-in (web OAuth client ID) |
| `GOOGLE_IOS_CLIENT_ID` | no | Google sign-in on iOS |
| `APP_ENV` | no | Environment name on crash reports (`development`, `production`) |

A release build with missing or placeholder values shows a "Service unavailable" screen instead of
running against the wrong backend.

## Supabase (local)

The schema lives in `supabase/migrations/` and is tested with pgTAP in `supabase/tests/`. See
[`supabase/README.md`](supabase/README.md) and
[`supabase/functions/README.md`](supabase/functions/README.md) for details.

```sh
supabase start -x studio,imgproxy,logflare,vector,supavisor,storage-api
supabase db reset          # apply every migration from scratch
supabase test db           # run the pgTAP tests

# Edge Functions with local secrets (gitignored)
cp supabase/functions/.env.example supabase/functions/.env
supabase functions serve --env-file supabase/functions/.env
```

`supabase status` prints the local API URL and anon key. To run the app against the local stack
on the Android emulator, put `"SUPABASE_URL": "http://10.0.2.2:54321"` and that anon key in a
`config/local.json` (gitignored) and run with `--dart-define-from-file=config/local.json`. Plain
`http` is accepted only for local addresses in debug builds. Emails sent by the local stack (sign-up
codes, password reset) are caught by the local mail viewer; `supabase status` shows its address.

## Supabase (hosted)

Supabase CLI 3 commands act on the local stack unless you pass `--remote`.

```sh
supabase login
supabase link --project-ref <project-ref>

# 1. Back up the hosted database (keep the files outside the repository).
supabase db dump --remote -f ~/exevra-backups/schema.sql
supabase db dump --remote --data-only -f ~/exevra-backups/data.sql

# 2. Drift check: compare the hosted schema with the baseline migration only.
supabase start
supabase db reset --version 20261115000000     # local database at the baseline
supabase db diff --from local --to remote --schema public
#    No output (or only cosmetic differences) means no drift. Resolve anything else first.
supabase db reset                               # back to all migrations

# 3. Mark the baseline as already applied (the hosted database was created from it).
supabase migration repair --remote --status applied 20261115000000

# 4. Apply the remaining migrations.
supabase db push --remote --dry-run
supabase db push --remote
```

`supabase db diff` only reads the hosted database. (`supabase db pull --remote` can also show
drift, but in CLI 3 it records the pulled file in the hosted migration history, which then has
to be reverted with `supabase migration repair --remote --status reverted <version>`.)

```sh
# 5. Server secrets (gitignored file; same names as supabase/functions/.env.example).
cp supabase/functions/.env.example supabase/.env.secrets
#    Fill in the production values (AI_DAILY_QUOTA=20 for launch), then:
supabase secrets set --env-file supabase/.env.secrets

# 6. Deploy the functions.
supabase functions deploy ai-chat send-invite delete-account
```

Auth settings (site URL, redirect URLs, SMTP, providers, password policy, rate limits) are set in
the Supabase dashboard; `supabase/README.md` lists the values that must match
`supabase/config.toml`. The app's redirect URLs are `com.exevra.app://auth-callback` and
`https://<APP_LINK_HOST>/auth/callback`.

## AI provider status

The assistant runs only on the server, in the `ai-chat` Edge Function. The app never talks to an
AI provider directly and holds no AI keys.

- **Claude first, Gemini as fallback.** Each answer comes from exactly one provider. If Claude
  fails or sends nothing within 12 seconds, the function switches to Gemini before any text is
  shown. Once text has started, it never switches; a failure ends the answer as "interrupted"
  with a Retry option. The app shows which model answered.
- **Consent and data.** Nothing is sent until the user turns the assistant on. The function then
  sends a summary of the user's own spending (their share of group expenses only) and the recent
  conversation. Logs record provider, timing and token counts, never message text or user details.

Secrets (set with `supabase secrets set`):

| Secret | Default | Notes |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | none | Claude. At least one provider key is required. |
| `GEMINI_API_KEY` | none | Gemini fallback. |
| `CLAUDE_MODEL` | `claude-haiku-5-5` | Set to `claude-sonnet-5-5` for stronger answers at a higher cost. |
| `GEMINI_MODEL` | `gemini-3.8-flash` | |
| `AI_DAILY_QUOTA` | `50` | Questions per user per UTC day. The launch setting is `20`. |
| `AI_PER_MINUTE` | `6` | Questions per user per minute. |

Change the model or quota without a redeploy:

```sh
supabase secrets set CLAUDE_MODEL=claude-sonnet-5-5 AI_DAILY_QUOTA=20
```

To see what the function is doing, open **Edge Functions → ai-chat → Logs** in the dashboard, or
use the CLI (`supabase logs sources --remote` lists the services you can filter on):

```sh
supabase logs --remote --search ai-chat --since 30m
```

Each request writes one JSON line with `provider`, `model`, `status`, `ttft_ms`, `latency_ms`
and token counts. A run of `provider: "gemini"` lines means Claude is failing; a run of
`status: "failed"` means both providers are.

## Security notes

- The app contains no secrets: only the Supabase URL and anon key, which are public by design.
  Never put a service-role key, AI key or email key in `config/*.json`.
- Server secrets live in Supabase secrets. The local files that hold them
  (`supabase/functions/.env`, `supabase/.env.secrets`) and `config/*.json` (except the example)
  are gitignored.
- If a key has ever been in a local `.env` file or in a build, treat it as exposed and rotate it.
- Row-level security is on for every table. Writes that need checks (membership, invitations,
  settlements, account deletion) go through Postgres functions that verify the caller.
- Report security issues privately to support@exevra.app rather than in a public issue.

## App icon and launch screen

The launcher icons and the native launch screen are generated; do not edit the files under
`android/app/src/main/res/` or `ios/Runner/Assets.xcassets/` by hand.

```sh
python3 assets/branding/generate_branding.py   # brand images in assets/branding/ (needs Pillow)
dart run flutter_launcher_icons                # Android adaptive, themed and legacy icons; iOS icons
dart run flutter_native_splash:create          # light and dark launch screens (Android 12+ included)
```

The settings for both tools are in `pubspec.yaml`. Only rerun the Python script when the source
artwork in `assets/icons/app_icon.png` changes.

## Build and release

```sh
# Debug run on a device or emulator
flutter run --dart-define-from-file=config/dev.json

# Release APK for beta testers (sideloaded)
flutter build apk --release --dart-define-from-file=config/prod.json \
  --obfuscate --split-debug-info=build/symbols \
  --extra-gen-snapshot-options=--save-obfuscation-map=build/app/obfuscation.map.json

# App bundle for Google Play
flutter build appbundle --release --dart-define-from-file=config/prod.json \
  --obfuscate --split-debug-info=build/symbols \
  --extra-gen-snapshot-options=--save-obfuscation-map=build/app/obfuscation.map.json
```

Outputs are in `build/app/outputs/flutter-apk/` and `build/app/outputs/bundle/release/`. Keep
`build/symbols` and `build/app/obfuscation.map.json` for each release (outside the repository):
without them, obfuscated crash stack traces cannot be read. The app bundle also carries native
symbol tables for Play Console.

When crash reporting is on, upload both to Sentry after each release build (settings in the
`sentry:` section of `pubspec.yaml`; the auth token is never committed):

```sh
SENTRY_ORG=<org> SENTRY_AUTH_TOKEN=<token> dart run sentry_dart_plugin \
  --sentry-define=release=com.exevra.app@<version>+<build>
```

Release builds are signed with your upload key, configured in `android/key.properties`
(gitignored, never committed). Start from the example:

```sh
cp android/key.properties.example android/key.properties
```

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Create the upload key once and back it up somewhere safe:

```sh
keytool -genkeypair -v -keystore ~/keys/exevra-upload.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias upload
```

Google Play re-signs bundles with its own app-signing key (Play App Signing). An APK you
sideload is signed with your upload key instead, so testers must uninstall it before installing
the Play version.

## Testing

```sh
flutter test                         # unit, widget and golden tests
flutter test --update-goldens        # regenerate goldens (on Linux, to match CI)

cd supabase/functions && deno test -A  # Edge Function tests (no network or database needed)

supabase test db                     # pgTAP tests against the local stack

# End-to-end on an emulator against the local stack
flutter test integration_test --dart-define-from-file=config/local.json
```

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every pull request and on pushes to
`main`:

- **Flutter**: formatting, `flutter analyze` and `flutter test` (goldens included)
- **Edge Functions**: `deno fmt --check`, `deno lint` and `deno test`
- **Database**: starts the local Supabase stack, applies every migration and runs the pgTAP tests
- **Android release bundle**: builds an obfuscated, signed release app bundle with a throwaway key
  and placeholder configuration, and keeps it as a build artifact for 7 days
- **iOS (no codesign)**: a no-codesign build on macOS, turned off until iOS ships

CI uses no repository secrets.

## Project structure

```text
lib/
  core/        configuration, logging, routing, theme, platform helpers, shared utilities
  features/    one folder per area: auth, dashboard, expenses, insights, chat, profile, …
  models/      data classes
  providers/   Riverpod providers and notifiers
  services/    access to Supabase and Edge Functions
test/          unit, widget and golden tests
integration_test/
supabase/
  migrations/  database schema (single source of truth)
  tests/       pgTAP tests
  functions/   Edge Functions (ai-chat, send-invite, delete-account)
  email_templates/
config/        build configuration (only the example is committed)
android/ ios/  platform projects
```

## License

No license has been chosen yet. Until one is added, all rights are reserved.

---

Designed & developed by Bharat Sharma.
