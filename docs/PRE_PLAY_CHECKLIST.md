# Before you pay the US$25: everything you can do now

Do these in the days before registering on Google Play. When you finally pay,
setup takes about an hour and the only real wait is Google's ID check and the
14-day tester window. Then continue with [PLAY_LAUNCH_GUIDE.md](PLAY_LAUNCH_GUIDE.md).

Tick them off as you go.

---

## Day 1 (about 1 hour)

### 1. Back up the signing key (do this first)
If the upload key is lost, updates need Google's key reset process (slow).

- [ ] Open `C:\Users\Dhruv\Desktop\Kynetix\kynetix_ui\android\`
- [ ] Copy `upload-keystore.jks` and `key.properties`
- [ ] Put both in a **private** Google Drive folder (e.g. `Kynetix/keys/`, shared with nobody): https://drive.google.com
- [ ] Put both on a USB stick or external drive
- [ ] Save the passwords inside `key.properties` in a password manager (Google Password Manager: https://passwords.google.com, or Bitwarden: https://bitwarden.com)
- [ ] Never email, upload to GitHub, or share these files

### 2. Choose and secure the owner Google account
The developer account is tied to one Google account and is hard to move later.
Use **kynetix.app@gmail.com** (it's already the public contact).

- [ ] Sign in at https://myaccount.google.com
- [ ] Turn on 2-Step Verification: https://myaccount.google.com/signinoptions/twosv
- [ ] Add a recovery phone and recovery email: https://myaccount.google.com/security
- [ ] Optional but recommended: add a passkey or Google Authenticator as a second factor

### 3. Get your registration documents ready
Google checks that your name matches across ID and payment. Read the requirements:
https://support.google.com/googleplay/android-developer/answer/13628312

- [ ] **ID**: Aadhaar, PAN, passport or driving licence. Note your name **exactly** as printed
- [ ] **Card**: Visa/Mastercard/RuPay that allows **international online payments** (turn this on in your bank app; many Indian cards have it off by default). Cardholder name should match the ID
- [ ] **Phone number** for OTP
- [ ] **An Android phone** you can sign in to with the same Google account (Play Console asks you to install its app to prove device access)
- [ ] Optional: set up a payments profile in advance at https://pay.google.com (Settings > Payments profile), legal name and address exactly as on the ID
- [ ] Decide the **developer name** shown on Play: `Kynetix` or `Dhruv Gupta`
- [ ] Choose **Personal** account type (an Organization account needs a registered company and a D-U-N-S number)

Context: Google's Android developer verification is rolling out (enforced from 30 Sep 2026); passing Play's ID check covers it. https://developer.android.com/developer-verification

---

## Day 2 (about 1 hour): Google sign-in setup in Google Cloud

Play re-signs your app with Google's key. Google Sign-In must know every
certificate the app is signed with, or "Continue with Google" fails (error 10).
You can do half of this now.

### 4. Find the right Google Cloud project
- [ ] Open `kynetix_ui\lib\config\supabase_secrets.dart`, look at the start of `googleWebClientId` (don't share it publicly)
- [ ] Open https://console.cloud.google.com/apis/credentials and switch projects (top bar) until you find the **Web client** with the same ID. That's your project.
- [ ] Note the existing **Android** client for `com.kynetix.app` (debug SHA-1). Leave it as is; it makes sign-in work for sideloaded builds.

### 5. Add the upload-key Android client
- [ ] https://console.cloud.google.com/apis/credentials > **Create credentials** > **OAuth client ID**
- [ ] Application type: **Android**
- [ ] Name: `Kynetix Android (upload key)`
- [ ] Package name: `com.kynetix.app`
- [ ] SHA-1: `0C:ED:B7:D7:9F:FF:19:FC:52:7E:24:0C:97:D8:51:F9:B2:B3:B7:46`
- [ ] **Create**

### 6. Make the consent screen production-ready
Google Auth Platform pages (same project):
- Branding: https://console.cloud.google.com/auth/branding
- Audience: https://console.cloud.google.com/auth/audience
- Data access (scopes): https://console.cloud.google.com/auth/scopes

- [ ] Branding: App name `Kynetix`, user support email `kynetix.app@gmail.com`
- [ ] App home page: `https://dhruvgupta-24.github.io/Kynetix/`
- [ ] Privacy policy: `https://dhruvgupta-24.github.io/Kynetix/privacy/`
- [ ] Terms of service: `https://dhruvgupta-24.github.io/Kynetix/terms/`
- [ ] Developer contact email: `kynetix.app@gmail.com`
- [ ] **Do not upload a logo** (a logo triggers brand verification that can take weeks)
- [ ] Scopes: only `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile`
- [ ] Audience > Publishing status: if it says **Testing**, click **Publish app** so it says **In production** (no review needed for these basic scopes). In Testing mode only listed test users can sign in.
- [ ] Later (after you have Play Console): add one more Android client with the **App signing key** SHA-1 from Play Console > Test and release > App integrity

