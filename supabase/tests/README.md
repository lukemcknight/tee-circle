# Local TeeCircle v2 SQL tests

Run the complete migration and SQL behavior suite against a new disposable
PostgreSQL cluster:

```sh
supabase/tests/run-local-v2.sh
```

PostgreSQL 15 or 16 command-line tools must be on `PATH`. The runner creates a
temporary cluster, applies the test fixture followed by every ordered migration,
runs the contract plus core, edit/delete, and release-integrity behavior suites,
and removes the cluster on exit. It never uses a linked Supabase project or
production credentials.

`fixtures/verified_legacy_schema.sql` is test-only. It represents only the
legacy columns and FK behaviors needed by these tests. It is not the missing
production baseline and must never be applied to, repaired into, or marked as
history for the linked TeeCircle project. Before production migration, capture
and review the real linked schema, RLS policies, functions, triggers, Realtime
publication membership, Auth references, and Storage dependencies as described
in `supabase/migrations/README.md`.
