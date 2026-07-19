#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PGPORT="${TEECIRCLE_TEST_PGPORT:-55432}"
PGROOT="$(mktemp -d "${TMPDIR:-/tmp}/teecircle-v2-pg.XXXXXX")"
PGDATA="$PGROOT/data"
PGSOCKET="$PGROOT/socket"
PGLOG="$PGROOT/postgres.log"
DB_NAME="teecircle_v2_test"

for command in initdb pg_ctl createdb psql; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing PostgreSQL command: $command" >&2
    exit 1
  fi
done

cleanup() {
  if [[ -f "$PGDATA/postmaster.pid" ]]; then
    pg_ctl -D "$PGDATA" stop -m fast >/dev/null 2>&1 || true
  fi
  rm -rf "$PGROOT"
}
trap cleanup EXIT

mkdir -p "$PGSOCKET"
initdb -D "$PGDATA" -A trust -U postgres --no-locale >/dev/null
pg_ctl -D "$PGDATA" -o "-k $PGSOCKET -p $PGPORT -c wal_level=logical" -l "$PGLOG" start >/dev/null
createdb -h "$PGSOCKET" -p "$PGPORT" -U postgres "$DB_NAME"

PSQL=(psql -h "$PGSOCKET" -p "$PGPORT" -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 -X)
BASELINE_MIGRATION="$ROOT/supabase/migrations/20260718173654_tee_circle_legacy_baseline_contract.sql"
SCHEMA_MIGRATION="$ROOT/supabase/migrations/20260718173955_tee_circle_v2_schema.sql"

"${PSQL[@]}" -f "$ROOT/supabase/tests/fixtures/verified_legacy_schema.sql"

echo "Verifying legacy publication guards"
"${PSQL[@]}" -c \
  "alter publication supabase_realtime add table public.rounds" >/dev/null
if "${PSQL[@]}" -1 -f "$BASELINE_MIGRATION" >/dev/null 2>&1; then
  echo "Baseline marker accepted a published legacy table" >&2
  exit 1
fi
"${PSQL[@]}" -c \
  "alter publication supabase_realtime drop table public.rounds" >/dev/null

"${PSQL[@]}" -c \
  "drop publication supabase_realtime; create publication supabase_realtime for all tables" \
  >/dev/null
if "${PSQL[@]}" -1 -f "$BASELINE_MIGRATION" >/dev/null 2>&1; then
  echo "Baseline marker accepted a FOR ALL TABLES publication" >&2
  exit 1
fi
"${PSQL[@]}" -c \
  "drop publication supabase_realtime; create publication supabase_realtime" \
  >/dev/null

echo "Applying $(basename "$BASELINE_MIGRATION")"
"${PSQL[@]}" -1 -f "$BASELINE_MIGRATION"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_legacy_baseline_contract.sql"

while IFS= read -r migration; do
  if [[ "$migration" == "$BASELINE_MIGRATION" ]]; then
    continue
  fi
  echo "Applying $(basename "$migration")"
  "${PSQL[@]}" -1 -f "$migration"
  if [[ "$migration" == "$SCHEMA_MIGRATION" ]]; then
    "${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_schema_boundary_contract.sql"
  fi
done < <(find "$ROOT/supabase/migrations" -maxdepth 1 -type f -name '*.sql' | sort)

"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_contract.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_function_acl_contract.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_behavior.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_edit_delete_behavior.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_nonmember_captain_commands_behavior.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_release_integrity_behavior.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_production_compat_behavior.sql"
"${PSQL[@]}" -f "$ROOT/supabase/tests/tee_circle_v2_profile_identity_behavior.sql"

echo "TeeCircle v2 local SQL suite passed."
