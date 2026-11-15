#!/usr/bin/env bash
# Upgrade check for the hosted project's path: baseline schema + legacy data -> every later migration.
#
#   1. reset the LOCAL database to the baseline migration and load legacy_fixture.sql
#   2. apply the remaining migrations (supabase migration up)
#   3. run check.sql (pgTAP) against the upgraded data
#   4. re-apply every migration after the baseline (in a rolled-back transaction): idempotency
#   5. compare the upgraded public schema with a fresh `supabase db reset`
#   6. a legacy amount that cannot be stored exactly must stop the upgrade
#      (legacy_amount_out_of_range) instead of being changed
#   7. finish with a clean `supabase db reset`
#
# Local stack only (CLI v3 targets the local database by default). Run from anywhere:
#   supabase/upgrade_check/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/supabase/upgrade_check"
SB="${SUPABASE_BIN:-supabase}"
DB="${SUPABASE_DB_CONTAINER:-supabase_db_exevra}"
BASELINE=20261115000000
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$ROOT"

psql_db() { docker exec -i -e PGOPTIONS='-c client_min_messages=warning' "$DB" psql -U postgres -X -q -v ON_ERROR_STOP=1 "$@"; }
step() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

step "Reset to the baseline and load legacy data"
"$SB" db reset --version "$BASELINE" --no-seed >"$WORK/reset.log" 2>&1 || { cat "$WORK/reset.log"; fail "reset to baseline"; }
psql_db <"$HERE/legacy_fixture.sql" >/dev/null

step "Apply the remaining migrations"
"$SB" migration up >"$WORK/up.log" 2>&1 || { cat "$WORK/up.log"; fail "migration up"; }
grep -c '^Applying migration' "$WORK/up.log" | sed 's/^/migrations applied: /'

step "Assertions on the upgraded data"
psql_db -tA <"$HERE/check.sql" >"$WORK/check.out" 2>&1 || { cat "$WORK/check.out"; fail "check.sql did not run"; }
if grep -qE '^(not ok|# Looks like)' "$WORK/check.out"; then
    grep -E '^(not ok|#)' "$WORK/check.out"
    fail "upgrade assertions"
fi
grep -c '^ok' "$WORK/check.out" | sed 's/^/assertions passed: /'

step "Re-apply every migration after the baseline (rolled back)"
{
    echo 'begin;'
    for f in supabase/migrations/*.sql; do
        [ "$(basename "$f" | cut -d_ -f1)" = "$BASELINE" ] && continue
        cat "$f"; echo
    done
    echo 'rollback;'
} | psql_db >/dev/null
echo "re-apply ok"

step "Compare the upgraded schema with a fresh reset"
"$SB" db dump --schema public -f "$WORK/upgraded.sql" >/dev/null 2>&1
"$SB" db reset --no-seed >/dev/null 2>&1
"$SB" db dump --schema public -f "$WORK/fresh.sql" >/dev/null 2>&1
if ! diff -u "$WORK/fresh.sql" "$WORK/upgraded.sql" >"$WORK/schema.diff"; then
    cat "$WORK/schema.diff"
    fail "upgraded schema differs from a fresh install"
fi
echo "schemas identical"

step "An amount that cannot be stored exactly stops the upgrade"
"$SB" db reset --version "$BASELINE" --no-seed >/dev/null 2>&1
psql_db <<'SQL' >/dev/null
-- The first schema.sql had no upper bound on amounts.
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_amount_check;
INSERT INTO auth.users (instance_id, id, aud, role, email, email_confirmed_at, raw_user_meta_data)
VALUES ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1', 'authenticated',
        'authenticated', 'range@example.com', now(), '{}'::jsonb);
INSERT INTO public.expenses (id, user_id, title, amount, category, date)
VALUES ('20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a1', 'Too large', 5000000000.00, 'Other', now());
SQL
if "$SB" migration up >"$WORK/range.log" 2>&1; then
    fail "the upgrade accepted an amount above the supported range"
fi
grep -q 'legacy_amount_out_of_range' "$WORK/range.log" || { cat "$WORK/range.log"; fail "unexpected upgrade error"; }
grep -o '20000000-0000-0000-0000-0000000000a1' "$WORK/range.log" | head -1 | sed 's/^/reported row: /'

step "Clean reset"
"$SB" db reset >/dev/null 2>&1
echo "PASS"
