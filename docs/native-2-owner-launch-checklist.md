# TeeCircle Owner Launch Checklist

The single list to execute cold before/around launch. Each item links to the doc with the full detail (SQL, exact steps) rather than duplicating it here — follow the link, then come back and tick the box.

## 1. SQL editor migrations (in order)

Paste each file wholesale into the Supabase SQL editor, in this order:

- [ ] `supabase/migrations/20260719120000_fix_bootstrap_roster_null_is_current_user.sql` — may already be applied during bring-up (2026-07-19 session); it is create-or-replace idempotent, safe to re-run. Verify with:
  ```sql
  select proname from pg_proc join pg_namespace n on n.oid = pronamespace
  where proname in ('get_trip_bootstrap_unfiltered_v1');
  ```
  returning a row whose body coalesces `isCurrentUser` (or simply re-run the file).
- [ ] `supabase/migrations/20260720130000_tee_circle_v2_account_deletion_finalizer.sql`
- [ ] `supabase/migrations/20260720140000_tee_circle_v2_decline_trip_seat.sql`

(Full context: `docs/superpowers/plans/2026-07-20-native2-m2-lean-gaps.md` → Deferred Owner Steps.)

## 2. Deploy the `delete-account-v1` edge function

- [ ] `npx supabase login` (if not already), then `npx supabase functions deploy delete-account-v1`
- [ ] Or: Supabase dashboard → Edge Functions → upload from `supabase/functions/delete-account-v1/`
- [ ] JWT verification stays on (`supabase/config.toml` → `[functions.delete-account-v1]` → `verify_jwt = true`)

## 3. Snapshot pipeline

- [ ] Execute `docs/native-2-snapshot-pipeline-steps.md` in full (worker secret, cron SQL, verify)

## 4. Follow-Live (when Vercel account is healthy)

- [ ] Set `SUPABASE_URL` env var in Vercel, redeploy
- [ ] Enable public previews:
  ```sql
  update tee_internal.runtime_flags set enabled = true where key = 'public_previews_enabled';
  ```
- [ ] Verify a share link renders the public Follow-Live page

## 5. Google Places key

- [ ] Mint an iOS-restricted key in Google Cloud Console (restrict to Places API New + app bundle id `com.teecircle.app`)
- [ ] Put it in `native/Config/Secrets.xcconfig` as `TEE_GOOGLE_PLACES_API_KEY = <key>` — never commit it (public repo)

## 6. Google OAuth consent screen branding

- [ ] Verify the OAuth consent screen App name for project number `350395562792` says "Tee Circle" (was "tiktokmarketing")
- [ ] Rename path: console.cloud.google.com → that project → Google Auth Platform / OAuth consent screen → Branding → App name

## 7. Supabase Auth dashboard

- [ ] Email OTP length = 6 (BRING-3 — confirm it stuck)
- [ ] Real SMTP (Resend/Postmark) configured before launch (spec §10)

## 8. M0 exit confirmation

- [ ] Tick `docs/native-2-device-bringup-steps.md` §4 (three sign-ins + relaunch)
- [ ] Tick `docs/native-2-device-bringup-steps.md` §5 (worktree removal)
- [ ] Commit the ticks

## 9. On-device production checks

- [ ] Account deletion end-to-end with a throwaway account
- [ ] Decline a seat from a second account
- [ ] Course autocomplete once the Places key lands (item 5 above)
- [ ] The Golfers (recent partners) tab shows real data (spec §6)

## 10. Kill-switch notes

- [ ] `purchases_required` stays **false** — free live scoring (owner decision, 2026-07-19)
- [ ] `live_activity_pushes_enabled` stays **false**
