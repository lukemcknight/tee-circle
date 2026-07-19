#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PGPORT="${TEECIRCLE_CLI_TEST_PGPORT:-55437}"
PGROOT="$(mktemp -d "${TMPDIR:-/tmp}/teecircle-cli-pg.XXXXXX")"
PGDATA="$PGROOT/data"
PGSOCKET="$PGROOT/socket"
PGLOG="$PGROOT/postgres.log"
DB_NAME="teecircle_cli_test"
DB_URL="postgresql://postgres@127.0.0.1:${PGPORT}/${DB_NAME}?sslmode=disable"
FAILURE_PROJECT="$PGROOT/failure-project"
FAILURE_VERSION="20260718000100"
CLI=(npx --yes supabase@2.109.1 --agent no --yes)

for command in initdb pg_ctl createdb psql npx; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing command: $command" >&2
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
pg_ctl -D "$PGDATA" \
  -o "-k $PGSOCKET -h 127.0.0.1 -p $PGPORT -c wal_level=logical" \
  -l "$PGLOG" start >/dev/null
createdb -h "$PGSOCKET" -p "$PGPORT" -U postgres "$DB_NAME"

PSQL=(psql "$DB_URL" -v ON_ERROR_STOP=1 -X -Atq)
"${PSQL[@]}" -f "$ROOT/supabase/tests/fixtures/verified_legacy_schema.sql"

"${CLI[@]}" --workdir "$ROOT" migration up \
  --db-url "$DB_URL" --include-all

expected_versions=()
while IFS= read -r version; do
  expected_versions+=("$version")
done < <(
  find "$ROOT/supabase/migrations" -maxdepth 1 -type f -name '*.sql' \
    -exec basename {} \; | sort | cut -d_ -f1
)

actual_versions=()
while IFS= read -r version; do
  actual_versions+=("$version")
done < <(
  "${PSQL[@]}" -c \
    "select version from supabase_migrations.schema_migrations order by version"
)

if [[ "${expected_versions[*]}" != "${actual_versions[*]}" ]]; then
  echo "Supabase CLI migration ledger does not match checked-in versions" >&2
  printf 'expected: %s\n' "${expected_versions[*]}" >&2
  printf 'actual:   %s\n' "${actual_versions[*]}" >&2
  exit 1
fi

mkdir -p "$FAILURE_PROJECT/supabase/migrations"
cp "$ROOT/supabase/config.toml" "$FAILURE_PROJECT/supabase/config.toml"
cp "$ROOT"/supabase/migrations/*.sql "$FAILURE_PROJECT/supabase/migrations/"
cp "$ROOT/supabase/tests/fixtures/cli_atomicity_failure.sql" \
  "$FAILURE_PROJECT/supabase/migrations/${FAILURE_VERSION}_cli_atomicity_failure.sql"

if "${CLI[@]}" --workdir "$FAILURE_PROJECT" migration up \
  --db-url "$DB_URL" --include-all >/dev/null 2>&1; then
  echo "Intentional CLI atomicity failure unexpectedly succeeded" >&2
  exit 1
fi

if [[ "$("${PSQL[@]}" -c \
  "select to_regclass('public.cli_atomicity_must_rollback') is null")" != "t" ]]; then
  echo "Failed CLI migration left its schema change committed" >&2
  exit 1
fi

if [[ "$("${PSQL[@]}" -c \
  "select count(*) from supabase_migrations.schema_migrations where version = '${FAILURE_VERSION}'")" != "0" ]]; then
  echo "Failed CLI migration left a migration-history row" >&2
  exit 1
fi

echo "Supabase CLI v2.109.1 ledger and failure atomicity test passed."
