# TeeCircle 2.0 release runbook

Code can establish the native targets, additive database migrations, functions, tests, and web fallback. The following portal actions require the TeeCircle owner and are release gates rather than code TODOs.

## 1. Preserve and baseline

- [x] Keep the Expo/EAS project buildable at repository root.
- [x] Create local annotated tag `expo-v1.4.0-build9` at the last Expo build-9 baseline.
- [ ] Push that tag to the protected remote after reviewing the native changes.
- [x] Export the linked production Supabase schema, policies, functions, publications, and migration history before applying any new migration.
- [x] Compare that export with the documented legacy baseline. Execute
  `20260718173654_tee_circle_legacy_baseline_contract.sql` normally as the first
  migration so its fail-closed assertions run and its exact version is recorded.
  Never mark it applied without executing it, and never replay the test fixture
  or backup over production.
- [x] Run the additive migration/RLS suite and the pinned Supabase CLI ledger
  and failure-atomicity test against disposable PostgreSQL before production.

Legacy tables and APIs remain available for at least two stable native releases or 90 days, whichever is longer.

## 2. Apple Developer and App Store Connect

For the existing `com.teecircle.app` identifier, enable:

- [x] Sign in with Apple
- [x] Associated Domains (`applinks:teecircle.vercel.app` for the MVP and `applinks:teecircle.app` for the future custom-domain cutover)
- [x] App Groups (`group.com.teecircle.app.shared`)
- [x] Push Notifications
- [x] Live Activities
- [x] Keychain Sharing

- [x] Create/confirm extension identifiers `com.teecircle.app.messages` and
  `com.teecircle.app.widgets`, then regenerate development profiles. A signed
  generic-device build completed on 2026-07-18 with explicit profiles for all
  three targets and the expected app-group/keychain/push entitlements.
- [ ] Create an APNs token restricted according to the team’s key policy. Store
  its key ID, team ID, and private key only in the server secret store.

In App Store Connect:

- [ ] Keep the current TeeCircle app record and upload version `2.0.0`, build `10` or higher.
- [ ] Create consumable `com.teecircle.app.trip_unlock_2999` at USD 29.99.
- [ ] Add the Messages extension and Live Activity disclosures/screenshots to review notes.
- [ ] Explain that sharing and message updates always require explicit user action.

## 3. Supabase

- [x] Populate local CLI configuration from the actual linked project without committing service credentials.
- [x] Inspect active/long-running transactions and waiting locks immediately
  before both production migration groups; both checks were quiet. Every migration has a bounded
  lock/statement timeout and must fail rather than wait indefinitely.
- [x] Use pinned Supabase CLI v2.109.1 for local ledger/atomicity verification,
  then execute all 17 reviewed migrations through Supabase's tracked migration
  API in one
  controlled sequence. Do not deploy native traffic or enable a flag between
  files; migration 015 is the required legacy/native compatibility boundary
  and migration 016 normalizes hosted Supabase function ACLs to the reviewed
  client/server allowlists.
- [x] Verify all 17 exact versions exist in
  `supabase_migrations.schema_migrations`, then run the Expo PostgREST
  `visible_rounds` query including embedded `round_responses → profiles` before
  declaring rollback compatibility healthy.
  The production structural query returned HTTP 200 on 2026-07-18; repeat it
  with a signed-in Expo creator/invitee during physical-device acceptance to
  validate non-empty user-scoped results.
- [x] Deploy the non-payment versioned functions with verification configured
  per endpoint: `record-score-v1` uses gateway JWT verification; the opaque
  Messages session, preview proxy, snapshot worker, and Activity worker perform
  their own scoped authentication. The six deployed functions are
  `record-score-v1`, `score-trip-hole-v1`, `messages-bootstrap-v1`,
  `preview-trip-v1`, `recompute-trip-snapshot-v1`, and
  `dispatch-live-activity-v1`. Do not restore authenticated access to the raw
  score RPC.
- [ ] Deploy `claim-trip-purchase-v1` and `revenuecat-webhook-v1` after the real
  RevenueCat project, app, API, and webhook credentials are available.
- [x] Configure Realtime for snapshot hints, not raw private score broadcasting.
  Production publishes only `public.trip_leaderboard_snapshots`.
- [ ] Run `enqueue_missing_trip_snapshot_jobs_service_v1` every minute, then invoke `recompute-trip-snapshot-v1` with its worker secret to lease/repair pending jobs. Also schedule the no-trip `dispatch-live-activity-v1` scan for retryable APNs delivery.
- [ ] Store APNs, RevenueCat webhook, and service-role secrets server-side.
- [ ] Enable native Apple and Google providers for `com.teecircle.app`.
- [x] Keep the production kill switches off until internal physical-device
  acceptance begins. As of 2026-07-18, native writes, public previews, sandbox
  purchases, and Live Activity pushes remain disabled.

Edge Function secrets/configuration:

- `REVENUECAT_V2_SECRET_API_KEY`, `REVENUECAT_PROJECT_ID`, and `REVENUECAT_APP_ID`
- `REVENUECAT_WEBHOOK_AUTHORIZATION`
- `SNAPSHOT_WORKER_SECRET`
- `ACTIVITY_WORKER_SECRET` and `LIVE_ACTIVITY_PUSHES_ENABLED`
- `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY`, and `APNS_LIVE_ACTIVITY_TOPIC`
- `PUBLIC_PREVIEW_PROXY_SECRET` (the same random 32-byte-or-longer value in
  Vercel and Supabase) and an independent `PUBLIC_RATE_LIMIT_SALT`

