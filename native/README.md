# TeeCircle 2.0 native client

This directory is the source of truth for the Apple-only TeeCircle 2.0 client. It replaces the Expo binary at the same `com.teecircle.app` App Store record while leaving the Expo app and EAS configuration at the repository root intact as the rollback client.

## Targets

| Target | Bundle ID | Purpose |
| --- | --- | --- |
| `TeeCircle` | `com.teecircle.app` | SwiftUI app, authentication, trips, scoring, purchase, and ActivityKit orchestration |
| `TeeCircleMessages` | `com.teecircle.app.messages` | Human-controlled Messages sharing and claimed-seat score entry |
| `TeeCircleWidgets` | `com.teecircle.app.widgets` | Lock Screen and Dynamic Island Live Activity |

All targets require iOS 16.4, support iPhone portrait, use signing team `9974PM5L6M`, and share `group.com.teecircle.app.shared`. The app version is `2.0.0` build `10`.

## Generate and build

Install XcodeGen, then regenerate after changing `project.yml` or adding files:

```sh
brew install xcodegen
cd native
xcodegen generate
xcodebuild -project TeeCircle.xcodeproj \
  -scheme TeeCircle \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the dependency-free core contract and scoring suite with:

```sh
swift test --package-path Packages/TeeCircleKit
```

Normal Debug device builds use the configured live Supabase MVP backend. The UI-test harness explicitly passes `-ui-testing` to opt into deterministic local fixtures without production writes. Release builds ignore fixture overrides, never grant a trip entitlement locally, and require configured server commands.

## Local configuration

Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`. The real file is ignored. Supply only public client configuration:

- Supabase publishable key
- Google iOS and server client IDs
- PostHog project token
- RevenueCat Apple public SDK key

Never place APNs signing keys, RevenueCat secret keys, Supabase service-role credentials, App Store Connect keys, or private `.p8` files in this project. Those remain in their server/provider secrets stores.

The Messages extension receives only a short-lived, hashed-server-side, device-scoped session. Its plaintext credential is stored in the shared Keychain access group; App Group `UserDefaults` is used only for non-secret cached trip snapshots and unsent form state.

`TEE_WEB_HOST` currently defaults to `teecircle.vercel.app`, so app and Messages shares emit `https://teecircle.vercel.app/t/<invite-token>` for the MVP. The app keeps associated-domain and routing support for `teecircle.app`, allowing a later custom-domain cutover without dropping links created on either host.

## Architecture

- `Packages/TeeCircleKit/TeeCircleDomain` owns Codable API and broadcast contracts.
- `TeeCircleScoring` is a Swift port used for offline previews; authoritative rankings always come from the server snapshot.
- `TeeCircleAPI` is a Foundation-only, extension-safe API client.
- `TeeCircleDesign` renders compact semantic leaderboard/message cards.
- `TeeCircleActivities` owns the sub-4 KB ActivityKit payload contract.
- App services isolate Supabase, RevenueCat, Google, PostHog, Keychain, APNs, and ActivityKit SDK calls from views.

Every public surface consumes `LeaderboardSnapshotV1`. A Realtime event is only a refresh hint; the persisted snapshot revision is canonical.

## Rollback boundary

The annotated local tag `expo-v1.4.0-build9` points to the last Expo rollback baseline. Do not remove root Expo dependencies, `app.json`, or `eas.json` until two stable native releases and at least 90 days have elapsed. If native 2.0 must be rolled back, submit the preserved Expo client with a higher patch version/build number.

See [`../docs/native-2-release-runbook.md`](../docs/native-2-release-runbook.md) for portal and device gates.
