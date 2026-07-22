# TeeCircle 2.0: Design System & Brand Refresh — Design (Spec 1 of the pre-debut redesign)

**Date:** 2026-07-21
**Status:** Approved in brainstorming — pending written-spec review
**Supersedes:** nothing structurally; extends `2026-07-18-native-2-lean-debut-design.md`. The debut now ships this refresh plus Spec 2 (friends) before App Store submission — the owner's explicit timing call, accepting the submission delay.
**Companion spec:** `2026-07-21-friends-graph-design.md` (Spec 2, implemented after this one).

## 1. Goal & design principles

The app's look (dark "broadcast" surfaces, signal-green accents, rounded cards) is right; its implementation is ad-hoc — per-screen styling against a loose `TeeCircleBrand` palette. This spec turns the identity into a system so future features (GPS, social growth) compose existing pieces instead of crowding the app with bespoke surfaces.

Owner's framing, verbatim intent: "I don't want the whole app to become crowded when I add a few more features" — scalable structure, not reserved tabs.

Principles: evolve, don't replace, the current look; every visual decision lives in one place; components over per-screen styling; the three-tab skeleton (Rounds / Golfers→Friends / Account) stays.

## 2. Workflow (owner decision)

**"I propose, Figma verifies."** The system is designed in code: SwiftUI previews + on-device builds are the review artifacts at each checkpoint; the owner reviews on hardware. After implementation, the system is documented as a Figma library (tokens, components, screens) with the Dev Mode MCP (`.mcp.json` entry `figma`, localhost:3845) keeping code and canvas aligned. Figma is never on the critical path; the desktop-app toggle can happen anytime.

## 3. Token system

New module directory `native/TeeCircle/DesignSystem/` (app target; no new SPM package — YAGNI):

- **Colors** (semantic, derived from today's `TeeCircleBrand`): background tiers (night/raised/card), accent (`signal`), supporting (moss/pine/forest), ink tiers, hairline, destructive. Dark-first; light mode explicitly out of scope for the debut.
- **Typography:** a named scale (display/title/headline/body/caption variants) wrapping the current rounded-black style so screens stop declaring `.font(.system(size: 39, weight: .black, ...))` inline.
- **Spacing & shape:** 4pt-grid spacing tokens; radius tokens (the 14pt controls / 26pt cards pattern); elevation/shadow tokens.
- `TeeCircleBrand` becomes a thin alias layer over the tokens during migration, then is retired.

## 4. Component library

Extracted from the best existing implementations, generalized: primary/secondary buttons (the 52pt/14pt-radius pattern), card container, labeled field (from `LabeledAuthField`), list row, section header, empty state, sheet scaffold, badge/chip, avatar-initials. Each component: one file, SwiftUI preview, used by ≥2 screens or it doesn't get extracted (YAGNI).

## 5. Screen migration

Every existing screen (Auth, ProfileSetup, Home, CreateRound, CreateTrip, TripHub, Scorecard, Leaderboard, Golfers, LegacyRounds/Setup, Profile/Account, InviteClaim, Paywall-dark) is migrated to tokens + components with **no intentional visual redesign** beyond consistency gains — same look, systematized. Migration proceeds screen-group by screen-group with the full suite green at each step (protected baselines: app 60/60, package 38/38, SQL suite). UI-test accessibility identifiers are load-bearing and must not change.

## 6. Brand in-app

- The **TC mark** (source: `assets/dark.png.kra`, 1024×1024 merged art already extracted) becomes an asset-catalog vector/bitmap used at: auth hero (replacing or complementing the drawn `TeeCircleMark`), home header. Tasteful, not plastered.
- **App icon set (iOS 18):** dark icon = the TC-on-black art (flattened, no alpha, per App Store rules); light variant = TC mark on brand-appropriate light/green field (generated; owner eyeballs before lock-in); tinted variant = grayscale derivative. Single 1024 source per variant in `AppIcon.appiconset` with `Contents.json` platform entries.

## 7. Iconography

Custom icon set where identity matters: the three tab-bar icons and signature actions (create round, invite, score). Consistent stroke weight and corner language matching the TC mark's geometry. Delivered as template-rendered assets in the catalog; SF Symbols remain for system furniture (chevrons, share, settings). If custom-icon production stalls, tab icons ship first and action icons ride a fast-follow — the set is additive.

## 8. Verification

- Full suite green after every migration group; final whole-branch review before Spec 2 begins.
- On-device owner checkpoints: (1) tokens+components with two migrated screen groups, (2) full migration, (3) brand/icons landed.
- Copy rule (no 1.0/2.0/legacy) binds every new string; accessibility identifiers preserved.

## 9. Out of scope

Light mode; any navigation-model change beyond polish; friends (Spec 2); GPS; tournament relight; Live Activities; paywall changes; Figma-first authoring.

## 10. Risks

- **Migration churn:** touching every screen risks regressions — mitigated by per-group suite gates and the UI tests' identifier stability rule.
- **Icon quality:** light/tinted variants are generated from a dark-first source; owner review gates lock-in.
- **Submission delay:** accepted explicitly by the owner (redesign-before-submit).