The APNs topic defaults to `com.teecircle.app.push-type.liveactivity`. Keep
`LIVE_ACTIVITY_PUSHES_ENABLED` and the database
`live_activity_pushes_enabled` flag must both be true before delivery. Keep both
false until physical-device acceptance.

Before enabling account deletion, capture and review every production FK to
`auth.users`, Storage object ownership, Auth identities/providers, and retained
RevenueCat/PostHog data. Then implement the server-only Auth Admin finalizer and
privacy redaction as a separate reviewed migration. The checked-in migration
only reports active-trip blockers and makes the legacy Expo deletion RPC fail
closed for native-trip members; it deliberately does not partially delete an
account.

Before production, exercise RLS as at least two users plus anonymous: invite privacy, seat claim races, scorer authority, idempotency, stale-revision conflicts, revoked tokens, transaction replay, ownership transfer, and deletion constraints.

## 4. RevenueCat

- [ ] Connect the existing App Store app and import the consumable product.
- [ ] Put only the Apple public SDK key in `Config/Secrets.xcconfig`.
- [ ] Configure the Supabase user UUID as RevenueCat App User ID.
- [ ] Add an authenticated `NON_RENEWING_PURCHASE` webhook to the server endpoint.
- [ ] Confirm unique App Store transaction IDs can bind to exactly one purchase intent/trip.
- [ ] Test cancellation, delayed webhook, crash after StoreKit success, reinstall, and account re-login in sandbox.
- [ ] For TestFlight only, set `sandbox_purchases_enabled=true` and confirm RevenueCat claims persist `environment=sandbox`.
- [ ] Before public rollout, set `sandbox_purchases_enabled=false`, verify the server flag directly, and confirm a sandbox-only trip reports `isUnlocked=false` while a production receipt reports `true`.

There is no subscription or device-local entitlement. The server’s sanitized,
environment-aware trip entitlement is authoritative for every roster member;
transaction IDs remain service-only payment evidence.

## 5. Vercel and domain

- [x] Set `PUBLIC_PREVIEW_ENDPOINT` and the server-only
  `PUBLIC_PREVIEW_PROXY_SECRET` in Vercel Production and Preview, and configure
  the matching proxy secret plus an independent rate-limit salt in Supabase.
  Never prefix the secret with `VITE_`.
- [x] Confirm HTTPS is active on `teecircle.vercel.app` and neither `/t/*` nor
  `/.well-known/apple-app-site-association` redirects.
- [x] Confirm
  `https://teecircle.vercel.app/.well-known/apple-app-site-association` serves
  JSON for team `9974PM5L6M` and `/t/*`.
- [x] Confirm the app and Messages extension emit
  `https://teecircle.vercel.app/t/<invite-token>` during the MVP.
- [ ] Keep `applinks:teecircle.app` enabled in the app. When the domain is acquired, attach it to the same Vercel project, replace its parked DNS, serve the same AASA contract, and then change `TEE_WEB_HOST` to `teecircle.app`.
- [x] Verify revoked/expired/no-network/completed rendering and privacy-safe
  Open Graph cards in the web suite; production trip documents return
  `noindex`, canonical metadata, and privacy-safe referrer policy.

The Vercel functions forward the platform-provided viewer address only on
requests authenticated with the shared proxy secret. The Edge Function hashes
that transient address with the private rate-limit salt and invitation hash
before the database call; do not add request-header or raw-address logging.

## 6. Physical-device acceptance

Use two physical iPhones on separate accounts and a third Messages recipient without TeeCircle installed when possible.

The signed generic-device build is valid. Installing on Luke's connected iPhone
is currently blocked before app launch because Xcode cannot mount the developer
disk image. Unlock/trust/reconnect or update the phone/Xcode pairing before
running this matrix. The simulator UI-test attempt also ended when CoreSimulator
crashed during relaunch, so UI acceptance is not yet recorded as passing.

1. Upgrade over Expo build 9, sign in again, view a legacy round, and copy it into a new trip.
2. Build a two-round trip from a saved manual course card with Stableford + Skins and net scoring.
3. Complete a sandbox $29.99 captain unlock; confirm cancellation preserves the ready trip.
4. Share, claim an open seat on phone two, score concurrently, and verify stale revisions return the server value.
5. Explicitly post and update an `MSSession` card; verify unsent input survives an expired extension session.
6. Open the same link without the app and compare snapshot revision/ranking to app and extension.
7. Explicitly start Follow Live, terminate the app, then receive a leader change, skin resolution, round transition, and final.
8. Exercise airplane-mode retry, revoked links, notification denial, reinstall, and delayed purchase webhook.
9. Test Dynamic Type, VoiceOver, reduced motion, contrast, and analytics privacy.

## 7. Rollout and rollback

- [ ] Internal TestFlight with kill switches and sandbox purchases.
- [ ] External TestFlight after the complete two-device matrix passes.
- [ ] Disable `sandbox_purchases_enabled` before the first public build becomes available.
- [ ] Phased App Store rollout while monitoring crashes, score-write errors, missing snapshots, snapshot lag, invite opens, claims, Messages posts, Activity starts, and purchase conversion.
- [ ] If a score-integrity issue appears, disable native writes with the server kill switch first.
- [ ] If binary rollback is necessary, pause the rollout and submit the tagged Expo app as a higher patch/build.

Do not delete legacy data or endpoints during rollback. Completed shared results remain readable.