### 7. Double-check Supabase's Google provider
- [ ] https://supabase.com/dashboard/project/sjrcqvqhycxtwwbivizy/auth/providers > Google: enabled, Client ID = your **Web** client ID (and the Android client IDs listed in "Authorized Client IDs" if that field exists). Don't change anything else.
- [ ] https://supabase.com/dashboard/project/sjrcqvqhycxtwwbivizy/auth/url-configuration: redirect URLs include `kynetix://login-callback` and `kynetix://reset-password` (they do today; just confirm)

---

## Days 2 to 5: recruit testers (the slow part, start early)

New personal accounts must run a **closed test with at least 12 testers opted in
for 14 days in a row** before going live:
https://support.google.com/googleplay/android-developer/answer/14151465

### 8. Build the tester list
- [ ] List **15 to 20 people** (buffer for drop-outs) who have an **Android phone** with the Play Store
- [ ] Collect the **exact Gmail address signed in on their phone's Play Store**
- [ ] Create a Google Group to manage them in one place: https://groups.google.com/my-groups > **Create group**
  - Name: `Kynetix testers`, email e.g. `kynetix-testers@googlegroups.com`
  - Who can join: **Only invited users**; Who can view members: **Group managers**
  - Add members directly (Members > Add members), or invite them
- [ ] Send a heads-up message now (WhatsApp/Instagram):

