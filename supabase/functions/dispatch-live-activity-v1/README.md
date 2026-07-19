# `dispatch-live-activity-v1`

Worker endpoint for canonical `LeaderboardSnapshotV1` broadcasts. It can be
called with `{ "schemaVersion": 1, "tripId": "...", "revision": 42 }` after
snapshot persistence, or without a trip to scan active subscriptions for newer
snapshots. Requests require `x-tee-circle-worker-secret`.

Server-only configuration:

- `ACTIVITY_WORKER_SECRET`
- `LIVE_ACTIVITY_PUSHES_ENABLED=true` (safe default is disabled)
- `APNS_TEAM_ID=9974PM5L6M`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY` (the `.p8` contents; escaped newlines are accepted)
- `APNS_LIVE_ACTIVITY_TOPIC` (defaults to
  `com.teecircle.app.push-type.liveactivity`)

The database `live_activity_pushes_enabled` runtime flag must also be true.
The environment and database switches are intentionally fail-closed and both
must permit delivery.

Routine updates use APNs priority 5. Lead changes, resolved skins, round
transitions, and finals use priority 10. Completed trips send ActivityKit's
`end` event. Invalid/expired tokens are ended locally, while retryable APNs
errors leave the subscription active for the next scheduled run. The database
leases one canonical revision per subscription at a time, so an older dispatch
cannot overtake a newer one. APNs collapse IDs and nonzero expiration retain the
newest queued update for offline devices; finals are retained for up to 24 hours.
