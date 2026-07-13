# TeeCircle: Trip Tournament Engine — Design

**Date:** 2026-07-13
**Status:** Approved in brainstorming — pending written-spec review
**Scope of this spec:** the MVP slice only (see §5). Fast-follows are named but not specified here.

## 1. Context & problem

TeeCircle is a working iOS golf app (v1.4.0, on TestFlight) with social circles, tee-time voice search over TeeItUp inventory, round scheduling, and hole-by-hole scorecards. Its blocker has never been features — it's monetization, which in turn gates the owner's willingness to market it.

Deep research (2026-07, [[monetization-research]]) killed the obvious models: reselling/alerting on tee-time inventory is non-commercial-licensed by GolfNow/TeeItUp and already offered free natively by the platform; booking affiliate revenue is approval-gated and inaccessible at small scale. The viable path is to monetize a layer TeeCircle **owns** — user-entered competition data — rather than a layer someone else owns (inventory).

The improvement/stats layer (handicaps, trends) is explicitly **out of scope**: the owner has a separate app for that. TeeCircle's identity is the **social/organizer** layer.

## 2. Product identity & positioning

**TeeCircle is the app for running your buddies' golf trip, built around the competition.**

Existing coordination features are re-cast as the **free acquisition wedge**; the tournament engine is the **paid spine**. The go-to-market funnel:

1. Market the current app on its existing, already-delivered promise: *"schedule rounds with your golf buddies."* This gets crews in the door for free — and can begin **immediately**, before the tournament engine ships.
2. Free users form a circle and use the app to organize rounds. Retention here is load-bearing: the upsell only converts if the crew already lives in the app.
3. Once a crew exists, they discover the trip tournament engine ("it runs our whole golf trip too?") and convert via a per-trip purchase.

The free coordination layer does not need to monetize directly. Its job is to manufacture the exact audience the paid layer sells to.

## 3. Personas

