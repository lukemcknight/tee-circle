# TeeCircleKit

Shared, dependency-light foundations for the TeeCircle app, Messages extension, widgets, and Live Activities.

## Products

- `TeeCircleDomain`: Codable v1 trip, roster, round, leaderboard, API-envelope, score-command, and deep-link contracts.
- `TeeCircleScoring`: deterministic Stableford, skins, stroke-allocation, trip aggregation, and legacy handicap math.
- `TeeCircleAPI`: an extension-safe `URLSession` actor with bearer auth, idempotency headers, version checks, bounded responses, and structured server errors.
- `TeeCircleDesign`: semantic SwiftUI leaderboard and compact Messages card views plus testable presentation models.
- `TeeCircleActivities`: ActivityKit attributes, compact content state, and authoritative-snapshot mapping.

The package has no third-party dependencies. The app can use Supabase and RevenueCat while extensions remain on Foundation-only networking.

## Integration

Add the local package from `Packages/TeeCircleKit`, then attach only the products each target needs. The package deployment floor is iOS 16.4; it also builds on macOS so its contracts and scoring can run in fast host tests.

```swift
import TeeCircleDomain
import TeeCircleScoring

let standings = TeeCircleScoring.tripStandings(
    rounds: playerRounds,
    format: .stableford,
    scoring: .net
)
```

```swift
import TeeCircleAPI
import TeeCircleDomain

let client = TeeCircleAPIClient(
    baseURL: URL(string: "https://api.teecircle.app")!,
    tokenProvider: keychainTokenProvider
)

let request = try APIRequest<APIEnvelope<ScoreHoleResultV1>>.json(
    method: .post,
    path: "/v1/scores",
    body: command,
    idempotencyKey: command.idempotencyKey
)
let result = try await client.sendEnvelope(request)
```

`APIClientConfiguration(allowsInsecureLocalhost: true)` permits HTTP only for `localhost`, `127.0.0.1`, and `::1`; production clients remain HTTPS-only.

## Verification

From this directory:

```sh
CLANG_MODULE_CACHE_PATH=.build/ModuleCache swift test
xcodebuild -scheme TeeCircleKit-Package \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The cross-runtime wire examples live in `contracts/native-v2-scoring-fixtures.json` and `contracts/native-v2-leaderboard-snapshot-v1.json` at the repository root.
