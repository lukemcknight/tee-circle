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
- [ ] Usage Data: product interaction (PostHog analytics) — linked to identity
      (AuthContext.tsx:181 calls posthog.identify(user.id, { email }); email is
      sent too. If Phase B removes the identify call, downgrade to not-linked.)
- [ ] Location: precise location (course search / "near me") — app functionality,
      not linked, not tracking
- [ ] User Content: none — no avatar upload exists (initials-only avatar, no
      image-picker dependency); Phase B may optionally remove the unused
      `NSPhotoLibraryUsageDescription`/`NSCameraUsageDescription` strings from
      app.json.
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
