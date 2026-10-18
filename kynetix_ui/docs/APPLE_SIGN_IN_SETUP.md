# Sign in with Apple: finishing the setup

The app code for Sign in with Apple is done. What is left is account setup on
Apple's side and one form in Supabase. None of it needs a Mac or an iPhone.

How the app behaves today:

- The "Continue with Apple" button only appears once the Apple provider is
  switched on in Supabase. The app checks
  `https://sjrcqvqhycxtwwbivizy.supabase.co/auth/v1/settings` at launch of the
  sign-in screen. While Apple is off (the current state), nobody sees the button.
- On iPhone and iPad the button opens Apple's native sheet. The app sends
  Apple a SHA-256 hashed nonce and gives Supabase the raw nonce with the
  identity token. If Apple shares the person's name (first sign-in only), it is
  saved to the profile as `full_name`.
- On Android the button opens Apple's sign-in page in the browser through
  Supabase. After signing in, the browser returns to the app through
  `kynetix://login-callback`, which is already registered in the Android
  manifest and in the Supabase redirect allow list.
- `ios/Runner/Runner.entitlements` already contains the
  `com.apple.developer.applesignin` entitlement, and the Xcode project points
  to it for Debug, Release and Profile builds.

Values used below:

| Item | Value |
| --- | --- |
| iOS bundle ID | `com.kynetix.app` |
| Supabase project | `sjrcqvqhycxtwwbivizy` |
| Supabase domain | `sjrcqvqhycxtwwbivizy.supabase.co` |
| Return URL | `https://sjrcqvqhycxtwwbivizy.supabase.co/auth/v1/callback` |
| Suggested Services ID | `com.kynetix.app.signin` |

## 1. Join the Apple Developer Program

1. Make sure you have an Apple Account with two-factor authentication on. You
   can create one and turn on two-factor at https://account.apple.com using
   an SMS phone number; no Apple device is required.
2. Go to https://developer.apple.com/programs/enroll and choose "Start your
   enrollment". Enrollment works in a web browser.
3. Choose Individual (uses your legal name as the seller) or Organization
   (needs a D-U-N-S number for the company, free from Dun & Bradstreet, which
   can take a few days).
4. Pay the membership fee: USD 99 per year (or the local equivalent).
5. Wait for the confirmation email. Individual accounts are often ready within
   a day or two; organizations can take longer.

## 2. Find your Team ID

1. Sign in at https://developer.apple.com/account.
2. Open "Membership details". Copy the 10-character Team ID (for example
   `AB12CD34EF`). Keep it for step 6.

## 3. Create the App ID (for the iOS app)

1. Go to Certificates, Identifiers & Profiles, then Identifiers:
   https://developer.apple.com/account/resources/identifiers/list
2. Click the plus button, choose "App IDs", then "App", then Continue.
3. Description: `Kynetix`. Bundle ID: choose Explicit and enter
   `com.kynetix.app`.
4. In the Capabilities list, tick "Sign in with Apple". Leave it as
   "Enable as a primary App ID".
5. Click Continue, then Register.

If the App ID already exists, open it, tick "Sign in with Apple", and Save.

## 4. Create the Services ID (for Android and web)

1. In Identifiers, click the plus button and choose "Services IDs", then
   Continue.
2. Description: `Kynetix sign in`. Identifier: `com.kynetix.app.signin` (it
   must be different from the bundle ID).
3. Click Continue, then Register.
4. Open the new Services ID from the list, tick "Sign in with Apple", and click
   "Configure" next to it.
5. Primary App ID: choose `com.kynetix.app`.
6. Domains and Subdomains: `sjrcqvqhycxtwwbivizy.supabase.co`
7. Return URLs: `https://sjrcqvqhycxtwwbivizy.supabase.co/auth/v1/callback`
8. Click Next, Done, Continue, then Save.

## 5. Create the Sign in with Apple key

1. Go to Keys: https://developer.apple.com/account/resources/authkeys/list
2. Click the plus button. Key name: `Kynetix Sign in with Apple`.
3. Tick "Sign in with Apple" and click "Configure". Choose `com.kynetix.app` as
   the primary App ID, then Save.
4. Click Continue, then Register.
5. Click Download. You get a file named like `AuthKey_XXXXXXXXXX.p8`. Apple
   lets you download it only once, so store it somewhere safe (a password
   manager). Never commit it to git.
6. Copy the 10-character Key ID shown on that page.

