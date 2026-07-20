# TeeCircle 2.0 Milestone 1 — Front Door & Live Leaderboards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app's first impression matches the product's standard — no internal-versioning copy, a Google button that belongs next to the Apple one, clear sign-up messaging, a green UI-test suite, and leaderboards that actually populate (in-app and on the public Follow-Live page).

**Architecture:** Four client tasks on the SwiftUI app (copy sweep, custom Google button + sign-up copy, two UI-test bug fixes) and two server/ops tasks (snapshot worker pipeline via pg_cron + pg_net + Vault; Follow-Live web enablement via Vercel env + the `public_previews_enabled` flag). Spec: `docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md` §5; bring-up findings in `docs/audits/2026-07-18-native2-bringup-log.md` (BRING-1, BRING-2, BRING-6).

**Tech Stack:** SwiftUI (iOS 16.4+), XCUITest, Supabase (pg_cron, pg_net, Vault, Edge Functions), Vercel (website).

## Global Constraints

- **Copy rule (owner directive, 2026-07-20):** user-facing strings never reference internal versioning — no "TeeCircle 1.0", "2.0", or "legacy" visible to users. It is one continuous app. (Accessibility identifiers and internal symbol names may keep `legacy`.)
- **Kill switches:** `purchases_required` stays **false** (owner's free-scoring decision); `live_activity_pushes_enabled` stays **false**; `public_previews_enabled` flips to **true** only in Task 6 after the pipeline is verified. `native_writes_enabled` stays true.
- **Public repo — never commit secrets.** The snapshot worker secret exists only in the Supabase dashboard (edge secret + Vault); never in git, never echoed into the transcript of any report.
- All commits land on `native-2`. TDD: the failing UI tests ARE the red state for Tasks 3-4 — no fix without the corresponding test passing after.
- Simulator runs use: `xcodebuild -project native/TeeCircle.xcodeproj -scheme TeeCircle -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6' -derivedDataPath native/DerivedData` (the `OS=18.6` pin is required on this machine).
- Baseline to protect: 42/42 unit, 11/13 UI (the 2 failures are Tasks 3-4's targets). Any regression below that blocks the task.

---

### Task 1: Versioning-copy sweep + spec addendum

**Files:**
- Modify: `native/TeeCircle/Features/Home/HomeView.swift:299`
- Modify: `docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md` (§5 addendum)
- Audit (read-only unless hits found): all `Text(`/`title`/alert strings under `native/TeeCircle`, `native/TeeCircleMessages`, `native/TeeCircleWidgets`

**Interfaces:**
- Produces: the copy rule as a spec line later tasks and milestones inherit.

- [ ] **Step 1: Fix the known offender**

In `HomeView.swift:299` replace:
```swift
sectionHeader("ORIGINAL ROUNDS", detail: "From TeeCircle 1.0")
```
with:
```swift
sectionHeader("ROUND HISTORY", detail: "Rounds you’ve already played")
```

- [ ] **Step 2: Audit for further user-facing hits**

Run: `grep -rn "1\.0\|2\.0\|[Ll]egacy" native/TeeCircle native/TeeCircleMessages native/TeeCircleWidgets --include="*.swift" | grep -v "accessibilityIdentifier\|launchArguments\|-ui-\|func \|var \|let \|struct \|case \|//\|legacyRound\|LegacyRound\|LegacyTrip\|legacyId\|legacy-"`
Judge every remaining hit: if the string can render on screen, rewrite it in product terms (same voice as Step 1); record each decision (hit → verdict) in your report. Known-clean examples that must NOT be renamed: navigation titles "Previous rounds" and "Converted round" (already neutral), all `legacy.*` accessibility identifiers, type/route names.

- [ ] **Step 3: Add the spec addendum**

Append to `docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md` §5:
```markdown
- **Copy rule (owner directive, 2026-07-20):** user-facing strings never reference
  internal versioning ("TeeCircle 1.0", "2.0", "legacy"). One continuous app.
```

- [ ] **Step 4: Verify build + unit tests**

Run the simulator build + unit tests (Global Constraints command, `test` action). Expected: build succeeds; 42/42 unit tests pass; UI failures unchanged (the 2 known ones only).

- [ ] **Step 5: Commit**

```bash
git add native/TeeCircle/Features/Home/HomeView.swift docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md
git commit -m "Remove internal-versioning copy from UI; add copy rule to spec

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
(Include any additional files Step 2 changed.)

---

### Task 2: Custom Google button + sign-up clarity copy

**Files:**
- Create: `native/TeeCircle/Features/Authentication/GoogleSignInBrandButton.swift`
- Create: `native/TeeCircle/Assets.xcassets/GoogleG.imageset/Contents.json` (scaffold; owner drops PNGs)
- Modify: `native/TeeCircle/Features/Authentication/AuthenticationView.swift:181-197` (button swap) and the email form (clarity copy)

**Interfaces:**
- Consumes: existing `beginGoogleSignIn()` action, `googleIsConfigured` gate, `isSubmitting` state, `TeeCircleBrand` palette — all already in `AuthenticationView.swift`.
- Produces: `GoogleSignInBrandButton(isEnabled: Bool, action: () -> Void)`.

- [ ] **Step 1: Create the button view**

```swift
import SwiftUI

/// Custom Google sign-in button matching the Apple button's geometry
/// (52pt, 14pt continuous radius), per Google's branding guidelines for
/// custom buttons: white surface, official "G" mark, standard label.
struct GoogleSignInBrandButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("GoogleG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text("Continue with Google")
                    .font(.headline)
                    .foregroundStyle(Color.black.opacity(0.84))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52, maxHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityIdentifier("auth.google")
    }
}
```

- [ ] **Step 2: Create the imageset scaffold**

`native/TeeCircle/Assets.xcassets/GoogleG.imageset/Contents.json`:
```json
{
  "images" : [
    { "filename" : "google_g_1x.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "google_g_2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "google_g_3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```
**Human step (owner):** download the official "G" logo PNGs from https://developers.google.com/identity/branding-guidelines (Download assets → `signin-assets` → the standalone `g-logo` mark), drop the three sizes into the imageset with the filenames above. Until then the button renders with an empty 18pt slot — acceptable for review, not for release.

- [ ] **Step 3: Swap the button in AuthenticationView**

Replace lines 181-197 (`if googleIsConfigured { GoogleSignInButton(...) ... }` block) with:
```swift
                if googleIsConfigured {
                    GoogleSignInBrandButton(
                        isEnabled: !isSubmitting,
                        action: beginGoogleSignIn
                    )
                }
```
Remove `import GoogleSignInSwift` from this file if no other symbol from that module remains (the `GoogleSignIn` module used by the sign-in flow is separate and stays). Leave the package product linked in `project.yml` — unlinking is project surgery deferred to M2 cleanup.

- [ ] **Step 4: Add sign-up clarity copy**

In the email form, directly below the `emailModeControl` line (~line 277), insert:
```swift
            if !usePassword {
                Text("New here? The emailed code signs you up automatically — no password needed.")
                    .font(.footnote)
                    .foregroundStyle(TeeCircleBrand.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("auth.signupHint")
            }
```

- [ ] **Step 5: Verify**

Simulator build + full test run (Global Constraints command). Expected: build succeeds; unit 42/42; UI failures unchanged (auth-flow UI tests — including the email sign-in state machine — still pass; `auth.google` identifier preserved so any existing reference keeps working). Capture a simulator screenshot of the auth card for the owner's visual sign-off.

- [ ] **Step 6: Commit**

```bash
git add native/TeeCircle/Features/Authentication/GoogleSignInBrandButton.swift \
        native/TeeCircle/Assets.xcassets/GoogleG.imageset/Contents.json \
        native/TeeCircle/Features/Authentication/AuthenticationView.swift
git commit -m "Replace SDK Google button with brand-guideline custom button; add sign-up hint

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Fix BRING-2 — profile-setup gate never presents under -ui-needs-profile

**Files:**
- Investigate: `native/TeeCircle/App/TeeCircleStore.swift` (fixture launch-arg handling, ~line 214 region parses other `-ui-*` args), `native/TeeCircle/App/RootView.swift` (gate condition `needsProfileSetup`), `native/TeeCircle/App/AppConfiguration.swift`
- Test (already failing = RED): `native/TeeCircleUITests/TeeCircleUITests.swift` — `testProfileSetupGateBlocksTheAppUntilNameAndUsernameExist`

**Interfaces:**
- Consumes: `profileSetup.*` accessibility identifiers (all present in `ProfileSetupView.swift` — verified; the bug is that the gate view never appears).

- [ ] **Step 1: Reproduce (RED)** — run only this test:
`xcodebuild <Global Constraints flags> test -only-testing:TeeCircleUITests/TeeCircleUITests/testProfileSetupGateBlocksTheAppUntilNameAndUsernameExist`
Expected: FAIL with "No matches found … 'profileSetup.submit'". Capture the auto-saved `gate-as-test-sees-it` screenshot from the result bundle — it shows what actually rendered instead of the gate.

- [ ] **Step 2: Root-cause** — trace how `-ui-needs-profile` is (or isn't) consumed: grep it in `native/TeeCircle`; compare with how `-ui-legacy-needs-setup` is honored (`TeeCircleStore.swift:214`). Hypothesis space (verify, don't guess): the arg is never parsed; or the fixture store seeds a complete profile so `needsProfileSetup` is false; or RootView checks a different flag in mock mode. State the confirmed root cause in your report with file:line.

- [ ] **Step 3: Minimal fix** at the confirmed source (fixture state wiring — do NOT weaken the production gate logic to make a test pass).

- [ ] **Step 4: Verify (GREEN)** — the Step 1 command passes; then the FULL suite: expected 12/13 UI or better (BRING-1 may still fail until Task 4), unit 42/42.

- [ ] **Step 5: Commit**
```bash
git add -A native/TeeCircle native/TeeCircleUITests
git commit -m "Fix profile-setup gate fixture: -ui-needs-profile now presents the gate

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Fix BRING-1 — legacy-conversion handicap field cannot be revealed

**Files:**
- Investigate: `native/TeeCircle/Features/Legacy/LegacyTripSetupView.swift` (handicap `TextField`s with `legacy.handicap.<id>` identifiers; scrolling/keyboard-avoidance), `native/TeeCircleUITests/TeeCircleUITests.swift` helpers (`tap`, `element` — how they reveal off-screen elements)
- Test (already failing = RED): `testConvertedLegacyRoundCanRecoverCourseCardAndHandicaps`

- [ ] **Step 1: Reproduce (RED)** — `-only-testing:` run of this test. Expected: FAIL with "Could not reveal UI element 'legacy.handicap.…' TextField". Note WHICH of the 3 fields fails (first/second/third) from the failure context — it disambiguates keyboard-occlusion (later fields) from render-timing (first field).

- [ ] **Step 2: Root-cause** — run once with the simulator visible if needed; determine whether the field exists but is occluded (keyboard covers it after typing in the previous field, and the view lacks scroll-into-view behavior) or never renders. Report the confirmed cause with file:line.

- [ ] **Step 3: Minimal fix** — if occlusion: give the view proper keyboard avoidance (e.g. ensure fields are inside the scroll container that already drives the picker, or add `.scrollDismissesKeyboard(.interactively)` + focus-driven `scrollTo`, matching the pattern in `AuthenticationView.swift:32-61`). Fixing the test helper instead of the view is acceptable ONLY if a real user can already reach the field (prove it with a simulator interaction before choosing that route).

- [ ] **Step 4: Verify (GREEN)** — single test passes; full suite: expected UI 13/13, unit 42/42 — the first fully green run. Update the bring-up log: mark BRING-1 and BRING-2 rows Resolved with commit refs.

- [ ] **Step 5: Commit**
```bash
git add -A native/TeeCircle native/TeeCircleUITests docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "Fix legacy-conversion handicap entry reveal; UI suite fully green

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Snapshot worker pipeline (server) — owner checklist + probes

**Files:**
- Create: `docs/native-2-snapshot-pipeline-steps.md`
- Modify (append verification results): `docs/audits/2026-07-18-native2-bringup-log.md`

**Interfaces:**
- Consumes: `public.enqueue_missing_trip_snapshot_jobs_service_v1()` (SQL, callable without HTTP secret — `release_integrity.sql:1573`); edge function `recompute-trip-snapshot-v1` (auth: header `x-tee-circle-worker-secret` vs env `SNAPSHOT_WORKER_SECRET` — `index.ts:78-79`); project ref `zgrbwhnfuxgvkwtgrncu`.
- Produces: leaderboard snapshots computing continuously; prerequisite for Task 6.

- [ ] **Step 1: Probe function deployment (agent, no secret needed)**

Run: `curl -s -o /dev/null -w '%{http_code}' -X POST https://zgrbwhnfuxgvkwtgrncu.supabase.co/functions/v1/recompute-trip-snapshot-v1 -H 'Content-Type: application/json' -d '{}'`
Expected: `401` or `403` (deployed, refusing without secret). A `404` means the function is NOT deployed — record that in the checklist's prerequisites section (owner deploys via dashboard from `supabase/functions/recompute-trip-snapshot-v1/` or `npx supabase functions deploy recompute-trip-snapshot-v1` after `npx supabase login`).

- [ ] **Step 2: Write the owner checklist with exactly this content** (adjust only the Step-1 finding):

```markdown
# Snapshot Pipeline — Owner Steps (M1 Task 5)

Goal: leaderboards compute automatically. ~10 minutes in the Supabase dashboard.
Never paste the worker secret into chat, git, or the app.

## 1. Mint the worker secret
- [ ] In a local terminal: `openssl rand -hex 32` — this is SNAPSHOT_WORKER_SECRET.
- [ ] Dashboard → Edge Functions → Secrets → add `SNAPSHOT_WORKER_SECRET` = that value.
- [ ] Dashboard → Project Settings → Vault → New secret: name `snapshot_worker_secret`,
      value = the SAME string.

## 2. Enable extensions + schedule (SQL Editor, one paste)
- [ ] Run:
      create extension if not exists pg_cron;
      create extension if not exists pg_net;

      select cron.schedule(
        'teecircle-enqueue-snapshots',
        '* * * * *',
        $$select public.enqueue_missing_trip_snapshot_jobs_service_v1();$$
      );

      select cron.schedule(
        'teecircle-recompute-snapshots',
        '* * * * *',
        $$
        select net.http_post(
          url := 'https://zgrbwhnfuxgvkwtgrncu.supabase.co/functions/v1/recompute-trip-snapshot-v1',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'x-tee-circle-worker-secret',
            (select decrypted_secret from vault.decrypted_secrets
             where name = 'snapshot_worker_secret')
          ),
          body := '{}'::jsonb
        );
        $$
      );

## 3. Verify (after ~2 minutes)
- [ ] SQL Editor: `select jobid, jobname, schedule, active from cron.job;`
      → both teecircle-* jobs listed, active = t.
- [ ] Score a hole in the app, wait 2 minutes, then:
      `select trip_id, revision, generated_at from public.trip_leaderboard_snapshots order by generated_at desc limit 3;`
      → a row with a recent generated_at.
- [ ] In the app: Leaderboard tab shows standings with a REVISION number.
```

- [ ] **Step 3 (owner):** execute the checklist; report the three verification results.

- [ ] **Step 4: Record + commit** — append the outcome to the bring-up log (pipeline live / any deviations as BRING-* rows):
```bash
git add docs/native-2-snapshot-pipeline-steps.md docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "Add snapshot pipeline owner steps; record pipeline verification

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Follow-Live web page enablement

**Files:**
- Modify (append steps + results): `docs/native-2-snapshot-pipeline-steps.md`, `docs/audits/2026-07-18-native2-bringup-log.md`

**Interfaces:**
- Consumes: Task 5's live pipeline; website server env contract (`website/server/publicPreview.ts:60-67`): `SUPABASE_URL` required (endpoint auto-derives to `${SUPABASE_URL}/functions/v1/preview-trip-v1`), `PUBLIC_PREVIEW_PROXY_SECRET` optional; gate function `resolve_public_trip_preview` requires `public_previews_enabled` = true (`services.sql:459`).
- Depends on: Task 5 verified. Do not start before.

- [ ] **Step 1 (agent): probe preview function deployment** — `curl -s -X POST https://zgrbwhnfuxgvkwtgrncu.supabase.co/functions/v1/preview-trip-v1 -H 'Content-Type: application/json' -d '{"schemaVersion":1,"inviteToken":"probe000000000000000000"}' | head -c 200` — expected: a structured JSON error (deployed). `404` → owner deploys as in Task 5 Step 1.

- [ ] **Step 2 (owner):** Vercel dashboard → the teecircle website project → Settings → Environment Variables → add `SUPABASE_URL` = `https://zgrbwhnfuxgvkwtgrncu.supabase.co` (Production) → Redeploy.

- [ ] **Step 3 (owner):** SQL Editor: `update tee_internal.runtime_flags set enabled = true where key = 'public_previews_enabled';`

- [ ] **Step 4: Verify end-to-end** — open a real share link (`https://teecircle.app/t/<token>` from the app's share sheet): expect the live leaderboard (or the styled "ready to share… will appear automatically" pending card if the trip has no snapshot yet — NOT "We can't find this leaderboard"). Agent probe: `curl -s "https://teecircle.app/api/preview?inviteToken=<token owner provides>" | head -c 300` returns `schemaVersion` JSON, not `invite_unavailable`.

- [ ] **Step 5: Record + commit** — append results to the docs; update BRING-6 row to Resolved:
```bash
git add docs/native-2-snapshot-pipeline-steps.md docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "Enable public Follow-Live previews; record end-to-end verification

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Close out Milestone 0 (carried gate)

M0's exit criteria (three sign-ins on hardware) has not been formally confirmed. Before M1 is declared done:
- [ ] Owner confirms: email code (6 digits) ✓/✗, Apple ✓/✗, Google ✓/✗, relaunch-still-signed-in ✓/✗ — recorded in `docs/native-2-device-bringup-steps.md` §4 checkboxes.
- [ ] Owner runs checklist §5 (close old Xcode window; `git worktree remove ../tee-circle-2 --force`).
- [ ] Controller appends the M0 closing summary to the bring-up log per M0 plan Task 6 and commits.

---

## Self-Review (completed 2026-07-20)

- **Coverage:** owner copy directive → Task 1 (+ spec addendum + memory already saved); Google button + sign-up copy (spec §5) → Task 2; BRING-1/2 → Tasks 4/3; BRING-6 pipeline → Tasks 5-6; M0 carried gate → Task 7. Deferred consciously: GoogleSignInSwift package unlink (M2 cleanup, noted in Task 2 Step 3).
- **Placeholders:** Task 5's SQL is complete and exact; the only owner-supplied values are the secret itself (deliberately never written down) and Task 6's real invite token (runtime value). Task 2's PNGs are an explicit human asset-drop step with source URL.
- **Consistency:** accessibility identifier `auth.google` preserved across Task 2; test names, file paths, and the `OS=18.6` destination pin match the recorded M0 baselines; kill-switch states match the bring-up log's product decisions.
