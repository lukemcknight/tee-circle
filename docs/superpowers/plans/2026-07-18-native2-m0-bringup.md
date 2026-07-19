# TeeCircle 2.0 Milestone 0 — Device Bring-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove TeeCircle 2.0 runs interactively — main checkout on a new `native-2` branch, package tests green, simulator boots, the app installs and launches on the owner's iPhone, and the owner signs in on hardware via email code, Apple, and Google.

**Architecture:** No feature work. This milestone is repo mechanics + build/run unblocking + Supabase configuration. The app's Debug device build already points at the live Supabase backend (per `native/README.md`); the blockers are environmental (disk-image mount, CoreSimulator crash), configuration (OTP email template, auth providers, one kill switch), and signing. Spec: `docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md` §4.

**Tech Stack:** Xcode (XcodeGen `project.yml` with committed `project.pbxproj`), Swift Package Manager (`native/Packages/TeeCircleKit`), Supabase (auth, RPCs, `tee_internal.runtime_flags`), iOS 16.4+ deployment target.

## Global Constraints

- **No feature work.** Google-button restyle, sign-up copy, course search, deletion etc. are Milestones 1-2 — do not touch them here.
- **Kill switches:** flip ONLY `native_writes_enabled` to true. `sandbox_purchases_enabled`, public previews, and `live_activity_pushes_enabled` stay OFF (spec §7, runbook §5).
- **Public repo — never commit secrets.** `native/Config/Secrets.xcconfig` is ignored via the tracked `native/.gitignore` and must stay untracked. Verify before every commit.
- **All commits land on `native-2`** (created in Task 1 from `40d9afc`). The Expo app at repo root is read-only throughout.
- **Human steps are owner-only** (Xcode GUI, iPhone, Supabase dashboard, Apple Developer). Tasks 4-6 write instructions and verify results; the owner executes.
- Bring-up failures are RECORDED, not silently fixed: every unexpected failure gets a `BRING-*` row in `docs/audits/2026-07-18-native2-bringup-log.md` (created in Task 2). Fix only what blocks the exit criteria.
- **Exit criteria for the whole plan (spec §4):** owner signs in on hardware via all three methods, including completing profile setup (which requires `native_writes_enabled=true` — `update_my_profile_v1` is gated on it at `supabase/migrations/20260718190000_tee_circle_v2_profile_identity.sql:73-74`).

---

### Task 1: Stand up `native-2` and move the main checkout

**Files:**
- Create: branch `native-2` from `40d9afc`
- Carry from `finalize-v1` (new commit on `native-2`): `docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md`, `docs/superpowers/plans/2026-07-18-native2-m0-bringup.md`, `docs/release/2026-07-appstore-1.5-checklist.md`, `docs/audits/2026-07-18-v1-defect-log.md`

**Interfaces:**
- Consumes: clean tree on `finalize-v1`; parked tree at `40d9afc` (contains full `native/` and the junk-ignore `.gitignore` entries; does NOT contain the `/native/` ignore line — correct, since `native/` is tracked here).
- Produces: main checkout (`/Users/lukemck/Development/tee-circle`) on `native-2` with a complete `native/` tree, the four docs above, pushed upstream. All later tasks run here. The `../tee-circle-2` worktree stays in place until Task 6's wrap-up (the owner has Xcode open on it).

- [ ] **Step 1: Verify clean start**

Run: `git branch --show-current && git status --porcelain | wc -l`
Expected: `finalize-v1` and `0`.

- [ ] **Step 2: Create and switch to native-2**

Run: `git branch native-2 40d9afc && git switch native-2`
Expected: `Switched to branch 'native-2'`. Git restores the tracked `native/` files and leaves ignored residue (DerivedData, Secrets.xcconfig) in place.

- [ ] **Step 3: Verify the native project and secrets survived the switch**

Run:
```bash
test -f native/TeeCircle.xcodeproj/project.pbxproj && echo PBXPROJ_OK
test -f native/Config/Secrets.xcconfig && echo SECRETS_PRESENT
git check-ignore native/Config/Secrets.xcconfig && echo SECRETS_IGNORED
git check-ignore native/TeeCircle.xcodeproj/project.pbxproj || echo PROJECT_TRACKED_OK
```
Expected: all four OK lines. If `SECRETS_IGNORED` fails, STOP and report — do not commit anything until resolved.

