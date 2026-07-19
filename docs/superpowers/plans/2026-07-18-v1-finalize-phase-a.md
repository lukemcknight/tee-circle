# TeeCircle v1 Finalize — Phase A (Park, Audit, Release Scaffolding) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely park the trip-tournament WIP, stand up the `finalize-v1` branch, produce the full audit apparatus (device checklist + code-audit defect log) and the App Store release scaffolding, ending with a ranked defect list ready to drive Phase B (fix, polish, submit).

**Architecture:** This is a stabilization/release project, not a feature build. Phase A produces documents, branch state, and a defect list; no app code changes. Phase B (a separate plan, written only after the device audit completes) consumes the ranked defect list and implements fixes, golden-path polish, and the 1.5.0 submission. Spec: `docs/superpowers/specs/2026-07-18-v1-finalize-release-design.md`.

**Tech Stack:** git, Expo/React Native (v54, RN 0.81), Supabase, EAS builds, App Store Connect, Vercel (website at `teecircle.app`).

## Global Constraints

- **No new features. No refactors beyond what a fix requires.** (Spec §6)
- **Public repo — never commit secrets.** `AuthKey.p8`, `*.p8`, `*.ipa`, `.env*` are git-ignored and must stay that way. Verify staged files before every commit in Task 1.
- **All work lands on `finalize-v1`** (branched off `main`), except Task 1 which commits to `trip-tournament-engines`.
- **Target release: version 1.5.0, buildNumber 10** — the actual bump happens in Phase B at submission time, not in this plan.
- **Listing copy is generic social-golf** ("schedule rounds with your golf buddies") — no promises of unshipped features (no GPS mentions). (Spec §7)
- **Severity rubric everywhere:** P0 = crash / data loss / flow-blocking / App Review rejection risk; P1 = works but bad experience; P2 = cosmetic. (Spec §5)
- Two test accounts are required for friend/invite flows (Account A = owner's, Account B = fresh email account created during the device audit).

---

### Task 1: Park the tournament WIP on `trip-tournament-engines`

**Files:**
- Modify: `.gitignore` (append 4 junk entries)
- Commit: all remaining dirty/untracked files on branch `trip-tournament-engines`

**Interfaces:**
- Consumes: current dirty working tree (~65 files: modified tournament engines, supabase functions/migrations, website liveTrip work, native/, contracts/, docs).
- Produces: clean working tree on `trip-tournament-engines`, pushed to origin. Later tasks rely on `git status --porcelain` being empty.

- [ ] **Step 1: Confirm starting branch and dirty state**

Run: `git branch --show-current && git status --porcelain | wc -l`
Expected: `trip-tournament-engines` and a count ≥ 60.

- [ ] **Step 2: Ignore the junk (session logs, temp dirs, Krita autosaves, local Claude settings)**

Append to `.gitignore`:

```gitignore

# tool/session junk
.playwright-mcp/
supabase/.temp/
*.kra
.claude/settings.local.json
```

- [ ] **Step 3: Stage everything else**

Run: `git add -A && git status --porcelain | grep -v "^A \|^M " || true`
Expected: no output lines beginning with `??` remain except nothing — i.e. everything is either staged or ignored.

- [ ] **Step 4: Secret guard — verify nothing sensitive is staged**

Run: `git diff --cached --name-only | grep -iE "\.p8$|\.p12$|\.ipa$|\.env|AuthKey|settings\.local" || echo CLEAN`
Expected: `CLEAN`. (`.mcp.json`, `.codex/config.toml`, `.claude/skills/` were inspected 2026-07-18 and contain no secrets; they are fine to commit.)

If anything sensitive appears: `git restore --staged <file>`, add it to `.gitignore`, and re-run Steps 3–4.

- [ ] **Step 5: Commit the WIP**

```bash
git commit -m "WIP: park trip tournament work (plan 1/3 engines done; functions, migrations, liveTrip site, native untested)

Parked per docs/superpowers/specs/2026-07-18-v1-finalize-release-design.md §4.
Resumable: plans 2/3 and 3/3 of the 2026-07-13 trip tournament design remain unimplemented.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Verify clean tree and push**

Run: `git status --porcelain | wc -l && git push origin trip-tournament-engines`
Expected: `0`, then a successful push (`trip-tournament-engines -> trip-tournament-engines`).

---

### Task 2: Create `finalize-v1` off `main` with the spec and plan

**Files:**
- Create: branch `finalize-v1` (from `main`)
- Copy from `trip-tournament-engines`: `docs/superpowers/specs/2026-07-18-v1-finalize-release-design.md`, `docs/superpowers/plans/2026-07-18-v1-finalize-phase-a.md`

**Interfaces:**
- Consumes: clean tree from Task 1; spec + plan docs committed on `trip-tournament-engines`.
- Produces: branch `finalize-v1` containing the spec and this plan, pushed with upstream set. All later tasks run on this branch.

- [ ] **Step 1: Branch off up-to-date main**

Run: `git checkout main && git pull origin main && git checkout -b finalize-v1`
Expected: `Switched to a new branch 'finalize-v1'`.

- [ ] **Step 2: Copy the spec and plan from the tournament branch**

Run:
```bash
git checkout trip-tournament-engines -- \
  docs/superpowers/specs/2026-07-18-v1-finalize-release-design.md \
  docs/superpowers/plans/2026-07-18-v1-finalize-phase-a.md
git commit -m "Add finalize-v1 spec and Phase A plan

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
Expected: both files staged and committed; `git log --oneline -1` shows the new commit.

- [ ] **Step 3: Push with upstream**

Run: `git push -u origin finalize-v1`
Expected: new remote branch created.

---

### Task 3: Author the device-audit checklist

**Files:**
- Create: `docs/audits/2026-07-18-v1-device-audit-checklist.md`

**Interfaces:**
- Consumes: spec §5 flow matrix.
- Produces: the checklist the owner executes in Task 7. Task 4 uses the same severity rubric and defect-log path: `docs/audits/2026-07-18-v1-defect-log.md`.

- [ ] **Step 1: Write the checklist file with exactly this content**

```markdown
# TeeCircle v1 Device Audit — Checklist (2026-07-18)

**Build:** current `finalize-v1` dev/TestFlight build on a physical iPhone.
**Accounts:** Account A (existing owner account) and Account B (create fresh
during Auth checks below). Two physical devices ideal; one device with
sign-out/sign-in switching acceptable (push checks then need care).
**Recording defects:** every failure goes in
`docs/audits/2026-07-18-v1-defect-log.md` using the table format defined there.
Severity: P0 = crash / data loss / flow-blocking / App Review rejection risk;
P1 = works but bad experience; P2 = cosmetic.

## 0. Install & first launch
- [ ] Fresh install → Welcome screen renders correctly (safe areas, no flash of wrong screen)
- [ ] Kill + relaunch → returns to correct screen (Welcome when signed out)

## 1. Auth
- [ ] Email sign-up (creates Account B) — validation errors readable (bad email, short password)
- [ ] Email sign-in wrong password → clear error, not a spinner hang
- [ ] Sign in with Apple completes and lands in the app (HUMAN_STEPS.md §1–2 config)
- [ ] Sign in with Google completes and lands in the app (HUMAN_STEPS.md §3–4 config)
- [ ] Sign out from Profile → back to Welcome, session actually cleared after relaunch

## 2. Username onboarding
- [ ] New account is forced through username claim
- [ ] Taken username → clear inline error
- [ ] Valid claim proceeds to Home; username visible on Profile

## 3. Home
- [ ] Empty state (Account B, no rounds) — designed, not blank/spinner
- [ ] Rounds list (Account A) — upcoming rounds render with course, date, status

## 4. Friends
- [ ] Search finds Account B by username; not-found state is designed
- [ ] A sends request → B sees it and can accept
- [ ] B receives a push notification for the request (device, app backgrounded)
- [ ] Friend count updates on both sides; friend detail screen renders
- [ ] Remove friend works and is reflected on both sides

## 5. Groups
- [ ] Create group, add B as member
- [ ] Group details + members screens render; member removal works

## 6. Tee time (the core loop — walk it twice, once per direction)
- [ ] Create round: course search returns results (Places API); date/time picker sane
- [ ] Invite friends screen lists friends; select B; submit succeeds
- [ ] B gets invite push; round appears for B with respond options
- [ ] B responds yes → A sees the response (TeeTimeResults/review reflects it)
- [ ] B responds no / changes response → state stays consistent
- [ ] Cancel/edit round (if exposed in UI) behaves; if not exposed, note as finding

## 7. Scoring & handicap
- [ ] Hole-by-hole entry on RoundScoreScreen: enter 18 holes, totals correct
- [ ] Backgrounding mid-entry does not lose strokes
- [ ] RoundDetail shows saved scorecard; handicap number updates plausibly

## 8. Voice search
- [ ] Mic permission prompt appears once, denial path shows guidance (not crash)
- [ ] "tee times saturday morning near me" → parsed intent → results or designed empty state
- [ ] Nonsense query → graceful failure message

## 9. Profile & account
- [ ] Profile edit saves and persists after relaunch
- [ ] Delete account: confirm flow → signed out → old credentials no longer sign in
      (Apple REQUIRES this to work for App Review)

## 10. Resilience spot-checks
- [ ] Airplane mode on Home / Friends / CreateRound → error or offline state, no crash
- [ ] Slow network (LTE, elevator) on tee-time create → no double-created rounds
```

- [ ] **Step 2: Commit**

```bash
git add docs/audits/2026-07-18-v1-device-audit-checklist.md
git commit -m "Add v1 device audit checklist (finalize Phase A)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Static code audit → seed the defect log

**Files:**
- Create: `docs/audits/2026-07-18-v1-defect-log.md`
- Read (audit targets, no modifications): all 16 screens in `src/screens/`, `src/hooks/useFriendships.ts`, `src/hooks/useRounds.ts`, `src/hooks/useRoundResponses.ts`, `src/hooks/usePushNotifications.ts`, `src/context/AuthContext.tsx`, `src/context/DataContext.tsx`, `src/lib/placesApi.ts`, `src/lib/socialAuth.ts`, `src/navigation/AppNavigator.tsx`

**Interfaces:**
- Consumes: severity rubric from Global Constraints.
- Produces: `docs/audits/2026-07-18-v1-defect-log.md` — the single defect list both audits append to; Phase B's plan is generated from it. Code findings use IDs `CODE-1..n`; device findings (Task 7) use `DEV-1..n`.

- [ ] **Step 1: Create the defect log with this header and table format**

```markdown
# TeeCircle v1 Defect Log (2026-07-18)

Single source of truth for the finalize-v1 release. Sources: static code audit
(`CODE-*`, this file's first section) and device audit (`DEV-*`, appended
during the device walk). Severity: P0 = crash / data loss / flow-blocking /
App Review rejection risk; P1 = works but bad experience; P2 = cosmetic.

| ID | Severity | Flow | Where (file:line) | Problem | Expected behavior |
|----|----------|------|-------------------|---------|-------------------|
```

- [ ] **Step 2: Audit every file on the target list against this checklist, appending one table row per finding**

For each screen/hook/context, check:
1. Every `await`/`.then` on Supabase or fetch has a failure path that reaches the UI (not just `console.log`/swallowed catch).
2. Loading state exists for every async render dependency (no permanently blank screen if a query hangs).
3. Empty states: list screens (Home, Friends, InviteFriends, GroupMembers, TeeTimeResults) render something designed at zero items.
4. Navigation dead ends: every screen reachable from `AppNavigator.tsx` can navigate back; no screen is orphaned after a mutation (e.g. after deleting the thing being viewed).
5. Mutations refresh dependent state (accepting a friend request updates lists/counts without manual refresh).
6. Realtime/listener cleanup: every subscription/listener in hooks is removed on unmount.
7. Text inputs: keyboard avoidance and submit-on-enter on Auth, Username, CreateRound, VoiceSearch.
8. Account deletion in `AuthContext`/`ProfileScreen` actually deletes server-side data (not just signs out) — Apple review risk if fake.
9. Push token lifecycle in `usePushNotifications.ts`: registered after login, revoked on sign-out/delete.
10. `placesApi.ts` / `socialAuth.ts`: API keys read from config (never hardcoded — public repo), quota/error responses handled.

- [ ] **Step 3: Sanity-check coverage**

Run: `grep -c "^| CODE-" docs/audits/2026-07-18-v1-defect-log.md`
Expected: a number ≥ 1 (a 16-screen app audited honestly will surface findings; if truly zero, state that explicitly in the doc under the table).
Every file on the target list must appear in at least one row OR in a "clean files" list appended below the table.

- [ ] **Step 4: Commit**

```bash
git add docs/audits/2026-07-18-v1-defect-log.md
git commit -m "Seed defect log from static code audit (finalize Phase A)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Verify legal URLs and apple-app-site-association are live

**Files:**
- Modify (append results): `docs/audits/2026-07-18-v1-defect-log.md`

**Interfaces:**
- Consumes: defect log from Task 4.
- Produces: verified-URLs section in the defect log; any failure is a `CODE-*` P0 row (App Review requires a working privacy URL).

- [ ] **Step 1: Check the three URLs**

Run:
```bash
for u in https://teecircle.app/privacy https://teecircle.app/terms https://teecircle.app/.well-known/apple-app-site-association; do
  echo "$u -> $(curl -s -o /dev/null -w '%{http_code}' -L "$u")"
done
```
Expected: `200` for all three.

- [ ] **Step 2: Record results**

Append to the defect log:

```markdown
## URL verification (Task 5)

| URL | HTTP status | Date |
|-----|-------------|------|
| https://teecircle.app/privacy | <status> | 2026-07-18 |
| https://teecircle.app/terms | <status> | 2026-07-18 |
| https://teecircle.app/.well-known/apple-app-site-association | <status> | 2026-07-18 |
```

(Fill `<status>` with the actual curl results — never leave the placeholders.)
If any status is not 200: add a `CODE-*` P0 row to the defect table AND retry against `https://teecircle.vercel.app/...` — if the vercel.app URL works while teecircle.app fails, the defect is "custom domain misconfigured," which is a Vercel dashboard fix for the owner.

- [ ] **Step 3: Commit**

```bash
git add docs/audits/2026-07-18-v1-defect-log.md
git commit -m "Record legal/AASA URL verification results

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: App Store release scaffolding (human checklist + listing copy)

**Files:**
- Create: `docs/release/2026-07-appstore-1.5-checklist.md`

**Interfaces:**
- Consumes: positioning constraint from Global Constraints; existing `HUMAN_STEPS.md` (sign-in dashboard steps).
- Produces: the complete human checklist the owner executes in Phase B to submit 1.5.0. Phase B's plan references this file rather than restating it.

- [ ] **Step 1: Write the checklist file with exactly this content**

```markdown
# App Store 1.5.0 Release Checklist (human steps)

Execute during Phase B, after P0/P1 fixes land. Companion to
`docs/superpowers/specs/2026-07-18-v1-finalize-release-design.md` §7.

## 1. Sign-in config (prerequisite — also feeds the device audit)
- [ ] Work through every unchecked box in `HUMAN_STEPS.md` §1–6 (Apple
      capability, Supabase Apple/Google providers, Google OAuth clients,
      repo placeholders, rebuild). Native sign-in cannot pass audit without this.

## 2. App Privacy questionnaire (App Store Connect → App Privacy)
Declare (based on what the app actually collects):
- [ ] Contact Info: email address (account) — linked to identity, app functionality
- [ ] Identifiers: user ID — linked to identity, app functionality
- [ ] Usage Data: product interaction (PostHog analytics) — not linked (verify
      PostHog config before declaring "not linked"; if user IDs are sent, declare linked)
- [ ] Location: precise location (course search / "near me") — app functionality,
      not linked, not tracking
- [ ] User Content: photos only if avatar upload ships in 1.5.0 (check ProfileScreen)
- [ ] "Data used to track you": NONE (no ad SDKs; keep it that way)

## 3. Screenshots (capture on iPhone 16 Pro Max simulator, 6.9", 1320×2868)
- [ ] 1. Home with 2–3 upcoming rounds ("Your golf weekend, organized")
- [ ] 2. Create round + friend invites ("Make a time, invite the crew")
- [ ] 3. Friends list ("Your golf circle")
- [ ] 4. Voice search results ("Just say when you want to play")
- [ ] 5. Scorecard ("Keep every round")
Seed Account A with realistic data first (real course names, 4 friends, plausible scores).

## 4. Metadata (draft — edit voice, keep the no-GPS-promises rule)
- Name: **Tee Circle**
- Subtitle: **Golf tee times with friends**
- Keywords: `golf,tee time,friends,scorecard,foursome,round,handicap,social,schedule,course`
- Support URL: https://teecircle.app — Privacy URL: https://teecircle.app/privacy
- Description draft:
  > Tee Circle is the easiest way to get your golf group on the course.
  > Add your friends, pick a course, make a time — everyone gets invited and
  > responds in one tap. No more group-chat chaos.
  >
  > • Build your circle: add friends and groups
  > • Make a time: pick course, date, and crew in seconds
  > • One-tap RSVPs with notifications
  > • Voice search: just say when and where you want to play
  > • Keep score hole-by-hole and track your handicap
  >
  > Free to use. Built for the group chat that can never pick a tee time.

## 5. Review readiness
- [ ] Age rating questionnaire: expect 4+
- [ ] Demo account for App Review: create `appreview@...` account, seed with
      1 friend + 1 upcoming round; put credentials in Review Notes
- [ ] Review note: "Sign in with Apple/Google available; email demo account
      provided. Location used for course search only."
- [ ] Account deletion path noted (Profile → Delete account) — reviewers check this

## 6. Ship (Phase B final task)
- [ ] `app.json`: version → 1.5.0, ios.buildNumber → 10 (committed in Phase B)
- [ ] EAS production build → upload → select build in App Store Connect
- [ ] Release option: Manually release this version
- [ ] Submit; on approval, press Release
```

- [ ] **Step 2: Commit**

```bash
git add docs/release/2026-07-appstore-1.5-checklist.md
git commit -m "Add App Store 1.5.0 release checklist and listing copy draft

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Device audit execution (owner) + triage → generate Phase B plan

**Files:**
- Modify: `docs/audits/2026-07-18-v1-defect-log.md` (owner appends `DEV-*` rows; then triage ranks everything)

**Interfaces:**
- Consumes: Task 3 checklist, Task 4/5 defect log, Task 6 §1 sign-in config steps (must be done first or Apple/Google rows will all fail).
- Produces: complete ranked defect log — the input to Phase B's plan.

- [ ] **Step 1 (owner, human):** Complete `HUMAN_STEPS.md` unchecked items (also listed in release checklist §1), produce a fresh dev build on `finalize-v1`, and install on a physical iPhone.

- [ ] **Step 2 (owner, human):** Execute `docs/audits/2026-07-18-v1-device-audit-checklist.md` top to bottom with Accounts A and B, appending a `DEV-*` row to the defect log for every failure. Tick checklist boxes as you go and commit the updated docs.

- [ ] **Step 3: Triage together** — agent proposes severity for each row, owner confirms; re-order the table P0 → P1 → P2. Commit:

```bash
git add docs/audits/
git commit -m "Complete device audit; triage defect log P0-P2

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Write the Phase B plan** — invoke the superpowers:writing-plans skill with the ranked defect log as input. Phase B covers: every P0 fix, every P1 fix, timeboxed P2s, the golden-path polish pass (spec §6), the full audit-matrix re-walk (spec §8), and the §6 "Ship" block of the release checklist. Phase A is complete when that plan exists.

---

## Self-Review (completed 2026-07-18)

- **Spec coverage:** §4 park → Task 1–2; §5 audit → Tasks 3, 4, 7; §7 App Store → Tasks 5, 6; §6 fix/polish and §8 final re-walk → explicitly deferred to Phase B (they depend on audit output that does not exist yet); §9 human-steps risk → Tasks 6 §1, 7.
- **Placeholder scan:** the only angle-bracket tokens are in Task 5's results table with an explicit instruction to fill them with real curl output.
- **Consistency:** defect-log path, severity rubric, and ID prefixes (`CODE-*`/`DEV-*`) are identical across Tasks 3–7; branch names match Tasks 1–2.
