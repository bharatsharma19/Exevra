# Exevra Edge Functions

Server-side code that holds the secrets the app must never ship: AI provider keys, the email
provider key and the service-role key.

| Function         | Purpose                                                                |
| ---------------- | ---------------------------------------------------------------------- |
| `ai-chat`        | Streams the in-app money assistant (Claude first, Gemini as fallback). |
| `send-invite`    | Creates a group invitation and emails it.                              |
| `delete-account` | Deletes the caller's account and data (and revokes Apple sign-in).     |
| `_shared`        | Helpers used by every function (not deployed on its own).              |

## Runtime and conventions

- The hosted Edge Runtime is Deno 2.1 compatible. Do not use APIs newer than Deno 2.1.
- Entry points use `Deno.serve`. `index.ts` only wires real dependencies into a pure
  `handler.ts`, which takes its dependencies (env, Supabase client factory, providers, clock) as
  arguments so it can be tested without network access.
- Dependencies use `npm:`/`jsr:` specifiers pinned to exact versions, written inline (for example
  `npm:@supabase/supabase-js@2.118.0`). Code under `_shared` must not rely on bare specifiers,
  because each function is bundled with its own `deno.json`.
- One `deno.json` per function (used by the bundler). There is no `import_map.json`. The root
  `deno.json` here only holds fmt, lint and task settings. Lockfiles are disabled (`"lock": false`)
  because the pins are exact.
- No CORS handling: the only client is the mobile app.
- Logs are one JSON line per request via `_shared/log.ts`. Never log message content, emails, user
  ids, tokens or keys. Field names containing words such as `user`, `email`, `name`, `token`,
  `key`, `message` or `text` are dropped automatically; log `errorName(err)` under `error`.

## Required `supabase/config.toml` entries

`config.toml` is owned by the database workstream; these are the entries the functions need:

```toml
[edge_runtime]
enabled = true
policy = "per_worker"
deno_version = 2

[functions.ai-chat]
enabled = true
verify_jwt = true
import_map = "./functions/ai-chat/deno.json"
entrypoint = "./functions/ai-chat/index.ts"

[functions.send-invite]
enabled = true
verify_jwt = true
import_map = "./functions/send-invite/deno.json"
entrypoint = "./functions/send-invite/index.ts"

[functions.delete-account]
enabled = true
verify_jwt = true
import_map = "./functions/delete-account/deno.json"
entrypoint = "./functions/delete-account/index.ts"
```

`verify_jwt = true` makes the gateway reject requests without a valid JWT. Each function still
verifies the caller with `auth.getUser` before doing any work.

## Secrets

Names are listed in [`.env.example`](./.env.example). `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` are injected by the platform.

```sh
cp supabase/functions/.env.example supabase/functions/.env   # gitignored; fill in values
supabase functions serve --env-file supabase/functions/.env  # local
supabase secrets set --env-file supabase/functions/.env      # hosted project
supabase functions deploy ai-chat send-invite delete-account
```

## Checks

Run from `supabase/functions` (Deno 2.x):

```sh
deno task check   # deno fmt --check && deno lint && deno test
```

Tests use fake dependencies and a mocked `fetch`; they need no network beyond the first download of
pinned packages and never start the local Supabase stack.

## Shared modules (`_shared`)

| Module       | Main exports                                                                                                                                                                                                                  |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `env.ts`     | `EnvSource`, `denoEnv`, `envFromRecord`, `envString`, `envRequired`, `envInt`, `envBaseUrl`, `MissingEnvError`, `readSupabaseEnv`, `readSupabaseAdminEnv`, `readAiEnv`, `readInviteEnv`, `readAppleEnv`, model/quota defaults |
| `http.ts`    | `ErrorCode`, `ERROR_STATUS`, `DEFAULT_ERROR_MESSAGES`, `HttpError`, `jsonResponse`, `errorResponse`, `errorResponseFrom`, `assertMethod`, `readJsonBody`, `isRecord`, `pgErrorKey`, `httpErrorFromPg`                         |
| `auth.ts`    | `bearerToken`, `authenticate`, `createUserClient`, `createAdminClient`, `userClientFactory`, `AuthCapableClient`, `AuthContext`, `AuthUser`                                                                                   |
| `sse.ts`     | `SSE_HEADERS`, `encodeSseEvent`, `encodeSseComment`, `createSseStream` (with `: ping` keep-alives), `sseResponse`, `parseSse`, `SseOverflowError`                                                                             |
| `log.ts`     | `createLogger`, `sanitizeLogFields`, `isSensitiveLogKey`, `errorName`, `newRequestId`, `silentLogger`                                                                                                                         |
| `html.ts`    | `escapeHtml`, `html` (escaping template tag), `SafeHtml`, `trustedHtml`, `toSingleLine`, `safeHttpsUrl`                                                                                                                       |
| `clock.ts`   | `Clock`, `systemClock`, `Timers`, `TimerId`, `systemTimers`                                                                                                                                                                   |
| `testing.ts` | Test-only: `fakeClock`, `fakeTimers`, `streamFromChunks`, `readAllText`, `mockFetch`, `memorySink`                                                                                                                            |

Error responses always look like `{ "error": { "code": "<ErrorCode>", "message": "<friendly>",
"reason"?: "<db business key>" } }`. Codes and statuses: `invalid_request` 400, `unauthorized`
401, `consent_required` 403, `forbidden` 403, `not_found` 404, `method_not_allowed` 405,
`conflict` 409, `too_long` 413, `quota_exceeded` 429, `rate_limited` 429, `internal` 500,
`unavailable` 503.