- [ ] **Step 4: Carry the four docs from finalize-v1 and commit**

Run:
```bash
git checkout finalize-v1 -- \
  docs/superpowers/specs/2026-07-18-native-2-lean-debut-design.md \
  docs/superpowers/plans/2026-07-18-native2-m0-bringup.md \
  docs/release/2026-07-appstore-1.5-checklist.md \
  docs/audits/2026-07-18-v1-defect-log.md
git commit -m "Carry 2.0 lean-debut spec, M0 plan, and recycled Phase A docs onto native-2

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
Expected: 4 files committed (the defect log and release checklist are reference material per spec §3; the checklist gets rewritten for 2.0 in Milestone 3).

- [ ] **Step 5: Push with upstream and verify no secret staged**

Run: `git show --stat HEAD | head -12 && git push -u origin native-2`
Expected: exactly the 4 doc paths in the stat; new remote branch `native-2`.

---

### Task 2: Baseline — package tests green + bring-up log created

**Files:**
- Create: `docs/audits/2026-07-18-native2-bringup-log.md`
- Test: `native/Packages/TeeCircleKit` (7 test files, runnable without Xcode)

**Interfaces:**
- Consumes: `native-2` checkout from Task 1.
- Produces: the bring-up log all later tasks append `BRING-*` rows to; a recorded baseline that the pure-Swift core passes.

- [ ] **Step 1: Run the package tests**

Run: `swift test --package-path native/Packages/TeeCircleKit 2>&1 | tail -15`
Expected: `Test Suite 'All tests' passed` (APIClient, LiveActivityContract, LeaderboardPresentation, DeepLink, DomainContract, HandicapCalculator, ScoringFixture suites). If the toolchain fails to build, record the exact error as `BRING-1` and report BLOCKED — do not attempt toolchain surgery without review.

- [ ] **Step 2: Create the bring-up log with exactly this content** (fill `<pass/fail + counts>` with the actual Step 1 result — never leave the placeholder)

```markdown
# TeeCircle 2.0 Bring-Up Log (Milestone 0, started 2026-07-18)

Every unexpected failure during bring-up gets a row. Fix only what blocks the
exit criteria (owner signs in on hardware 3 ways); everything else is recorded
for Milestone 1+.

| ID | Stage | What happened | Blocking exit? | Resolution/status |
|----|-------|---------------|----------------|-------------------|

## Baselines
- Package tests (`swift test --package-path native/Packages/TeeCircleKit`, 2026-07-18): <pass/fail + counts>
```

- [ ] **Step 3: Commit**

```bash
git add docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "Record M0 baseline: TeeCircleKit package test run + bring-up log

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Simulator recovery and fixture-mode boot

**Files:**
- Modify (append results): `docs/audits/2026-07-18-native2-bringup-log.md`

**Interfaces:**
- Consumes: bring-up log from Task 2.
- Produces: a simulator that boots the app; UI-test run results recorded. (The prior attempt crashed CoreSimulator during relaunch — runbook §6.)

- [ ] **Step 1: Reset the simulator subsystem**

Run:
```bash
xcrun simctl shutdown all
xcrun simctl erase all
killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || true
xcrun simctl list devices | head -12
```
Expected: device list prints without error (service restarts clean). If listing itself fails: `sudo xcodebuild -runFirstLaunch` and retry; still failing → `BRING-*` row, report BLOCKED.

- [ ] **Step 2: Build for simulator**

Run:
```bash
xcodebuild -project native/TeeCircle.xcodeproj -scheme TeeCircle \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`. (Simulator builds need no signing team.) Compile errors are `BRING-*` rows — fix only if trivial (missing file reference), otherwise report BLOCKED with the error.

- [ ] **Step 3: Run the UI-test suite once**

Run:
```bash
xcodebuild -project native/TeeCircle.xcodeproj -scheme TeeCircle \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet test 2>&1 | tail -25
```
Expected: the run COMPLETES (pass or fail) without CoreSimulator crashing. Record: unit-test and UI-test pass/fail counts as a bring-up-log baseline line. Individual test failures are `BRING-*` rows marked `Blocking exit? no` unless they indicate the app cannot launch at all.

- [ ] **Step 4: Commit the log update**

