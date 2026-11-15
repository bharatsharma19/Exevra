# Build configuration

Exevra reads its configuration at compile time with
`--dart-define-from-file`. Nothing is loaded from a bundled `.env` file.

## Local setup

1. Copy the example file. `config/dev.json` is gitignored; never commit it.

   ```sh
   cp config/dev.example.json config/dev.json
   ```

2. Fill in the values from your Supabase project
   (Project settings → API).
3. Run the app with it:

   ```sh
   flutter run --dart-define-from-file=config/dev.json
   ```

Use the same flag for `flutter build`, with a separate file per
environment (for example `config/prod.json`, also gitignored).

## Keys

| Key | Required | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | yes | `https://<project-ref>.supabase.co`. Plain `http` is accepted only for `127.0.0.1`, `localhost` or `10.0.2.2` in debug builds. |
| `SUPABASE_ANON_KEY` | yes | The **anon** (publishable) key. Never use the `service_role` or `sb_secret_` key here; the app refuses to start with one. |
| `APP_LINK_HOST` | no | Host used for shared invite links. Defaults to `exevra.app`. |
| `SENTRY_DSN` | no | Crash reporting DSN (not secret). Empty disables reporting. |
| `GOOGLE_WEB_CLIENT_ID` | no | OAuth web client ID used as the Google sign-in server client ID. Empty hides Google sign-in behind a "not available" message. |
| `GOOGLE_IOS_CLIENT_ID` | no | OAuth iOS client ID. |

## What the client may hold

The app binary only ever contains the Supabase URL and the anon
(publishable) key, which are public by design and protected by row-level
security. AI provider keys, email credentials and any other secrets are
Supabase secrets used by server-side Edge Functions; they must never be
added to these files or to the app.

## Invalid configuration

If a value is missing, malformed or still a placeholder, the app shows a
"Service unavailable" screen instead of starting. Debug builds list the
problems on that screen; release builds show only the friendly message.

## Offline demo (development only)

`flutter run --dart-define=DEMO=true` enables an offline demo for UI work:
without a valid configuration the app runs against an unreachable local
placeholder backend with sample data, and failed sign-ins open a local demo
account. Demo mode is compiled out of release builds.
