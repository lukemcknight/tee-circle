# TeeCircle: v1 Finalize & Public Release — Design

**Date:** 2026-07-18
**Status:** Approved in brainstorming — pending written-spec review
**Scope:** Take the existing TeeCircle app (v1.4.0 build 9, TestFlight) to a public App Store release. No new features. GPS tracking is the next project and is explicitly out of scope here.

## 1. Context & strategic frame

The owner has decided to compete head-on with established golf apps (18Birdies, TheGrint) by adding GPS course tracking to TeeCircle. Before that work starts, the existing app — social circles, friend management, tee-time scheduling, scorecards, voice search — gets finished and shipped publicly. This project is that finish line.

Standing decision changes vs. the 2026-07-13 trip-tournament spec:

- The **trip tournament work is parked, not abandoned.** The `trip-tournament-engines` branch (plan 1/3 implemented, ~65 dirty/untracked files) gets committed as WIP and pushed, then left alone. It stays resumable.
- The **GPS tracker becomes the new differentiator** and will get its own spec → plan → implementation cycle immediately after this project.

## 2. Goal & success criteria

TeeCircle v1.5.0 is submitted for public App Store release within ~2 weeks, and released as soon as Apple approves. Concretely:

- Every shipped flow has been walked end-to-end on a real device and works.
- The golden path — first launch → sign in → add friend → make a time — has had a polish pass (empty states, loading, errors, keyboard behavior).
- The tournament WIP is safely committed and pushed on its branch.
- No features cut, no features added. ("Cut scope" was clarified to mean: add nothing new.)

## 3. Decisions log (from brainstorming)

| Question | Decision |
|---|---|
| Fate of trip-tournament WIP | Park cleanly: commit + push to its branch, stop building |
| What "finalize" means | Public App Store release + fix broken flows + UX polish pass |
| Features to cut | None — keep friends, groups, tee times, scorecards/handicap, voice search |
| Known-broken list | None known; full audit is part of the project |
| Timebox | ~1–2 weeks; polish concentrated on the golden path |
| Approach | A: audit-driven release train |

## 4. Step 0 — Park the tournament WIP

- Commit all dirty and untracked files on `trip-tournament-engines` as WIP commit(s); push the branch.
- Create `finalize-v1` off `main` for all work in this project.
- If the audit surfaces a bug whose fix already exists on the tournament branch (e.g. the modified `supabase/functions/_shared/auth.ts`), cherry-pick that single fix — do not merge the branch.

## 5. The audit (days 1–2)

A scripted end-to-end walk of every flow on a device build, using **two test accounts** (friend/invite flows cannot be exercised solo). Matrix:

- **Auth:** email, Apple, and Google sign-in. Verify the unchecked dashboard steps in `HUMAN_STEPS.md` (Apple capability, Supabase providers, Google OAuth clients) are actually complete; native sign-in is a prime P0 suspect.
- **Onboarding:** welcome → username claim → landing state.
- **Friends:** search/add, accept, remove, friend detail, friend count.
- **Groups:** create, view details, manage members.
- **Tee times:** create round (course search included) → invite friends → responses → review → results.
- **Scoring:** hole-by-hole entry, round detail, handicap calculation.
- **Voice search:** query → parse → results (external deps: TeeItUp inventory, Gemini parse).
- **Profile & account:** profile edit, account deletion (exists in `ProfileScreen` — must work; Apple requires it), sign out.
- **Push notifications:** invite and response notifications arrive on device.

Output: one ranked defect list committed to `docs/` with three severities — **P0** (release blocker: broken, crashes, or App Review rejection risk), **P1** (works but bad experience), **P2** (cosmetic).

## 6. Fix & polish (days 3–9)

- Fix all P0s, then P1s. P2s only if time remains inside the timebox.
- Then one polish pass strictly scoped to the golden path (first launch → sign in → add friend → make a time): empty states, loading states, error messages, keyboard handling.
- Hard rules: **no new features; no refactors beyond what a fix requires.**

## 7. App Store release (days 10–14)

- App Privacy questionnaire in App Store Connect.
- Confirm privacy policy and terms URLs are live (website already has `Privacy.tsx` / `Terms.tsx` — verify deployed URLs resolve).
- Screenshots for required device sizes; app metadata (description, keywords) written around "schedule rounds with your golf buddies."
- Positioning constraint: the listing must still make sense when GPS ships next — generic social-golf framing, no promises of unshipped features.
- Age rating, demo account credentials for App Review.
- Bump version to 1.5.0, build, submit for review, release publicly.

## 8. Verification

- Every fix is verified on device before its task is considered done.
- Final gate before submission: a full re-walk of the §5 audit matrix.

## 9. Risks

- **Apple review timing** is outside our control; the day 10–14 window is a buffer, and "submitted" may precede "live" by days.
- **Human-only steps** (Apple/Google/Supabase dashboards, App Store Connect) are written up as checklists in the style of `HUMAN_STEPS.md` for the owner to execute.
- **Second test account** required for friend-flow testing.
- **External dependencies** (TeeItUp inventory, Gemini parsing) mean some voice-search failures may be documented-and-accepted rather than fixed.

## 10. Out of scope

- GPS course tracking (next project; own spec).
- Tournament engine, per-trip IAP, live activities, RevenueCat (parked).
- League/season features.
- Any new feature work whatsoever.