> Hey! I built a fitness + Indian food app called Kynetix and I'm putting it on the Play Store. Can you be one of my testers for 2 weeks? I'll send you a Play Store link soon. Just install it, keep it installed for 14 days, open it a few times, and tell me what feels off (there's a "Talk to us" button inside). Send me the Gmail you use on your phone.

- [ ] Rules to tell them: install from the link I send, **don't uninstall for 14 days**, use it a few times (log a meal, try Kyno)

---

## Days 3 to 6: test everything on your own phone

### 9. Install the latest build
- [ ] Install `kynetix_ui\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` **over** your current app (don't uninstall; that would wipe local data)

### 10. Run this test list and note anything off
- [ ] Cold start from the icon 3 to 4 times: K appears, glides, YNETIX slides out, ember cuts, fades to the app. Smooth, no long stall
- [ ] Still signed in after the update
- [ ] Sign out, then sign in with **email**, then with **Google**
- [ ] Log a meal in your own words; edit one ingredient number; scan one barcode
- [ ] Start a workout, log sets, finish; open **Share**, swipe all 5 cards; share one to an Instagram Story and WhatsApp
- [ ] Kyno: ask a question; long-press a reply > **Report this reply**
- [ ] Profile > **Talk to us**: send a test message; then Settings > **Feedback inbox** shows it (you're the curator on amdhruvgupta@gmail.com)
- [ ] Add each widget size (long-press home screen > Widgets > Kynetix) and check numbers match the app
- [ ] Health Connect: connect; steps and weight appear
- [ ] Account deletion on a **throwaway account only**: sign up, Settings > Delete account; confirm you can't sign in again
- [ ] Send me (or log in the Feedback inbox) every issue you find

### 11. Create the reviewer account
Google's reviewers need a login that works without Google sign-in.
- [ ] In the app, **sign up with an email you control** (e.g. a second Gmail), strong 8+ character password, confirm the code
- [ ] Finish onboarding; log 2 to 3 meals and one workout; send one Kyno message
- [ ] Save the email + password in your password manager. They go **only** into the Play Console "App access" form later. Never into the repo (it's public).
- [ ] Keep this account until the app is approved

---

## Days 4 to 7: get the store listing ready to paste

### 12. Read the policies once (30 minutes)
- [ ] Developer Program Policies overview: https://play.google.com/about/developer-content-policy/
- [ ] Health apps policy: https://support.google.com/googleplay/android-developer/answer/12261419
- [ ] AI-generated content policy (why the report button exists): https://support.google.com/googleplay/android-developer/answer/13985936
- [ ] User data / Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- [ ] Account deletion requirement: https://support.google.com/googleplay/android-developer/answer/13327111
- [ ] Health Connect publishing: https://developer.android.com/health-and-fitness/health-connect/publish

### 13. Put all listing text in one Google Doc
From [PLAY_LAUNCH_GUIDE.md](PLAY_LAUNCH_GUIDE.md):
- [ ] Part 5: app name, short description (80 chars), full description (4000), category Health & Fitness, contact email, website
- [ ] Part 6: App content answers (privacy URL, app access notes, ads: no, target audience 18+, account deletion URL)
- [ ] Part 7: Data safety answers (collected yes, shared no; types and purposes table)
- [ ] Part 8: Health Connect reasons for steps, weight, sleep, HRV
- [ ] Read the full description out loud; change anything that doesn't sound like you (keep: no dashes, nothing the app can't do)
- [ ] Content rating: preview the questionnaire topics here so answers are ready: https://support.google.com/googleplay/android-developer/answer/9859655

### 14. Check every image
Specs: https://support.google.com/googleplay/android-developer/answer/9866151
- [ ] App icon 512x512: `C:\Users\Dhruv\Desktop\Kynetix-logo-concepts\shear-final\play-store-icon-512.png`
- [ ] Feature graphic 1024x500 and 8 phone screenshots: `C:\Users\Dhruv\Desktop\Kynetix-logo-concepts\play-store\designed\`
- [ ] Open each full screen; ask a friend which 2 screenshots make them want the app (put those first)

### 15. Check the public links (on your phone too)
- [ ] Website: https://dhruvgupta-24.github.io/Kynetix/
- [ ] Privacy policy: https://dhruvgupta-24.github.io/Kynetix/privacy/
- [ ] Account deletion: https://dhruvgupta-24.github.io/Kynetix/delete-account/
- [ ] Terms: https://dhruvgupta-24.github.io/Kynetix/terms/
- [ ] The privacy page names you (Dhruv Gupta) and kynetix.app@gmail.com; read it once fully so you can answer questions about it

---

## The day before you pay

### 16. Build the final app bundle
- [ ] Any fixes from your phone test are done and pushed
- [ ] Version in `kynetix_ui\pubspec.yaml` is `1.0.0+1` for the first upload (raise the number after `+` for every later upload)
- [ ] Build:
```
cd C:\Users\Dhruv\Desktop\Kynetix\kynetix_ui
flutter build appbundle --release
```
- [ ] File to upload: `kynetix_ui\build\app\outputs\bundle\release\app-release.aab` (signed with the upload key automatically; the build refuses to run without `key.properties`)

### 17. Have these open in tabs
- [ ] Your Google Doc with all listing text
- [ ] The images folder
- [ ] Reviewer login (password manager)
- [ ] Tester group address
- [ ] [PLAY_LAUNCH_GUIDE.md](PLAY_LAUNCH_GUIDE.md)

Then register: https://play.google.com/console/signup (Personal, pay US$25, verify ID) and follow the launch guide from Part 2.

---

## Optional, before testers arrive (ask Claude to do these)
- **Crash reporting** (Sentry or Firebase Crashlytics) so tester crashes show up with details
- **Feedback email alerts**: create a Gmail **app password** for kynetix.app@gmail.com at https://myaccount.google.com/apppasswords (needs 2-Step Verification on) and hand it over; every new feedback then emails amdhruvgupta@gmail.com
- **Small backend tidy-ups** from the security audit
