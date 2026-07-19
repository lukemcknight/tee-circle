# `recompute-trip-snapshot-v1`

Scheduled repair worker for canonical leaderboard snapshots. Requests require
`x-tee-circle-worker-secret: $SNAPSHOT_WORKER_SECRET`. With no trip body it
leases pending outbox jobs; `{ "schemaVersion": 1, "tripId": "...",
"revision": 42 }` repairs one exact revision.

Schedule `enqueue_missing_trip_snapshot_jobs_service_v1()` every minute before
invoking this worker. The database step only recreates missing outbox rows and
needs no HTTP secret; this Edge worker remains the only component that runs the
TypeScript scoring engine. A persisted repair also triggers ActivityKit, while
stale jobs are reported as superseded.
