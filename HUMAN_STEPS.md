# B3: Native Apple + Google Sign-In — Human Steps

The code for native Sign in with Apple and Google is in place, but it cannot
work until the following dashboard/config/build steps are completed by a human.

> ⚠️ **A rebuild is required.** `expo-apple-authentication`,
> `@react-native-google-signin/google-signin`, and `expo-dev-client` are native
> modules — they do NOT work in Expo Go or in any existing binary. After
> completing the config below you must produce a new development build (step 6)
> before either button can be tested.

## 1. Apple Developer

- [ ] In [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list),
      select the `com.teecircle.app` App ID and enable the **Sign In with Apple**
      capability. (EAS will regenerate the provisioning profile on the next build;
      `app.json` already sets `ios.usesAppleSignIn: true`.)

## 2. Supabase — Apple provider

- [ ] Supabase Dashboard → Authentication → Providers → **Apple** → Enable.
- [ ] Add `com.teecircle.app` to **Authorized Client IDs**.
- [ ] No Services ID or client secret is needed for the native iOS flow
      (`signInWithIdToken`) — those are only for the web OAuth flow.

## 3. Google Cloud Console

- [ ] Configure the **OAuth consent screen** (External, app name "Tee Circle",
      support email, logo) in a Google Cloud project.
- [ ] Create an **iOS OAuth client ID** with bundle ID `com.teecircle.app`.
      Note two values it gives you:
      - the client ID: `XXXX.apps.googleusercontent.com`
      - the reversed **iOS URL scheme**: `com.googleusercontent.apps.XXXX`
- [ ] Create a **Web application OAuth client ID** (no redirect URIs needed for
      the native flow). Note its client ID — Supabase validates the ID token
      audience against this.

## 4. Supabase — Google provider

- [ ] Supabase Dashboard → Authentication → Providers → **Google** → Enable.
- [ ] Set the **Client ID** to the *Web* client ID.
- [ ] Add the *iOS* client ID to **Authorized Client IDs** (comma-separated
      list) so ID tokens issued to the iOS app are accepted.

## 5. Fill placeholders in the repo

- [ ] `app.json` → plugins → `@react-native-google-signin/google-signin` →
      `iosUrlScheme`: replace `com.googleusercontent.apps.PLACEHOLDER` with the
      real reversed iOS URL scheme from step 3.
- [ ] `eas.json` → all three build profiles (`development`, `preview`,
      `production`) → env:
      - `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID`: the iOS client ID
      - `EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID`: the Web client ID
- [ ] If you use `npx expo start` locally, also put both values in your local
      `.env` so the dev client picks them up.

## 6. Rebuild + test

- [ ] `eas build --profile development --platform ios`
- [ ] Install the build. **Google** can be tested on the iOS Simulator.
- [ ] **Apple** sign-in requires a real device (Simulator Apple auth is
      unreliable) — test via the dev build on-device or TestFlight.
- [ ] Verify for both providers:
      - Tapping the button and cancelling shows no error (silent).
      - Completing sign-in lands in the app; a brand-new user is routed to the
        Username screen (OAuth users have no username yet).
      - The Apple button only appears on iOS; it is never smaller/less
        prominent than the Google button.
