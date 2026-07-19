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
