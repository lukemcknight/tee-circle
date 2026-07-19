# `record-score-v1`

The authenticated main-app score pipeline. Supabase JWT verification is on and
the body must include the original `expectedScoreRevision`, played `strokes`
(excluding penalties), additive `penalties`, and an idempotency key.

An accepted request atomically writes/audits the score, synchronously persists
the latest canonical `LeaderboardSnapshotV1`, then triggers Live Activity
delivery. Success returns the accepted revision, latest canonical revision and
snapshot, normalized score (including `grossTotal`), and dispatch status.

If the score committed but snapshot computation could not finish, the endpoint
returns retryable `snapshot_updating` with the accepted score identity. Retry
the identical body and idempotency key; the write is replayed without a second
audit event and recomputation follows the trip to its current revision.

Authenticated clients intentionally have no `EXECUTE` privilege on the raw
score RPC, so they cannot bypass this pipeline.
