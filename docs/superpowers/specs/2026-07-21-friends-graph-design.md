# TeeCircle 2.0: Friends Graph — Design (Spec 2 of the pre-debut redesign)

**Date:** 2026-07-21
**Status:** Approved in brainstorming — pending written-spec review
**Supersedes:** `2026-07-18-native-2-lean-debut-design.md` §2's "no friend graph at launch" decision — the owner reopened it: the debut ships in-app user adding.
**Depends on:** Spec 1 (`2026-07-21-design-system-brand-refresh-design.md`) — all UI here is built from Spec 1's tokens/components. Implemented strictly after Spec 1.

## 1. Model (owner decision)

**Mutual friends with requests** — search by username → send request → recipient accepts → connected. Consent-based, v1's model rebuilt natively in the v2 house style. One-way follows and non-consensual address-book adds were considered and rejected.

## 2. Server design (v2 house style throughout)

- **Schema (new migration):** `friendships` (canonical ordered pair `user_low < user_high`, status `pending|accepted`, `requested_by`, timestamps; unique on the pair) — the v1-proven shape, rebuilt in the v2 schema with RLS limiting rows to their two members. No separate requests table: a `pending` friendship IS the request.
- **RPCs (versioned commands, api_success/api_error envelope, `native_writes_enabled` gate, request-id, four-role ACL revoke + authenticated grant, registered in the ACL contract):**
  - `search_profiles_v1(p_query)` — username prefix search over public profiles; rate-limited via the existing `consume_public_rate_limit_v1` pattern; returns display name + username + id only.
  - `request_friend_v1(p_user_id)` — creates pending (idempotent; auto-accepts if a reverse pending exists).
  - `respond_friend_request_v1(p_user_id, p_accept)` — accept or decline (decline deletes the row).
  - `remove_friend_v1(p_user_id)` — dissolves an accepted friendship.
  - `get_friends_bootstrap_v1()` — friends + incoming/outgoing pending, for the Friends tab and invite picker.
- **Account deletion:** `finalize_account_deletion_v1` gains `delete from friendships where user_low/user_high = uid` (mirrors v1's cleanup) — small follow-up migration.
- **SQL behavior suites** for every command (happy path, both error paths, no-mutation on failure, begin…rollback flag discipline) + ACL contract rows. RED-first against `run-local-v2.sh`.

## 3. Client design

- **Golfers tab becomes "Friends":** two sections — Friends (the graph) and Recent partners (today's trip-derived list, retained). Tab rename + Spec 1 custom icon.
- **Add flow:** search field (username, ≥3 chars, debounced — reuse the course-search controller pattern), result rows with Add button; pending state shown.
- **Requests:** incoming requests surface at the top of Friends with accept/decline; tab badge count (in-app only — push delivery stays dark for the debut).
- **Invite integration:** the round-roster picker lists friends first (one-tap add), recent partners second, share-link fallback unchanged.
- **Endpoint catalog + `NativeServiceContractTests`** move together; repository/store methods follow the existing actor patterns; fixture mode gets seeded friends for UI tests.

## 4. Verification

- SQL suites green; app suite grows with friends unit/UI tests and stays green; protected baselines hold.
- On-device: two-account end-to-end (request → accept → invite-by-friend → remove), plus deletion of an account with friendships.
- Copy rule binds; production migrations/deploys land on the owner launch checklist as new rows.

## 5. Out of scope

Activity feed, profiles beyond name/username, blocking/reporting (revisit before any public-search scale-up), push-delivered request notifications, contact-book import, QR codes.

## 6. Risks

- **Search abuse/privacy:** username search exposes existence — mitigated by rate limiting and returning minimal fields; blocking deferred consciously.
- **Legacy v1 friendships:** the old Expo tables still hold v1 relationships; migrating them into the new graph is explicitly deferred (the compatibility window keeps them readable; a backfill can be a later fast-follow).