```bash
git add docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "Record simulator recovery + first completed test run

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Author the owner's device + dashboard checklist

**Files:**
- Create: `docs/native-2-device-bringup-steps.md`

**Interfaces:**
- Consumes: nothing new; encodes runbook §6 blockers + Supabase config into owner-executable steps.
- Produces: the checklist Tasks 5-6 are executed from. The implementer must verify two facts before writing: (a) the three target bundle IDs in `native/project.yml` (expected `com.teecircle.app`, `.messages`, `.widgets` variants — copy the exact strings found); (b) the `tee_internal.runtime_flags` column names in the migration that creates it (`grep -n "runtime_flags" supabase/migrations/*.sql` — adjust the SQL in §3 below only if columns differ from `key`/`enabled`).

- [ ] **Step 1: Write the checklist with exactly this content** (substituting the two verified facts)

```markdown
# TeeCircle 2.0 — Device Bring-Up Steps (owner)

Goal: the app runs on your iPhone and you can sign in all three ways.
Record anything unexpected in docs/audits/2026-07-18-native2-bringup-log.md.

## 1. Fix the device install (Xcode ↔ iPhone)
The last attempt failed with "unable to mount developer disk image" (runbook §6).
In order — stop at the first step that fixes it:
- [ ] Check versions: Xcode ≥ the iOS version on your iPhone.
      `xcodebuild -version` vs iPhone Settings → General → About → iOS Version.
      If the iPhone's iOS is newer than Xcode supports, update Xcode first — this
      is the most common cause of the disk-image error.
- [ ] iPhone: Settings → Privacy & Security → Developer Mode → ON (reboots phone).
- [ ] Reconnect cable, tap "Trust This Computer" on the phone.
- [ ] `xcrun devicectl list devices` — your iPhone should appear as "connected".
- [ ] If the mount error persists: quit Xcode, delete
      `~/Library/Developer/Xcode/iOS DeviceSupport/` (it re-downloads), reboot
      BOTH Mac and iPhone, retry.

## 2. Signing (Xcode GUI, once)
- [ ] Open `native/TeeCircle.xcodeproj` (in the MAIN checkout
      /Users/lukemck/Development/tee-circle — not the tee-circle-2 worktree).
- [ ] For ALL THREE targets — TeeCircle, TeeCircleMessages, TeeCircleWidgets —
      set Signing & Capabilities → Team to your Apple Developer team,
      "Automatically manage signing" ON. Bundle IDs: <the three exact IDs from project.yml>.
- [ ] Select your iPhone as the run destination; press Run (Debug).
- [ ] EXIT CHECK: the app launches on the phone and shows the auth screen
      ("Make the tee time. The group will follow.").

## 3. Supabase dashboard (config the app needs to sign in)
- [ ] Email code fix — Dashboard → Authentication → Email Templates → Magic Link:
      the body must include the token, e.g.:
        <h2>Your TeeCircle sign-in code</h2>
        <p>Enter this code in the app: <strong>{{ .Token }}</strong></p>
        <p>Or tap: {{ .ConfirmationURL }}</p>
      (Today it sends only the link — that's why no code arrived.)
- [ ] SMTP decision: built-in Supabase mailer is fine for bring-up (it's
      rate-limited to a few emails/hour — space out your tests). Real SMTP
      (Resend/Postmark) is a Milestone 3 release gate, not needed now.
- [ ] Apple provider — Authentication → Providers → Apple → Enable; add
      `com.teecircle.app` to Authorized Client IDs.
- [ ] Google provider — Authentication → Providers → Google → Enable;
      Client ID = the value of TEE_GOOGLE_SERVER_CLIENT_ID in
      native/Config/Secrets.xcconfig; add the TEE_GOOGLE_IOS_CLIENT_ID value
      to Authorized Client IDs (comma-separated).
- [ ] Kill switch (required for profile setup / username claim) — SQL Editor:
        insert into tee_internal.runtime_flags (key, enabled)
        values ('native_writes_enabled', true)
        on conflict (key) do update set enabled = true;
      Leave sandbox_purchases_enabled, public previews, and
      live_activity_pushes_enabled ALONE (they stay off for the lean debut).

## 4. The three sign-ins (exit criteria — do all three on the iPhone)
- [ ] Email code: enter your email → code arrives (6 digits, in the email) →
      verify → if this is a fresh account, complete the username/profile screen
      (this proves the kill switch is on).
- [ ] Sign out (Profile → sign out), then Sign in with Apple → lands in the app.
- [ ] Sign out, then Continue with Google → lands in the app.
- [ ] Kill the app, relaunch: still signed in.
Anything that fails: add a BRING-* row to the bring-up log with what you saw.

## 5. Wrap-up (after all of §4 passes)
- [ ] Close Xcode if it still has the tee-circle-2 worktree project open.
- [ ] Remove the worktree (from the main checkout):
        git worktree remove ../tee-circle-2 --force
      (--force is needed because ignored files live there; the main checkout
      has the originals, including Secrets.xcconfig.)
```

- [ ] **Step 2: Commit**

```bash
git add docs/native-2-device-bringup-steps.md
git commit -m "Add owner device + dashboard bring-up checklist (M0)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Owner executes the checklist (human-gated)

**Files:**
- Modify (owner ticks + appends): `docs/native-2-device-bringup-steps.md`, `docs/audits/2026-07-18-native2-bringup-log.md`

**Interfaces:**
- Consumes: Task 4's checklist, Task 3's working simulator (fallback debugging surface if the device path stalls).
- Produces: the app running on hardware with all three sign-ins working — the plan's exit criteria.

- [ ] **Step 1 (owner):** Work `docs/native-2-device-bringup-steps.md` §1-§4 top to bottom, ticking boxes and logging `BRING-*` rows for anything unexpected.
- [ ] **Step 2 (agent, after owner reports):** Review new `BRING-*` rows; for each blocking row, diagnose with the owner (systematic-debugging skill) until §4's three sign-ins all pass. Non-blocking rows stay recorded for Milestone 1.
- [ ] **Step 3: Commit the completed checklist + log**

```bash
git add docs/native-2-device-bringup-steps.md docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "M0 exit: three sign-ins verified on hardware; bring-up log updated

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Milestone close-out

**Files:**
- Modify: `docs/audits/2026-07-18-native2-bringup-log.md` (closing summary)

**Interfaces:**
- Consumes: completed Task 5.
- Produces: recorded M0 completion; clean workspace (worktree removed per checklist §5); the input state for the Milestone 1 plan (front door: Google button, sign-up copy — spec §5).

- [ ] **Step 1 (owner):** Checklist §5 wrap-up (close Xcode, remove `../tee-circle-2` worktree).
- [ ] **Step 2: Verify workspace state**

Run: `git worktree list && git branch --show-current && git status --porcelain | wc -l`
Expected: only the main checkout listed; `native-2`; `0` (or only the checklist/log if not yet committed).

- [ ] **Step 3: Append closing summary to the bring-up log and commit**

Append: date, what unblocked the device install (which §1 step fixed it), sign-in results (3/3), open non-blocking `BRING-*` rows carried to Milestone 1. Then:

```bash
git add docs/audits/2026-07-18-native2-bringup-log.md
git commit -m "Close Milestone 0: 2.0 runs on hardware, three sign-ins green

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 4:** Invoke superpowers:writing-plans for the Milestone 1 plan (front door: Google button restyle + sign-up copy, spec §5), seeded with any carried `BRING-*` rows.

---

## Self-Review (completed 2026-07-18)

- **Spec coverage (spec §3-§4):** branch mechanics → Task 1; disk-image/CoreSimulator blockers → Tasks 3-4; signing → Task 4 §2; OTP template/providers/SMTP decision → Task 4 §3; kill-switch necessity (profile RPC gated) → Global Constraints + Task 4 §3; exit criteria (3 sign-ins on hardware) → Tasks 5-6. Worktree disposal (spec §3) → Task 4 §5/Task 6.
- **Placeholder scan:** two intentional substitution points, both with explicit fill instructions: Task 2 Step 2 baseline result; Task 4's `<the three exact IDs from project.yml>` verified by the implementer before writing.
- **Consistency:** log filename, `BRING-*` convention, and branch name `native-2` identical across Tasks 2-6; kill-switch SQL matches `tee_internal.native_writes_enabled()`'s storage (`runtime_flags`, `key`/`enabled`) as read from `20260718183842_tee_circle_v2_commands.sql:47-58`, with a column-name re-verify step in Task 4.
