# Kynetix on Google Play: the whole launch, step by step

From "no developer account" to "live on the Play Store". Do the parts in order.
Rough timeline: account 1 to 3 days, closed test at least 14 days, production
review up to 7 days. So plan on about 3 to 4 weeks end to end.

Everything Kynetix needs from the code side is already done: signed app bundle,
privacy policy, account deletion page, store assets. What's left is accounts,
forms and testers, which only you can do.

---

## Part 0. What you need before you start

| Thing | Where it is / what it is |
|---|---|
| A Google account you'll keep forever | Use a dedicated one if you can (e.g. kynetix.app@gmail.com). The developer account can't be moved to another Google account easily later. |
| US$25 | One-time Play Console registration fee. Card that works for international payments. |
| Government photo ID | Aadhaar, PAN, passport or driving licence. Name must match the payment profile name exactly. |
| A phone number | For OTP verification. |
| An Android phone | Play Console asks you to install the Play Console app on a real Android device to prove access. |
| The app bundle | `kynetix_ui/build/app/outputs/bundle/release/app-release.aab` (rebuild any time with `flutter build appbundle --release` in `kynetix_ui`; it is signed with the upload key automatically and refuses to build without it). |
| Upload key | `kynetix_ui/android/upload-keystore.jks` + `kynetix_ui/android/key.properties`. **Back both up now** (Google Drive + a USB stick). Lose them and updates need Google's key reset process. |
| Store assets | `Desktop/Kynetix-logo-concepts/play-store/` (feature graphic, screenshots) and `Desktop/Kynetix-logo-concepts/shear-final/play-store-icon-512.png` (icon). |
| Links | Website https://dhruvgupta-24.github.io/Kynetix/ · Privacy https://dhruvgupta-24.github.io/Kynetix/privacy/ · Delete account https://dhruvgupta-24.github.io/Kynetix/delete-account/ · Terms https://dhruvgupta-24.github.io/Kynetix/terms/ · Email kynetix.app@gmail.com |

---

## Part 1. Create the Google Play developer account

1. Open **https://play.google.com/console/signup** while signed in to the Google account you chose.
2. Choose **"Yourself"** (a personal account). An organisation account needs a registered company plus a D-U-N-S number; you're an individual, so personal is right.
3. **Developer name**: what shows under the app on Play. Use `Kynetix` (or `Dhruv Gupta`). You can change it later.
4. **Contact details**:
   - Developer email shown on Play: `kynetix.app@gmail.com`.
   - Your private contact email and phone (verified by OTP, not public).
5. **About you**: answer the questions about your Android experience and how many apps you plan to publish. These don't affect approval.
6. **Pay the US$25** fee with your card. A Google Payments profile gets created; the legal name there must match your ID.
7. **Identity verification**: upload your government ID. Google checks that the name matches your payments profile. This takes from a few hours to a few days. You'll get an email.
8. **Device verification**: install the **Google Play Console** app on your Android phone, sign in with the same account, and follow the prompt that confirms you have a real device.
9. When the dashboard says your account is verified, you can create apps.

Heads up (2026): Google is rolling out *Android developer verification* for all developers, with enforcement starting 30 September 2026. Accounts that already passed Play's identity check are covered; just keep your details accurate in **Settings > Developer account**.

---

## Part 2. Create the app in Play Console

1. **Home > Create app**.
2. App name: `Kynetix` (you can add a short tagline later in the listing, max 30 chars total).
3. Default language: **English (United States)** or **English (India)**.
4. App or game: **App**. Free or paid: **Free** (free can never become paid later, which is fine).
5. Tick the declarations (Developer Program Policies, US export laws) and **Create app**.

---

## Part 3. Upload your first build to Internal testing (to get Play App Signing)

Internal testing is instant (no review wait) and lets you upload the bundle once so Google sets up signing.

1. Left menu **Test and release > Testing > Internal testing > Create new release**.
2. It asks about **Play App Signing**: choose **Use Google-generated key** (recommended). Google keeps the app signing key; your upload key stays yours.
3. Upload `app-release.aab`.
4. Release name: `1.0.0 (1)`. Release notes: `First build.`
5. **Save > Review release > Start rollout to Internal testing**.
6. **Testers** tab: create an email list with your own Gmail (the one on your phone) and copy the **opt-in link**. Open it on your phone, accept, and install from Play. This is the first time Kynetix installs from the Play Store.