- **Primary — the trip captain.** Runs the annual buddies' trip: 8–16 players, multiple rounds over a weekend. Wants the trip's competition to feel *organized and official* — real formats, live standings, weekend-long trash talk. Uses the product 1–2×/year.
- **Fast-follow — the league commissioner.** Runs a recurring season (office/men's-club league). Natural fit for a subscription tier, not per-trip. Out of scope for this spec; validates after the trip model proves out.

## 4. Monetization

- **Model: per-trip unlock.** The captain pays once to flip a trip to Pro, which unlocks the full tournament engine **for every player in that trip**, on all their devices. Chosen over subscription because the trip captain uses the product 1–2×/year — a recurring charge is the wrong mental model; an event purchase at peak motivation (trip setup) is the right one, priced trivially against a trip that already costs each player hundreds.
- **Price:** treat as a testable variable, ~$20–40 per trip. Not locked here.
- **Viral loop:** one captain's purchase puts the Pro experience in ~12 hands; some of those players run their own trips. The paid action and the growth action are the same event — build around this.
- **Paywall placement:** at the point of maximum *revealed* value, not hidden behind it. The captain can build the trip and add the roster for free; the wall sits at "activate the tournament / go live." Free users must be able to *see* that the trip/leaderboard experience exists in order to want it — that visibility is what drives the funnel in §2.
- **Subscription later:** a League/Season tier is the natural home for recurring billing and serves persona #2 — a fast-follow, not built now.

## 5. MVP scope

**In scope (the smallest real, sellable product):**

- **Trip container** — a parent entity grouping multiple rounds into one event with standings.
- **Two format engines** — **skins** and **Stableford** (the two most-loved, see §7).
- **Live leaderboard** — standings across the trip's rounds, updating in real time as scores are entered.
- **Per-trip unlock (IAP)** — App Store in-app purchase + entitlement gating for the above.

**Explicitly out (fast-follows, named so scope stays honest):**

- Ryder Cup / team match-play formats + team assignment (highest emotional payoff; leans on the same engine, cheap to add after).
- Trash-talk feed tied to leaderboard moments.
- League/Season subscription tier (persona #2).
- Nassau, wolf, and other formats.

## 6. Architecture

**Reuse (already built — the substrate):**

- `scorecards` (per player, per round: gross/net/handicap) and `scorecard_holes` (per-hole strokes) — hole-by-hole capture already works via `RoundScoreScreen` (610 lines).
- `RoundDetailScreen` already renders every player's scores side by side.
- `groups`/`group_members` (the crew), `rounds`, `round_responses` (RSVP), auth, profiles, handicap data.

**Net-new:**

- **Trip container** — new `trips` table (id, name, created_by, date range, status, entitlement/pro flag, format config) plus a link from rounds to a trip (nullable `trip_id` FK on `rounds` is the least-invasive option). A trip roster (which players are in the competition) derived from participating scorecards or an explicit `trip_players` join.
- **Format engines** — pure TypeScript functions: `(holes for the trip's rounds, config) → standings`. No server-side scoring logic. Kept pure so they are unit-testable in isolation (TDD), which matters because scoring rules are fiddly and golfers will not tolerate a wrong leaderboard.
- **Live leaderboard** — each client subscribes to Supabase realtime on `scorecard_holes` for the trip's rounds and recomputes standings locally via the pure format engine. This avoids server-side format duplication and gives every player a live-updating board. New leaderboard screen.
- **Entitlement** — a trip carries a Pro flag set by a verified IAP. RevenueCat recommended over raw StoreKit to smooth receipt validation and cross-device entitlement (all players in a paid trip see Pro). Gate the tournament activation + Pro formats + live leaderboard behind it.

**ToS note:** the tournament engine runs entirely on **user-entered scores**. It touches no GolfNow/TeeItUp inventory, so it is free of the non-commercial-license exposure that blocks the tee-time-based models. This is the point.

## 7. Format rules (MVP)

Both formats compute on **net** score by default (uses existing handicap data; net is the inclusive choice for mixed-handicap buddy trips), with **gross** as a per-trip config option.

- **Skins.** Each hole is worth one "skin." The player with the lowest score on a hole wins it. **Ties carry the skin over** to the next hole (the pot accumulates), which is the fiddly, must-be-exactly-right part. A trip-long skins board tallies skins won across all rounds.
- **Stableford (standard).** Points per hole vs. par by net score: albatross 5, eagle 4, birdie 3, par 2, bogey 1, double-bogey-or-worse 0. Trip standings = total points across rounds, highest wins. (Modified Stableford is a variant; standard only for MVP.)

## 8. Risks

- **Format correctness (highest).** Wrong skins carryovers or Stableford points destroy trust instantly. Mitigate with pure, exhaustively unit-tested engines (TDD, known-scorecard fixtures).
- **IAP integration.** App Store IAP + cross-device entitlement is fiddly; RevenueCat reduces but doesn't eliminate the work. Budget for App Store review of the paywall.
- **App Store review.** Per-trip unlock must be a compliant IAP; confirm the free/paid boundary reads as legitimate freemium.
- **Free-tier retention.** The funnel fails if crews don't stick on the free layer. Not a build risk per se, but a product-quality bar the free experience must clear.

## 9. Success criteria

- A captain can create a trip, add rounds/roster, and unlock it via a real IAP.
- Every player in an unlocked trip sees a live leaderboard that updates as scores are entered, ranked correctly by skins and Stableford.
- Format engines pass a suite of known-scorecard unit tests including tie/carryover edge cases.
- The free→paid boundary is visible (free users can see a trip exists and hit the wall at activation).

## 10. Resolved decisions

Open questions resolved by the owner's "make the calls, I'll feel it when built" delegation (2026-07-13). All are revisitable after hands-on testing.

- **Price:** placeholder $29.99 per trip — IAP product config, swappable anytime; real number tested post-launch.
- **Trip roster:** explicit `trip_players` table (first-class roster, set before scores exist; teams fast-follow attaches here).
- **Free/paid boundary:** captain builds the full trip (crew, rounds, leaderboard shell) for free; the paywall is the **"Start Tournament"** action that activates live scoring + skins/Stableford + the live board. Value fully visible before the wall.
- **Entitlement model:** **trip-scoped**, not per-user. The captain's verified purchase flips `trips.is_pro = true` via a server-side (Supabase edge function) receipt verification; all players in that trip then read Pro. This is what lets one purchase unlock ~12 devices.
- **Purchases:** RevenueCat (over raw StoreKit) for receipt validation; entitlement still stored trip-scoped in Supabase per above.