## 6. Generate the client secret

Supabase needs a client secret for the Android (web) flow. It is a JWT signed
with the `.p8` key, and Apple caps its life at 6 months.

Option A, easiest: on the Supabase docs page for Apple login
(https://supabase.com/docs/guides/auth/social-login/auth-apple) there is a
secret generator. Enter the Team ID, Key ID, Services ID
(`com.kynetix.app.signin`) and the contents of the `.p8` file. It runs in your
browser and gives you the JWT.

Option B, a local script (needs Node.js 18 or newer). In an empty folder run
`npm install jose`, then save this as `apple-secret.mjs` and run
`node apple-secret.mjs`:

```js
import { readFileSync } from 'node:fs';
import { importPKCS8, SignJWT } from 'jose';

const teamId = 'YOUR_TEAM_ID';
const keyId = 'YOUR_KEY_ID';
const servicesId = 'com.kynetix.app.signin';
const p8 = readFileSync('./AuthKey_YOUR_KEY_ID.p8', 'utf8');

const key = await importPKCS8(p8, 'ES256');
const now = Math.floor(Date.now() / 1000);
const jwt = await new SignJWT({})
  .setProtectedHeader({ alg: 'ES256', kid: keyId })
  .setIssuer(teamId)
  .setSubject(servicesId)
  .setAudience('https://appleid.apple.com')
  .setIssuedAt(now)
  .setExpirationTime(now + 180 * 24 * 60 * 60) // about 6 months, Apple's limit
  .sign(key);

console.log(jwt);
```

Put a reminder in your calendar for 5 months from today. When the secret
expires, Apple sign-in on Android stops working until you generate a new one
and paste it into Supabase (step 7). The native iPhone flow does not use the
secret, so it keeps working.

## 7. Turn on Apple in Supabase

1. Open https://supabase.com/dashboard/project/sjrcqvqhycxtwwbivizy/auth/providers
2. Open "Apple" and switch "Enable Sign in with Apple" on.
3. Client IDs: `com.kynetix.app.signin,com.kynetix.app` (Services ID first,
   then the iOS bundle ID, comma separated, no spaces).
4. Secret Key (for OAuth): paste the JWT from step 6.
5. Leave the callback URL as shown
   (`https://sjrcqvqhycxtwwbivizy.supabase.co/auth/v1/callback`).
6. Save.

That is all. The next time someone opens the sign-in screen, the app sees
Apple as enabled and shows "Continue with Apple". No app update is needed.

## 8. Test on Android, without an Apple device

1. Install a build on an Android phone or emulator and open the sign-in screen.
   "Continue with Apple" should now show under "Continue with Google".
2. Tap it. The browser opens Apple's sign-in page.
3. Sign in with any Apple Account (the one from step 1 works). Apple asks for
   a code sent to your trusted phone number.
4. Choose whether to share or hide your email, then continue.
5. The browser hands back to Kynetix and you land signed in (onboarding for a
   new account).
6. In Supabase, Authentication, Users, you should see the new user with
   provider "apple".

If the browser shows an Apple error such as `invalid_client`, recheck the
Services ID, the domain and return URL in step 4, and the Client IDs and secret
in step 7. If it does not come back to the app, check that
`kynetix://login-callback` is still in Authentication, URL Configuration,
Redirect URLs.

## 9. iPhone builds and App Store review

- iOS builds need a Mac with Xcode, or a cloud build service such as Codemagic
  or Xcode Cloud. The entitlement is already in the project. When signing, use
  automatic signing with your team, or a provisioning profile for
  `com.kynetix.app` created after step 3 so it includes Sign in with Apple.
- App Store Review Guideline 4.8 (Login Services): an iOS app that offers a
  third-party or social login (Kynetix offers Google) must also offer an
  equivalent privacy-focused login. Sign in with Apple meets this. Finish the
  steps above before submitting to the App Store, or the review is likely to
  be rejected.
- Guideline 5.1.1(v): apps with account creation must let people delete their
  account in the app. Kynetix already has account deletion. Apple also asks
  apps to revoke the Apple token when an Apple user deletes their account;
  plan that as a follow-up for the delete-account flow.
- Hide My Email: people can choose a private relay address ending in
  `@privaterelay.appleid.com`. For emails from Kynetix (for example password
  resets) to reach them, register your sending domain or address under
  Certificates, Identifiers & Profiles, Services, "Sign in with Apple for
  Email Communication", and set up SPF for that domain.