> Version numbers: every new upload needs a higher `versionCode`. Bump the `+N` in `kynetix_ui/pubspec.yaml` (`version: 1.0.0+1` becomes `1.0.0+2`) before each new bundle.

---

## Part 4. Fix Google Sign-In for Play installs (do this right after Part 3)

Play re-signs the app with Google's app signing key. Google Sign-In checks the signing certificate, so it must know that key's fingerprint, or "Continue with Google" fails with error 10 for everyone who installed from Play.

1. In Play Console: **Test and release > Setup > App signing** (it may be under **App integrity**). Copy two SHA-1 fingerprints:
   - **App signing key certificate** SHA-1 (Google's key).
   - **Upload key certificate** SHA-1. It should be `0C:ED:B7:D7:9F:FF:19:FC:52:7E:24:0C:97:D8:51:F9:B2:B3:B7:46`.
2. Open **https://console.cloud.google.com/** with the Google account that owns the Kynetix OAuth setup (the project where the web client ID used by the app lives; the ID is in `kynetix_ui/lib/config/supabase_secrets.dart`, `googleWebClientId`).
3. Top bar project picker: select that project.
4. **APIs & Services > Credentials > + Create credentials > OAuth client ID**.
5. Application type: **Android**.
   - Name: `Kynetix Android (Play signing)`.
   - Package name: `com.kynetix.app`.
   - SHA-1: paste the **App signing key** SHA-1.
   - **Create**.
6. Repeat step 5 with name `Kynetix Android (upload key)` and the **upload key** SHA-1.
7. Keep any existing Android client with the debug SHA-1 for your sideloaded/debug builds.
8. **APIs & Services > OAuth consent screen**: make sure **Publishing status = In production**. If it says *Testing*, only listed test users can sign in. Press **Publish app**. Google may ask for verification if you use sensitive scopes; Kynetix only asks for email and profile, which normally needs no review.
9. Nothing to change in the app or in Supabase: the app uses the web client ID, Supabase's Google provider stays as is.
10. Test: on your phone, uninstall nothing; just open the Play-installed internal build, sign out, and tap **Continue with Google**. It should work. (Changes in Cloud Console can take a few minutes.)

---

## Part 5. Store listing

**Grow users > Store presence > Main store listing**:

| Field | What to put |
|---|---|
| App name | `Kynetix` |
| Short description (80 chars) | `Log dal, roti and every set. Kyno coaches you on both. Real food. Real lifts.` |
| Full description (4000) | Use the draft below. |
| App icon | `shear-final/play-store-icon-512.png` (512x512, 32-bit PNG) |
| Feature graphic | `play-store/feature-graphic-1024x500.png` |
| Phone screenshots | The 8 from `play-store/` (Part 9 explains them). Min 2, max 8. |
| Tablet screenshots | Optional; skip for now. |
| Video | Optional; skip, or a YouTube link to a screen recording later. |

Full description draft:

```
Real food. Real lifts. One coach.

Kynetix is for people who eat dal and roti and lift four days a week.

FOOD, THE WAY YOU ACTUALLY EAT
Type it like you'd say it: "3 roti, dal tadka, paneer bhurji." Kynetix knows a katori from a bowl and does the maths. Scan packaged food by barcode. Calories and protein rings show what's left today.

TRAINING THAT KEEPS UP
Pick a split or build your own. Log every set in a tap: weight, reps, warm-ups and drops. See records, volume and your week at a glance.

KYNO, YOUR COACH
Kyno reads your meals and your lifts together. Ask "what should I eat to hit my macros?" and get options that fit what you have left. It notices when protein comes up short or a lift stalls, and tells you what to try next. Kyno can be wrong and isn't medical advice.

SHARE THE WORK
Five share cards for your story: Poster, Receipt, Skyline, In real terms, and a transparent Sticker.

ALSO IN THE BOX
Home screen widgets. Health Connect (steps, weight, sleep, HRV), read only. Dark theme that actually looks good.

PRIVACY, NO FUNNY BUSINESS
No ads. We don't sell your data. Delete your account and everything with it from Settings, any time.

Questions or ideas? Profile > Talk to us, or kynetix.app@gmail.com
```

**Store settings** (same menu, *Store settings*):
- Category: **Health & Fitness**. Tags: Fitness, Nutrition, Workout tracker, Calorie counter (pick from Google's list).
- Contact: email `kynetix.app@gmail.com`, website `https://dhruvgupta-24.github.io/Kynetix/`. Phone optional.

---

## Part 6. App content (Policy > App content). Every section must be green.

1. **Privacy policy**: `https://dhruvgupta-24.github.io/Kynetix/privacy/`
2. **App access**: choose *All or some functionality is restricted*. Add instructions so the reviewer can log in:
   - Name: `Reviewer account`
   - Username and password: a dedicated reviewer account (sign up in the app with an email you control, finish onboarding, log a meal and a workout). Type the credentials only into this Play Console form, never into the repo (it's public). Reviewers sign in with email, so Google sign-in isn't needed.
   - Notes: `Sign in with email. Onboarding is done; the account has meals and workouts logged.`
3. **Ads**: *No, my app does not contain ads*.
4. **Content rating**: start the IARC questionnaire. Category **Utility, Productivity, Communication or Other** (or Health). Answer honestly: no violence, no sexual content, no gambling. Users can chat with AI (answer *Yes* to user-generated / AI-generated content if asked; mention in-app reporting). Expect a rating like *Everyone* / *3+* (Google might set PEGI 3 or 12 depending on the AI chat answers; that's fine).
5. **Target audience and content**: age group **18 and over** only (the app enforces 18+ at onboarding). Not designed for children.
6. **News app**: No.
7. **Data safety**: see Part 7.
8. **Government app**: No. **Financial features**: none.
9. **Health apps**: see Part 8.
10. **Account deletion**: *Yes, users can create accounts*. Deletion link: `https://dhruvgupta-24.github.io/Kynetix/delete-account/`. In-app path: *Profile avatar > Settings > Delete account*.
11. **Advertising ID**: *No* (the app doesn't use it).
12. **Permissions declarations**: none needed. Camera is for barcodes; photos use Android's photo picker (no media permission); `SCHEDULE_EXACT_ALARM` needs no declaration (only `USE_EXACT_ALARM` does).

---

## Part 7. Data safety form (the exact answers)

Important definition: data sent to a company that processes it **on your behalf** (a service provider: Supabase hosting, Gemini/Groq/OpenRouter answering Kyno) counts as **collected**, not **shared**. "Shared" means handing data to a third party for *their own* use. So for Kynetix: **collected = yes, shared = no**.

Top questions:
- Does your app collect or share any required user data types? **Yes**
- Is all data encrypted in transit? **Yes** (HTTPS only; cleartext is off)
- Do you provide a way for users to request deletion? **Yes** (in-app + web link)

Data types to tick (for each: Collected = Yes, Shared = No, Processed ephemerally = No unless noted, Required or optional as noted):

| Category > type | Why (purposes to tick) | Required? |
|---|---|---|
| Personal info > **Name** | App functionality, Account management | Required |
| Personal info > **Email address** | App functionality, Account management, Developer communications (feedback replies) | Required |
| Health and fitness > **Health info** (weight, sleep, HRV) | App functionality, Personalisation | Optional |
| Health and fitness > **Fitness info** (workouts, steps) | App functionality, Personalisation | Optional |
| Photos and videos > **Photos** (meal photos sent to Kyno) | App functionality. Tick **Processed ephemerally = Yes** (sent to the AI for one answer, not stored) | Optional |
| App activity > **Other user-generated content** (meals you type, Kyno chat questions, feedback, reports) | App functionality, Analytics? **No**, just App functionality | Optional |
| App info and performance > **Crash logs** (in-house error reports) | Analytics, App functionality | Required (automatic) |
| Device or other IDs | **Don't tick**: the app doesn't use advertising ID or device IDs |  |
| Location, Contacts, Financial, Messages, Audio, Calendar | **Don't tick** |  |

Then preview the safety card and submit.

---

## Part 8. Health apps declaration (Health Connect)

**Policy > App content > Health apps**:

1. Select the health features Kynetix supports: **Activity and fitness**, **Nutrition**, **Sleep** (because of sleep read), and anything that matches body measurements.
2. Health Connect data types: declare exactly the four the app reads, each with its reason (paste these):
   - **Steps (read)**: `Shows today's steps and uses the recent average to size the user's daily calorie target.`
   - **Weight (read)**: `Shows the weight trend and keeps calorie and protein targets matched to the user's current weight.`
   - **Sleep (read)**: `Lets the coach factor last night's sleep into training advice (for example, suggesting a lighter session after poor sleep).`
   - **Heart rate variability (read)**: `Used as a recovery signal so the coach can suggest when to push or ease off in training.`
3. Write access: **None** (Kynetix never writes to Health Connect).
4. Confirm the privacy policy link is the same one shown in Health Connect (it is: the in-app policy screen and the website say the same thing).
5. HRV gets the most scrutiny. If Google pushes back, the fallback is to remove HRV from the manifest in a new build.

---

## Part 9. The closed test (the 12 testers x 14 days rule)

Personal accounts created after 13 Nov 2023 can't publish to production until a **closed test** has had **at least 12 testers opted in continuously for 14 days**. Testers must actually install the app; people who leave and rejoin restart their count.

1. **Test and release > Testing > Closed testing > Create track** (or use the default *Alpha*).
2. **Testers**: create an email list (Gmail addresses of friends, family, gym buddies). Aim for 15 to 20 so you still have 12 if a few drop.
3. **Create release** on the closed track: upload the same or a newer `.aab`, release notes, **Start rollout**. Closed releases go through review (usually a few hours to a couple of days).
4. Once approved, send everyone the **opt-in link** (and the web Play link shown on the Testers tab). Each tester: open link > *Become a tester* > install from Play. Ask them to keep it installed and open it a few times; Google also looks at engagement.
5. Use the 14 days: collect feedback (it lands in your in-app **Feedback inbox**), fix bugs, upload new builds to the same closed track (bump versionCode each time).
6. Day 14+: **Dashboard > Apply for production**. You answer questions about the test (how you recruited testers, what feedback you got, what you changed). Be specific. Review usually takes up to 7 days.

---

## Part 10. Production release

1. After production access is granted: **Test and release > Production > Create new release**.
2. Add the latest bundle (or promote the closed build), release notes like `Kynetix 1.0. Real food. Real lifts.`
3. **Countries/regions**: start with **India** (add others later).
4. Consider a **staged rollout** (e.g. 20%) so a bad crash only hits a few people; raise to 100% after a couple of days of clean Android vitals.
5. **Send for review**. When approved, it's live.

---

## Part 11. After launch

- Update the website's Google Play badge to a real link (ask me; it's one change) and the README.
- Watch **Quality > Android vitals** for crashes and ANRs daily for the first week.
- Reply to reviews in **Grow users > Ratings and reviews**.
- Read feedback in the app: *Settings > Feedback inbox* (only your account sees it).
- Every update: bump `version` in `pubspec.yaml`, `flutter build appbundle --release`, upload to the track, roll out.

## Optional, later

- Custom domain for the website (about INR 800 to 1,500 a year for `.app`/`.in`), connect it to GitHub Pages.
- Supabase Pro (US$25/month) turns on leaked-password protection and daily backups.
- iPhone: needs a Mac (or a cloud Mac), the Apple Developer Program (US$99/year), and App Store review. The Flutter code is ready for it in principle.

Sources:
[Play Console: testing requirements for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) ·
[Android developer verification rollout](https://android-developers.googleblog.com/2026/03/android-developer-verification-rolling-out-to-all-developers.html) ·
[Play Console guide to developer verification](https://developer.android.com/developer-verification/guides/pdf-guides/adc-guide.pdf) ·
[Publish your Health Connect app on Google Play](https://developer.android.com/health-and-fitness/health-connect/publish) ·
[Declare access to Health Connect data types](https://developer.android.com/health-and-fitness/guides/health-connect/publish/declare-access)
