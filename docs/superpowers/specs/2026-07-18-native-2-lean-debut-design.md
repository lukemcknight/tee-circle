# TeeCircle 2.0: Lean Debut — Design

**Date:** 2026-07-18
**Status:** Approved in brainstorming — pending written-spec review
**Supersedes:** the public-release goal of `2026-07-18-v1-finalize-release-design.md` (Phase B of that spec is canceled; its Phase A artifacts are recycled here).

## 1. Context & decision

Phase A of the v1 finalize project (audit + release scaffolding, branch `finalize-v1`) completed on 2026-07-18. Before the device audit ran, the owner evaluated the parked native rewrite ("TeeCircle 2.0", committed at `trip-tournament-engines` @ `40d9afc`) and decided — with full awareness of the tradeoffs — that 2.0 is the app TeeCircle should ship.

Motivations (all four, explicitly): 2.0 looks and feels like the product they want; the GPS rangefinder ambition is better served by a native foundation; finishing the Expo app felt like polishing something slated for replacement; substantial working code already exists.

A completeness assessment (`.superpowers/sdd/native2-assessment.md`) established 2.0's real state: auth (email OTP/Apple/Google), username onboarding, offline-queued hole-by-hole scoring, handicap, profile, and the trip/leaderboard core are REAL and contract-tested. But the rewrite dropped v1's friend graph, groups, voice search, and Google Places course search; account deletion is UI-only (`unsupportedCapabilities` — no server command); and the app has never successfully run interactively (simulator/disk-image blockers, no device run).

## 2. Decisions log

| Question | Decision |
|---|---|
| Which app is TeeCircle? | The native 2.0 app. App Store debut = version 2.0.0 |
| Expo public release (v1 Phase B) | **Canceled.** Expo stays on TestFlight untouched until 2.0 replaces it |
| v1 defect log (23 findings) | Retired with the Expo app, EXCEPT CODE-17 (auth-user survives deletion) — fixed server-side by this project for both apps |
| First 2.0 release scope | **Lean:** social core only; tournaments, $29.99 unlock, Live Activities stay dark behind existing kill switches |
| Social model at launch | **Invite links** (2.0's design: create round → share link → claim/RSVP) + Golfers recent-partners list. No friend graph, no groups at launch |
| GPS tracker | Next design cycle, immediately after the 2.0 debut ships |
| Owner-reported auth issues (2026-07-18) | In scope: OTP email template fix (root cause confirmed: default Supabase template sends link, no `{{ .Token }}` code), Google button restyle, sign-up copy |

## 3. Repo mechanics

- New branch **`native-2`** cut from `trip-tournament-engines` @ `40d9afc` (that commit contains the full tree: Expo app, `native/`, supabase functions/migrations, website). 2.0 work proceeds there — separated from the parked tournament *strategy* branch.
- The main checkout (`/Users/lukemck/Development/tee-circle`) moves to `native-2`. The `../tee-circle-2` worktree becomes disposable once that happens.
- Recyclable Phase A docs are copied from `finalize-v1` onto `native-2`: the App Store checklist (rewritten for 2.0), this spec's companion audit method, and the `.gitignore` hygiene entries.
- `finalize-v1` is retired but kept for reference; nothing is deleted.

## 4. Milestone 0 — device bring-up (first, blocking everything)

The app has never run interactively; no other milestone starts until it does.

- Resolve the simulator/disk-image mount and UI-test CoreSimulator blockers noted in the assessment; get signing working; launch on the owner's physical iPhone.
- Supabase config (owner dashboard steps, HUMAN_STEPS-style checklist): add `{{ .Token }}` to the OTP email template; enable native Apple and Google providers for `com.teecircle.app`; decide SMTP (built-in dev mailer is rate-limited to ~2 emails/hour — acceptable for bring-up, custom SMTP e.g. Resend/Postmark required before launch).
- **Exit criteria:** owner signs in on hardware via all three methods (email code, Apple, Google).

## 5. Milestone 1 — the front door

- Replace the SDK-rendered `GoogleSignInButton` (button-inside-a-button today, `AuthenticationView.swift:181-197`) with a custom 52pt/14pt-radius button matching the Apple button's geometry, per Google brand guidelines (G logo + "Continue with Google").
- Add copy to the email form making clear the six-digit code signs you up: new accounts are created automatically (`shouldCreateUser: true` is already the behavior).
- **Copy rule (owner directive, 2026-07-20):** user-facing strings never reference
  internal versioning ("TeeCircle 1.0", "2.0", "legacy"). One continuous app.

## 6. Milestone 2 — lean-scope gaps

- **Course search:** port v1's Google Places integration (`src/lib/placesApi.ts`) to a Swift service; free-text entry remains the fallback. API key lives in `Config/Secrets.xcconfig` (git-ignored), restricted appropriately for iOS.
- **RSVP decline:** add the decline path to the invite/RSVP flow (claim flow is real; decline UI is absent).
- **Real account deletion:** a server-side command (edge function) that deletes app data AND the Supabase auth user (admin API). Both apps share one Supabase project, so this also closes v1's CODE-17 P0 for existing users. The 2.0 client replaces its `unsupportedCapabilities` stub with this call.
- Confirm the Golfers recent-partners surface works against production data.

## 7. Milestone 3 — release

- Slimmed runbook gates: execute the legacy-baseline migration contract as specified in `docs/native-2-release-runbook.md` §1; upload version 2.0.0 (build ≥ 10); App Privacy questionnaire (carry Phase A's corrected answers, re-verified against what 2.0 actually uses — e.g. confirm whether PostHog exists in 2.0 at all); screenshots; listing copy recycled from `docs/release/2026-07-appstore-1.5-checklist.md` §4 (still generic social-golf, still no GPS promises); demo account; submit.
- Verify tournament, purchase, and live-activity kill switches are OFF in the shipped build. APNs/RevenueCat/IAP release gates from the original runbook are deferred with their features.
- Device audit: the Phase A checklist method, rewritten for 2.0's flows, walked by the owner on hardware before submission.

## 8. Explicitly out of scope

- Friend graph, groups, voice search (dropped from launch; legacy v1 data remains readable server-side per the migration contract's compatibility window).
- Tournaments, paywall/RevenueCat, Live Activities, iMessage-extension polish beyond what invite links require.
- GPS (next spec, starts right after debut).
- Any Expo app work beyond leaving TestFlight as-is.

## 9. Testing

- Existing contract tests must stay green throughout.
- New Swift code (course-search service, deletion client+function) is built TDD.
- Final gate: owner walks the rewritten device-audit checklist on hardware.

## 10. Risks

- **Bring-up unknowns dominate:** an app that has never run may surface issues that reshape Milestones 1-3; that is why Milestone 0 is first and blocking.
- **Email deliverability:** launch requires real SMTP; the template fix alone is not enough at scale.
- **App Review:** sign-in and account deletion are exactly what reviewers exercise; Milestone 2's deletion work is a review prerequisite, not polish.
- **Human gates:** Supabase dashboard, Apple signing, App Store Connect are owner-only; each milestone ships a HUMAN_STEPS-style checklist for them.
- **v1 TestFlight users:** their friend/group data won't surface in 2.0's UI at launch (legacy tables remain readable server-side). Accepted consequence of the lean scope.
