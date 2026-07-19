# TeeCircle 2.0 migrations

These migrations are additive to TeeCircle's existing production schema. They intentionally do not recreate the legacy schema from handwritten client types or replay a schema dump over linked data.

`20260718173654_tee_circle_legacy_baseline_contract.sql` is the ordered production marker. It makes no schema or data changes: it fail-fast checks the MCP-audited Expo tables, enum-backed rounds and responses, profile-backed foreign keys, RLS, legacy functions/triggers/view, the audited empty public-table Realtime state, and the absence of a partial native-v2 install. Apply the marker normally so a successful check is recorded in Supabase migration history before migration 001. The marker is an assertion, never a legacy-schema replay.

`supabase/tests/fixtures/verified_legacy_schema.sql` is the reviewed, production-shaped executable representation of that audited baseline for disposable local tests. It is test-only—not a production migration, dump, or restoration source—and must never be applied or marked as applied on a linked project. The local runner applies the no-op marker to the fixture, verifies the fixture remains unchanged, and only then applies native-v2 migrations. Do not use `db push` against production from an unreviewed checkout.

The migration files intentionally do not contain explicit `BEGIN`/`COMMIT`
statements. Supabase CLI appends the migration-history insert to the same batch;
leaving transaction-control statements inside a file would allow its DDL to
commit before that ledger row. The local SQL runner uses `psql -1`, and
`supabase/tests/run-cli-migration-atomicity.sh` pins CLI v2.109.1 to verify both
the exact ledger versions and rollback of a deliberately failing migration.

Migration order:

0. No-op production legacy-baseline contract marker. Execute and record it
   normally; never mark it applied without running its assertions.
1. Additive tables, constraints, consistency triggers, private jobs, and runtime flags.
2. RLS and table privileges.
3. Authenticated configuration commands.
4. Roster, lifecycle, and atomic score commands.
5. Read models, legacy conversion, invitations, and public-preview service APIs.
6. Extension credentials, device/ActivityKit registrations, purchase verification, ownership transfer, and worker APIs.
7. Messages-only service APIs.
8. Authenticated invite discovery and atomic roster-seat acceptance.
9. Authenticated owner-scoped reusable course-card read model.
10. Native edit/delete commands, account-deletion blockers, hardened legacy deletion, and Realtime snapshot publication.
11. Release-integrity permissions, atomic lifecycle commands, append-only snapshots, scoped extension/purchase invariants, and repair/service RPCs.
12. One-shot invite responses, purchase-environment provenance, sanitized entitlement reads, cancellable/global purchase intents, and revision-leased Live Activity delivery.
13. JWT-bound RLS authorization helpers and column-safe roster reads that keep claimed account IDs private.
14. Pilot-aware sanitized unlock state for the app and Messages without exposing purchase evidence.
15. Production-schema compatibility and a restrictive boundary between native trip rounds and the legacy Expo round/scorecard model.
16. Hosted-Supabase function ACL normalization: anonymous callers receive no
    native/private RPC access, authenticated clients receive only the reviewed
    app commands, and `service_role` receives only the reviewed worker APIs.

Hosted Supabase grants `EXECUTE` on newly created functions to API roles through
the `postgres` default privileges. Every future migration that creates a new
function must either repeat migration 16's revoke-and-allowlist normalization
or first replace those hosted default privileges through a separately reviewed
compatibility migration.

Migration 11 commits a secret-free database repair primitive but deliberately
does not assume that `pg_cron` is installed on every environment. On the linked
Supabase project, schedule the following once per minute after confirming the
extension is enabled:

```sql
select cron.schedule(
  'teecircle-enqueue-missing-snapshots-v1',
  '* * * * *',
  'select tee_internal.enqueue_missing_trip_snapshot_jobs_v1()'
);
```

This job only restores missing outbox rows. The scheduled
`recompute-trip-snapshot-v1` Edge invocation still leases and computes those
rows; keep its service credentials in Supabase Secrets rather than SQL.

Migration 12 adds `sandbox_purchases_enabled` with a fail-closed default of
`false`. Enable it only for a bounded TestFlight acceptance window, then turn it
off and verify it is off before any App Store production rollout. Sandbox
entitlements remain auditable but are not treated as unlocked while the flag is
off; production entitlements are always eligible.

Migration 14 keeps the app and Messages DTOs aligned with the server gate: when
`purchases_required` is disabled for a bounded pilot, trips report effectively
unlocked without creating or exposing entitlement evidence. The flag's
production default remains `true`; re-enable and verify it before the paid
public rollout.

Migration 15 keeps native trip rounds out of every legacy discovery, response,
locking, invitation, scorecard, and handicap-differential path. Native round
ownership remains trip/roster based, so their nullable legacy `created_by`
column is intentionally left empty. Legacy rounds retain their existing Expo
behavior and view column contract. Account deletion remains fail-closed.

The audited linked project already has an empty `supabase_realtime` publication
with `puballtables = false`. Migration 10 idempotently adds only
`trip_leaderboard_snapshots`; it does not publish a legacy table. The actual
linked publication membership must still be captured and reviewed before
applying these migrations; the test fixture is not a substitute for that
inventory.

Native account deletion intentionally remains an owner-gated checkpoint. A
production-safe implementation requires the actual linked legacy FK inventory,
Supabase Auth Admin deletion, Storage ownership cleanup, and external-provider
cleanup. Migration 10 does not loosen attribution FKs or claim to hard-delete an
Auth user. It only returns active-trip blockers and makes the legacy Expo RPC
fail closed when any native trip membership exists.
