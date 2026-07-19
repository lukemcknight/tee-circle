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
      "Automatically manage signing" ON. Bundle IDs: com.teecircle.app, com.teecircle.app.messages, com.teecircle.app.widgets.
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
