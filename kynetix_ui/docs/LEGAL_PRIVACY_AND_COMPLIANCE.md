# Legal, Privacy & Compliance Rulebook — Kynetix

> **Status:** Engineering rulebook. **Not legal advice.** Every customer-facing legal text (Privacy Policy, Terms, in-app notices) is a *review-ready draft* until certified by qualified Indian legal counsel.
> **Scope:** Kynetix Flutter app (`kynetix_ui/`), Supabase backend (`supabase/functions/`), store listings (Google Play, Apple App Store).
> **Companion:** [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md) (user-facing draft), [`DATA_ISOLATION.md`](DATA_ISOLATION.md) (per-user cache isolation contract).
> **Last code audit:** 2026-10-16 against branch `ui-overhaul`.

### How to read legal claims in this document

Each legal statement carries one of these markers:

| Marker | Meaning |
|---|---|
| **[Confirmed]** | Stable, widely documented requirement. Still confirm wording with counsel. |
| **[Verify]** | Believed accurate but the rule, its commencement date, or the platform policy text changes often. Check the current official source before relying on it. |
| **[Counsel]** | Judgment call or interpretation. A lawyer must decide. |

Engineers must not upgrade a marker on their own. "The doc says so" is not verification.

---

## 1. Core principles

1. **Data minimisation.** Do not collect, send or keep personal data because a library makes it easy. Every field needs a purpose, an owner, a retention rule, an access rule and a deletion rule. Speculative "might be useful later" fields are forbidden.
2. **AI proposes, the user decides.** AI output (meal macro estimates, coaching text, insights) is never the source of truth. The user's confirmed log is. AI output is always labelled as an estimate and is always editable.
3. **Third-party minimisation.** Prefer bundled assets and on-device processing over network calls to third parties that see the user's IP address, health data or free text.
4. **Indian law first.** Kynetix targets users in India, so the primary frame is the DPDP Act 2023 and the IT Act 2000. Defensive measures for EU/US exposure are secondary.
5. **Evidence-backed compliance.** A requirement counts as met only when code, a test or a physical device check proves it. A UI badge or a policy sentence is not proof.

---

## 2. What Kynetix actually processes (verified data inventory)

Verified by reading code on 2026-10-16. If code changes, update this table **and** `PRIVACY_POLICY.md` in the same PR.

| # | Category | Elements | Where it is collected (code) | Where it goes | Notes |
|---|---|---|---|---|---|
| 1 | Account identity | Email + password, or phone number + OTP, or Google account (ID token, email, name) | `lib/services/auth_service.dart` (`signUp`, `signInWithPassword`, `signInWithOtp`, `signInWithIdToken`), `lib/screens/auth_screen.dart` (`IntlPhoneField`) | Supabase Auth; Google Sign-In; SMS OTP via whatever SMS provider is configured in the Supabase project | Email and phone are **also copied** into `profiles` (`lib/services/profile_service.dart:101-104`). |
| 2 | Body & goal profile | Name, age, gender, height (cm), weight (kg), goal, training days/week, portion anchor, custom calorie/protein targets, target-change history | `lib/screens/onboarding_screen.dart`, `lib/models/user_profile.dart` | Supabase `profiles`; local `shared_preferences` | Weight and body metrics are health-adjacent data. |
| 3 | Meal & nutrition logs | Free-text meal descriptions, parsed items, calories/macros, meal sections, quick-adds, saved/recurring meals, per-user food corrections, eating patterns | `lib/screens/add_meal_screen.dart`, `lib/services/nutrition_pipeline.dart`, `meal_memory.dart`, `user_nutrition_memory.dart`, `quick_add_service.dart` | Supabase `day_logs`, `user_nutrition_memory`, `user_quick_adds`, `user_eating_patterns`, `user_meal_contexts`; local cache | |
| 4 | Workout data | Splits, sessions, exercises, sets (weight × reps), exercise preferences, achievements | `lib/services/workout_service.dart`, `cloud_sync_service.dart` | Supabase `workout_sessions`, `workout_splits`, `user_achievements`; local cache | |
| 5 | Device health data (read-only) | Steps, body weight readings, sleep sessions, heart-rate variability (RMSSD) | `lib/services/health_service.dart:471-478` (`health` package → Health Connect / HealthKit) | Steps/sleep/HRV: **local only** (`shared_preferences`, e.g. `kynetix_sleep_hours_v1`). Weight history: shown on dashboard **and summarised into the AI coach prompt** (`lib/services/ai_coach_service.dart:199-200`). | The app never writes to Health Connect or HealthKit. |
| 6 | Photos | Camera photo or gallery images (menus, plates, delivery screenshots), downscaled to max 1024px width | `lib/screens/ai_coach_screen.dart:134-190` (`image_picker`) | Sent to the AI router Edge Function and on to the AI model. No evidence of storage in Supabase Storage. | Confirm EXIF/GPS metadata is stripped before upload. |
| 7 | AI coach chat | User messages, attached images, AI replies; context built from profile, today's log, last 30 days of `day_logs`, top 100 nutrition-memory rows | `lib/services/ai_coach_service.dart`, `kyno_context_service.dart`, `kyno_assistant_service.dart`, `insights_report_service.dart`; server: `supabase/functions/ai-meal-coach/index.ts:804-807, 693-699` | Supabase Edge Functions → **OpenRouter** (default text model `deepseek/deepseek-chat-v3-0324`; vision: `google/gemini-2.5-pro`, `google/gemini-2.5-flash`, `nvidia/nemotron-nano-12b-v2-vl:free`) **or** the user's own ChatGPT account (OpenAI) | The AI prompt includes the user's **name**, age, gender, height and weight. |
| 8 | Connect ChatGPT | OpenAI device-auth session, OAuth access + refresh tokens, selected model, connection status, last provider used | `lib/screens/connect_chatgpt_screen.dart`, `lib/services/chatgpt_link_service.dart`; server: `openai-link-*` functions | Supabase tables `openai_device_auth_sessions`, `user_openai_links`; OpenAI (`auth.openai.com`, `chatgpt.com/backend-api/...`) | Tokens are stored server-side and are not returned to the client (per `ai-chat-router/index.ts:13-14`). |
| 9 | Local device cache | Profile, day logs, meal memories, insights cache, sleep/HRV, home-screen widget payload (`widget_data_v1`: today's calories/protein) | `lib/services/persistence_service.dart`, `widget_service.dart`, `KynetixWidgetProvider.kt` | `shared_preferences` (unencrypted app sandbox) | Cleared on sign-out per `DATA_ISOLATION.md`. |
| 10 | Exercise media | None from the user. The **device IP address** reaches third-party CDNs when images/videos load. | `lib/services/exercise_media_service.dart:13-20` | `cdn.jsdelivr.net`, `raw.githubusercontent.com` | Third-party network exposure. |
| 11 | Shared reference data | Global food defaults (not personal) | `lib/services/global_food_service.dart` | Supabase `global_food_defaults` | |
| 12 | Server logs | Edge Function logs include user IDs, provider/model, message counts and **previews of AI responses and raw provider bodies** | `supabase/functions/ai-chat-router/index.ts:132, 214, 345, 356, 394` | Supabase logging | Must be reduced (see Gaps). |

**Not present (verified):** no analytics, crash-reporting, advertising or attribution SDKs in `pubspec.yaml`/`pubspec.lock` (no Firebase, Sentry, Mixpanel, Amplitude, PostHog, AppsFlyer, Facebook). No contacts, location, microphone or call-log permissions. No payments or subscriptions.

---

## 3. India — Digital Personal Data Protection Act, 2023 (DPDP Act)

Kynetix (the operator, "[Company legal name]") is a **Data Fiduciary**: it decides why and how personal data is processed. Supabase, OpenRouter and its model providers, and Google (sign-in) act as **Data Processors** or independent providers, depending on the contract.

### 3.1 Legal status and timing — [Verify]
- The Act was passed in August 2023 (Act No. 22 of 2023).
- The DPDP Rules, 2025 were notified by MeitY in November 2025 with **phased commencement**. Most substantive obligations take effect about 18 months after notification. Counsel must confirm which provisions are in force on the launch date.
- Until full commencement, the **IT Act 2000, Section 43A** and the **SPDI Rules 2011** apply. The SPDI Rules list passwords and "physical, physiological and mental health condition" as *sensitive personal data*. Kynetix's body metrics, weight, sleep and HRV fall in that category. **Build to DPDP now.** It is the stricter long-term target and also meets the SPDI consent and disclosure requirements.

### 3.2 Notice and consent (Sections 5 & 6) — [Confirmed]
- Before or when asking for consent, give a notice that lists the personal data collected, the purpose, how to exercise rights, and how to complain to the Data Protection Board.
- Consent must be **free, specific, informed, unconditional and unambiguous**, given by a **clear affirmative action**, and **as easy to withdraw as to give**.
- Do not bundle purposes. Kynetix must separate at least:
  1. **Core service.** Account, logging meals and workouts, and syncing them. This is necessary to provide the service the user asked for.
  2. **Device health data.** A separate, optional opt-in for each Health Connect / HealthKit data type.
  3. **AI processing.** A separate, optional opt-in before any personal data (profile, logs, photos, health-derived weight) is sent to third-party AI models.
  4. **Connect ChatGPT.** A separate, explicit opt-in to link a third-party account and store its tokens.
  5. Any future marketing, analytics or research purpose. Each needs its own optional opt-in, unchecked by default.
- Record consent with context: user ID, purpose, policy version, timestamp, granted/withdrawn status, and the UI surface. A bare `consent = true` is not enough.
- **[Counsel]** Whether "legitimate use" (Section 7) covers any of the core-service processing without separate consent.

### 3.3 Purpose limitation and minimisation — [Confirmed principle]
- Use data only for the purpose stated at collection. Data collected for meal logging may not be reused for a new purpose (for example, training an in-house model, marketing, or selling insights) without fresh notice and consent.
- Send AI providers only what the specific answer needs. The user's **name is not needed** for nutrition coaching.

### 3.4 Data Fiduciary obligations (Section 8) — [Confirmed]
- **Accuracy** when the data is used to make decisions about the user. The user's own logs override AI estimates.
- **Reasonable security safeguards** to prevent a personal data breach (Section 8(5)). This is the obligation with the highest penalty ceiling in the Schedule: up to ₹250 crore. Penalties are set case by case by the Data Protection Board and are **not** automatic.
- **Breach intimation** to the Board and to each affected user (Section 8(6)). See §12.
- **Erase** personal data when consent is withdrawn or the purpose is no longer being served, unless law requires retention (Section 8(7)). Make processors erase it too.
- **Publish the contact details** of a person who can answer questions about processing (Grievance Officer / DPO). Run a working **grievance redressal** mechanism (Sections 8(9)–8(10), 13).
- **Significant Data Fiduciary** status (DPO, audits, DPIA) applies only if the government notifies it. **[Counsel]** Health-adjacent data at scale is a factor the government may weigh. Keep a light DPIA anyway.

### 3.5 User rights (Sections 11–14) — [Confirmed]
Users can: get a summary of their data and of who it was shared with; have it corrected, completed, updated or erased; use grievance redressal; and nominate someone to exercise their rights after death or incapacity. Each right needs a working in-app or email path.

### 3.6 Children (Section 9) — [Confirmed]
- Under the DPDP Act, a "child" is anyone **under 18**.
- Processing a child's data needs **verifiable parental consent**. Processing that is likely to harm a child's well-being is forbidden, and so are **tracking, behavioural monitoring and targeted advertising directed at children**.
- Calorie targets, weight-loss goals and body-metric tracking for minors are high-risk content.
- **Decision for Kynetix:** the service is **18+ only** unless and until a verifiable parental-consent flow is built and reviewed by counsel. Onboarding must reject ages under 18. A signal that a user is under 18 must trigger account lock and purge. Do **not** collect ID documents to verify age, because that breaks minimisation.

### 3.7 Cross-border transfer (Section 16) — [Confirmed / Verify list]
- Transfers outside India are allowed **except** to countries the government restricts by notification (a negative list). **[Verify]** whether any country has been notified before launch.
- The Kynetix Supabase project's region must be checked and disclosed. OpenRouter, the underlying model providers (DeepSeek, Google, NVIDIA and others) and OpenAI process data **outside India**, mainly in the USA. Disclose this.

### 3.8 Retention — [Confirmed principle]
Kynetix has no tax or invoicing obligation that forces long retention: there are no payments. So the default is to **delete when the account is deleted or the purpose ends**. Proposed schedule:

| Data | Retention |
|---|---|
| Account, profile, logs, workouts, memories | Life of the account. Deleted within **[N] days** of an account-deletion request. |
| `user_openai_links` tokens | Until disconnect or account deletion. **Null the tokens immediately on disconnect** (already done in `openai-link-disconnect/index.ts:43-44`). |
| `openai_device_auth_sessions` | Short-lived. Purge expired or completed sessions within 24 hours (to be implemented). |
| Meal photos sent to AI | Not stored by Kynetix. Retention by the AI provider follows that provider's terms. Confirm zero retention. |
| Edge Function / server logs | ≤ 30 days, with PII and content removed. |
| Supabase backups / PITR | Per plan. Deleted users drop out of backups as the backups age out. Disclose the window. |
| Inactive accounts | **[Counsel]** Define an inactivity purge. The Rules may prescribe one for some classes of fiduciary. |

---

## 4. Account deletion

### 4.1 Requirements — [Confirmed]
- **Google Play:** an app that lets users create accounts must provide an **in-app** way to request account deletion **and** a **web link** where users can request deletion without reinstalling the app. Enter that link in the Data Safety section. Deletion must cover the data tied to the account, not just deactivate it.
- **Apple App Store, Guideline 5.1.1(v):** an app that supports account creation must let users **start account deletion from within the app**.
- **DPDP Section 8(7):** erase the data when consent is withdrawn, including at processors.

### 4.2 Kynetix deletion pipeline (to build)
1. **Request.** Profile → "Delete account & data". Show plainly what will be deleted, then re-authenticate.
2. **Server.** A new Edge Function `delete-account`, using the service role, deletes all rows for `user_id` in every user table: `profiles`, `day_logs`, `workout_sessions`, `workout_splits`, `user_achievements`, `user_eating_patterns`, `user_insights_cache`, `user_meal_contexts`, `user_nutrition_memory`, `user_quick_adds`, `user_openai_links`, `openai_device_auth_sessions`, and any table added later. It then calls `auth.admin.deleteUser`.
3. **Third parties.** Best-effort revocation of the user's linked OpenAI refresh token, if OpenAI supports revocation; disconnect Google Sign-In (`GoogleSignIn.disconnect()`, not just `signOut()`).
4. **Device.** Run the existing `AuthService.signOut()` → `PersistenceService.reset()` sequence (`DATA_ISOLATION.md`) and remove `widget_data_v1`.
5. **Backups.** Disclose the backup age-out window. Re-apply deletions after any restore.
6. **Verify.** An automated test asserts zero rows for the user ID in every table and that the auth user is gone.
7. **Web path.** A public URL `[deletion request URL]` that authenticates the user (or verifies the email) and triggers the same function.

---

## 5. Processors and sub-processors

Keep this register in sync with code. Every row needs a signed or accepted DPA or terms, a region, and confirmed training and retention settings before launch.

| Provider | Role | Data sent | Region | Must verify before launch |
|---|---|---|---|---|
| **Supabase, Inc.** | Database, Auth, Edge Functions, logs | Everything in §2 rows 1–4, 7–8, 12 | Project region: **[verify — Supabase project region]** | DPA accepted; region disclosed; RLS on every user table (schema is **not in the repo**: `supabase/supabase/` is empty); backup window; log retention. |
| **SMS provider configured in Supabase Auth** (for phone OTP) | OTP delivery | Phone number, OTP | **[verify]** | Which provider (e.g. Twilio/MessageBird/other); Indian DLT/TRAI registration for SMS templates **[Verify]**. |
| **Google (Google Sign-In)** | Identity provider | Google account email, name, ID token | Global | OAuth consent screen lists the privacy policy URL; only default scopes (no extra scopes found in `auth_service.dart`). |
| **OpenRouter, Inc.** | AI gateway (default AI provider, paid for by Kynetix) | Prompt with profile, logs, nutrition memory, chat text, photos, weight summary | USA (and the routed provider's region) | **Account-level setting that blocks providers which train on or retain prompts.** Free (`:free`) model endpoints may have different data policies, so confirm or remove them. Zero-data-retention routing if available. **[Verify]** |
| **Model providers behind OpenRouter**: DeepSeek, Google (Gemini 2.5 Pro/Flash), NVIDIA (Nemotron) | AI inference | As above | Various, outside India | Covered by OpenRouter's terms, plus each provider's data policy as surfaced by OpenRouter. **[Verify]** |
| **OpenAI (user's own ChatGPT account)** | AI inference, only when the user links their account | Prompt as above, sent with the **user's** OAuth token | USA | Data handling follows the **user's** ChatGPT account settings, not Kynetix's (`store:false` is set in `ai-chat-router/index.ts:110`). **[Counsel]** See §7.4. |
| **jsDelivr / GitHub** | Exercise image/video CDN | Device IP, user-agent | Global | Prefer bundling or self-hosting. Confirm the dataset licence (§10). |

**Rules**
- No new third party receives personal data without (a) an entry in this table, (b) an update to `PRIVACY_POLICY.md`, and (c) an update to the store Data Safety and App Privacy answers.
- AI provider keys stay server-side only. This already holds: `lib/config/secrets.dart` contains no AI keys. **Keep it that way.**

---

## 6. AI data governance

1. **AI is not the source of truth.** AI macro estimates and coaching text are proposals. The user's confirmed log entry is canonical. AI must never silently overwrite a user-entered or user-corrected value. This is consistent with the "fail-closed" memory rules in `DATA_ISOLATION.md`.
2. **Label every AI output.** AI-estimated meals keep a visible badge (the "🤖 AI" badge exists in `add_meal_screen.dart:1344`). The coach screen states that replies are AI-generated estimates and **not medical advice**. No such disclaimer exists today.
3. **No training on user data without consent.** Kynetix does not use user data to train or fine-tune any model. Third-party providers must be configured not to train on or retain Kynetix prompts (§5). Any future in-house training or evaluation set built from user data needs its own opt-in consent, de-identification, and a policy update.
4. **Minimise prompts.** Remove the user's **name** from the system prompt (`ai-meal-coach/index.ts:693`). Send ranges or rounded values where precision is not needed. Do not send email, phone or user ID to the model.
5. **Health-derived data to AI.** Weight history from Health Connect / HealthKit reaches the AI prompt (`ai_coach_service.dart:199-200`). This must be (a) disclosed, (b) behind the AI opt-in, and (c) checked against the Health Connect and HealthKit rules (§7, §8).
6. **Photos.** Strip EXIF/GPS before upload. Tell users not to photograph people or documents. Do not store photos server-side unless a feature needs it and it is disclosed.
7. **Safety.** Prompts should keep the coach from recommending extreme deficits, from diagnosing, and from giving advice for medical conditions, pregnancy or eating disorders. Point users to professionals instead. **[Counsel]** Keep marketing and in-app copy in "general wellness" positioning and avoid diagnostic or treatment claims, which could pull the app toward medical-device regulation.
8. **Kill switch.** Add a server-side flag that disables all AI calls (fall back to local estimation, which already exists as `local_fallback` in `nutrition_result.dart`) in case of a provider incident.

---

## 7. Google Play — Health Connect, Data Safety, account deletion

### 7.1 Health Connect — [Verify against current Play policy text]
- Each Health Connect permission must be declared in the manifest **and** justified in the Play Console Health Connect declaration. Request only the data types a user-facing feature needs.
- The app must show a **privacy policy / permissions rationale** when Health Connect opens it:
  - Android 14+: an `activity-alias` handling `android.intent.action.VIEW_PERMISSION_USAGE` with category `android.intent.category.HEALTH_PERMISSIONS`. This is present in `AndroidManifest.xml:61-70`, but it targets `MainActivity`, which does not handle the intent or show a policy.
  - Android 13 and lower: an activity with an intent filter for `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`. This is **missing**: only a `<queries>` entry exists.
- **Limited-use expectations:** use Health Connect data only to provide or improve the user-facing features disclosed. Do not use it for advertising. Do not sell it. Transfer it to third parties only as needed to provide the feature, with disclosure and consent. **[Counsel]** Whether sending a weight summary to a third-party LLM fits "providing the user-facing feature". Treat it as requiring explicit, separate consent.
- `READ_HEALTH_DATA_HISTORY` (data older than 30 days) needs its own justification.
- **Health apps declaration:** Play Console requires a health apps declaration for apps with health and fitness features. **[Verify]** current form.

### 7.2 Data Safety form — draft answers (must match code at submission)

| Data type (Play taxonomy) | Collected | Shared* | Optional? | Purpose |
|---|---|---|---|---|
| Personal info → Name | Yes | Yes (AI provider, in the prompt; remove to make this "No") | Required | App functionality, personalisation |
| Personal info → Email address | Yes (email/Google sign-in) | No | Required for that sign-in method | Account management |
| Personal info → Phone number | Yes (phone sign-in) | Yes, to the SMS OTP provider (**[Counsel]** may count as a service provider and therefore not "sharing") | Optional sign-in method | Account management |
| Personal info → Other (age, gender) | Yes | Yes (AI provider) | Required | App functionality, personalisation |
| Health and fitness → Health info (height, weight, body metrics) | Yes | Yes (AI provider) | Required | App functionality, personalisation |
| Health and fitness → Fitness info (steps, workouts, sleep, HRV) | Yes | Weight summary to AI | Optional (Health Connect) | App functionality |
| Photos | Yes (user-attached) | Yes (AI provider) | Optional | App functionality |
| App activity → Other user-generated content (meal text, chat) | Yes | Yes (AI provider) | Required for AI features | App functionality |
| App info & performance → Crash logs / Diagnostics | No SDK. Server logs only. | No | — | — |
| Device or other IDs | No | No | — | — |

\*Under Play's definitions, a transfer to a **service provider** acting on your behalf may not count as "sharing". **[Counsel]** Decide on each AI provider and record the reasoning.

Also declare: data is **encrypted in transit** (HTTPS/TLS to Supabase and the AI providers), users **can request deletion** (once §4 is built), and the **deletion URL**.

---

## 8. Apple — HealthKit, App Privacy labels, review guidelines

### 8.1 HealthKit — [Confirmed core; Verify details]
- Guideline **5.1.3**: health data may not be used for advertising, marketing or use-based data mining, except to improve health or for approved research. It may not be disclosed to third parties without the user's consent. Health information may not be stored in iCloud. The app must have a privacy policy.
- Technical requirements: the HealthKit **capability and entitlement**, plus `NSHealthShareUsageDescription` (read). `NSHealthUpdateUsageDescription` is only needed if the app writes. **None of these are present** in `ios/Runner/` today (no `.entitlements` file, no usage strings in `Info.plist`).
- Camera and photos: `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` are **missing**. The iOS camera path in `ai_coach_screen.dart` will crash without `NSCameraUsageDescription`.

### 8.2 Other Apple requirements — [Verify]
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) declaring data collected and required-reason APIs. For example, `NSUserDefaults` is used by `shared_preferences`. Missing.
- **Guideline 5.1.1(v)** in-app account deletion (§4).
- **Guideline 4.8 (login services):** an app that offers a third-party login such as Google must also offer an equivalent login option that meets Apple's privacy criteria. Sign in with Apple satisfies this. **[Verify]** current wording and whether email/phone sign-in alone satisfies it.
- **Third-party AI disclosure:** Apple's guidelines (5.1.2) require clear disclosure, and **explicit permission**, before personal data is shared with third parties, including third-party AI. **[Verify]** current text.

### 8.3 App Privacy ("nutrition") labels
Mirror the §7.2 table using Apple's categories: Contact Info (name, email, phone), Health & Fitness (health, fitness), User Content (photos, other user content), Identifiers (user ID: linked to the user, not used for tracking). **Tracking: No.** No data is used for tracking as Apple defines it, so no ATT prompt is needed. Re-check whenever an SDK is added.

---

## 9. Analytics, telemetry and logging isolation

Kynetix has **no analytics or crash SDK today**, which is the safest state. If one is added, it must follow these rules:

1. **Three walled tiers.** (a) Strictly necessary: auth session, local cache. (b) Product telemetry: anonymous event names, timings, sanitised errors, behind opt-in consent. (c) Personal fitness and nutrition data: Supabase only. **Tier (c) never flows into tier (b).**
2. **Forbidden in any telemetry or crash payload:** name, email, phone, user ID linked to content, meal text, chat text, photos, weights, body metrics, health-platform data, AI prompts or responses.
3. **No session replay or screen recording tools** (Hotjar, FullStory, Clarity, LogRocket, Smartlook and similar).
4. **No advertising, attribution or cross-app tracking SDKs.** Adding one changes the Data Safety, App Privacy and ATT answers and the DPDP children analysis.
5. **Logging hygiene, which applies today:**
   - Flutter `debugPrint` **is not stripped in release builds**. There are about 370 `debugPrint` calls in `lib/`, several logging email, phone or chat text (e.g. `auth_service.dart:23, 41, 87, 98`; `ai_coach_screen.dart:197-201`). Wrap them in `if (kDebugMode)` or a logger that no-ops in release, and never log PII or content.
   - Edge Functions must not log prompt or response content or raw provider bodies (`ai-chat-router/index.ts:132, 214, 345, 356, 394`; `openai-link-poll/index.ts:309`). Log IDs, status codes and lengths only.

---

## 10. Open-source licences and third-party assets

- **Bundled fonts (`assets/google_fonts/`):** Inter and Bricolage Grotesque are under the **SIL Open Font License 1.1**. The OFL allows bundling and redistribution with software. The copyright notice and licence text must accompany the fonts, the fonts may not be sold on their own, and Reserved Font Name rules apply to modified versions. **[Confirmed]**
  - `OFL.txt` and `OFL-Inter.txt` are already bundled. Also **register them** with `LicenseRegistry.addLicense` so they appear on Flutter's licence page.
  - Expose `showLicensePage` from Profile → "Open-source licences". Not present today.
- **google_fonts runtime fetching:** set `GoogleFonts.config.allowRuntimeFetching = false` in `main.dart`. Otherwise any weight or style not bundled (e.g. italic) is fetched from Google's servers at runtime, which leaks the IP address and fails offline.
- **Dependencies:** run a licence audit of `pubspec.lock` before every release. Permissive licences (MIT, BSD, Apache-2.0) are approved. Weak copyleft (LGPL, MPL) needs review. GPL/AGPL code linked into the app is prohibited. Generate an SBOM per release (CycloneDX or SPDX).
- **Exercise dataset and media:** `assets/data/exercises_library.json` and media from `github.com/hasaneyldrm/exercises-dataset` (`exercise_media_service.dart:13-20`). **[Counsel] Confirm the licence permits commercial redistribution and hot-linking.** Prefer bundling or self-hosting the media to remove the third-party IP exposure.
- **Trademarks:** "ChatGPT" and "OpenAI" are third-party marks. Use them only descriptively ("Connect your ChatGPT account"), with no implied endorsement. Run a trademark clearance check for "Kynetix" and "Kyno" (IP India, Class 9/42/44 as advised by counsel) before launch. **[Counsel]**

### 10.1 Connect ChatGPT — special review item **[Counsel]**
The feature uses OpenAI's device-authorisation flow and calls `chatgpt.com/backend-api/codex/...` with the user's consumer OAuth token (`ai-chat-router/index.ts:5-7, 28`). It is not clear that OpenAI's terms let third-party apps use these endpoints or consumer tokens this way. Before launch, get legal review of the OpenAI terms and confirm the token storage design (§11). Be ready to remove the feature.

---

## 11. Security baseline (the "reasonable safeguards" duty)

1. **Row Level Security** on every user table, scoped to `auth.uid() = user_id`. The schema and policies must be committed to the repo as migrations (`supabase/supabase/` is empty) so they can be reviewed.
2. **OAuth tokens at rest:** store `user_openai_links.access_token` / `refresh_token` encrypted (e.g. Supabase Vault or pgsodium column encryption). Make them unreadable through any client-facing RLS policy and reachable only through the service role.
3. **No secrets in the client.** This holds today: only the Supabase URL, the anon key and Google client IDs, all of which are public by design. Keep `secrets.dart` and `supabase_secrets.dart` gitignored (they are).
4. **Edge Functions:** verify the JWT on every call (already done in the routers). Tighten `Access-Control-Allow-Origin: '*'` if any web client is shipped. Add per-user rate limits on AI endpoints.
5. **Transport:** HTTPS only. No cleartext traffic.
6. **Local data:** `shared_preferences` is not encrypted. That is acceptable for non-credential cache, but never store tokens or passwords there. The Supabase session is managed by `supabase_flutter`.
7. **Deep links:** `kynetix://reset-password`, `kynetix://login-callback` and `kynetix://openai-auth/callback` must validate their parameters and must never accept tokens from untrusted sources.

---

## 12. Breach response

1. **Lifecycle:** Detect → Triage → Contain (revoke keys, trip the AI kill switch, rotate the Supabase service role key and OpenRouter key) → Investigate → Remediate → Notify → Recover → Post-mortem.
2. **CERT-In:** under the CERT-In Directions of April 2022 (IT Act s.70B), reportable cyber-security incidents, including data breaches and unauthorised access, must be reported to CERT-In **within 6 hours** of noticing them. **[Confirmed]** Keep the reporting contact and form ready.
3. **DPDP s.8(6):** notify the **Data Protection Board** and **each affected user** of a personal data breach, in the form, manner and timelines set by the DPDP Rules. **[Verify]** current timelines. The Rules require detailed follow-up reporting within a set period.
4. **Platform obligations:** check the Google Play and Apple developer agreements for incident duties involving Health Connect or HealthKit data.
5. **Named owner:** [Security/incident contact]. A runbook must exist before launch.

---

## 13. Terms of Service essentials (separate doc, to draft)
- 18+ eligibility (§3.6).
- Wellness, not medical advice. AI output is estimated and may be wrong. Consult a professional before major diet or training changes, or if you have a medical condition.
- Acceptable use (no scraping or abuse of the AI endpoints). Third-party account linking (ChatGPT) is governed by that provider's terms.
- Governing law: India. Jurisdiction: [City] courts. **[Counsel]**
- Terms cannot override non-waivable consumer rights (Consumer Protection Act 2019) or DPDP duties. **[Confirmed]**

---

## 14. Gap checklist — fix before release

Verified against code on 2026-10-16. **P0 = launch-blocking.**

| # | Pri | Gap | Evidence (file:line) | Fix |
|---|---|---|---|---|
| 1 | P0 | **No account deletion** (in-app or web) | No delete path anywhere in `lib/` or `supabase/functions/` | Build the §4.2 pipeline, a Profile entry, and a web URL. |
| 2 | P0 | **No privacy notice / policy link / consent capture** at sign-up or onboarding | `lib/screens/auth_screen.dart`, `lib/screens/onboarding_screen.dart` (no privacy/terms/consent references in `lib/`) | Add a notice with policy and terms links, unbundled opt-ins (§3.2), and a consent log table. |
| 3 | P0 | **Minors accepted:** age validator allows 10–100 | `lib/screens/onboarding_screen.dart:516` | Require 18+ and block plus purge on an under-18 signal (§3.6). |
| 4 | P0 | **Personal + health-derived data sent to third-party AI without explicit opt-in or disclosure**, including the user's **name** | `supabase/functions/ai-meal-coach/index.ts:693-699, 804-807`; `lib/services/ai_coach_service.dart:199-200`; photos `lib/screens/ai_coach_screen.dart:134-190` | AI consent gate; drop the name; disclosure; local-only fallback when consent is declined. |
| 5 | P0 | **OpenRouter data policy unverified**; `:free` vision model in the chain | `supabase/functions/ai-chat-router/index.ts:35-43` | Turn on the no-training / no-retention provider filter in OpenRouter; remove models that log or train; document it in §5. |
| 6 | P0 | **Health Connect manifest/code mismatch:** code requests sleep and HRV, manifest declares only steps, weight and history | `lib/services/health_service.dart:475-478`; `android/app/src/main/AndroidManifest.xml:5-8` | Add `READ_SLEEP` / `READ_HEART_RATE_VARIABILITY` with Play justification, or drop those features. Remove `ACTIVITY_RECOGNITION` if it is not needed. |
| 7 | P0 | **Health Connect rationale/privacy screen not implemented** (alias points to `MainActivity`, which ignores it; Android ≤13 rationale intent filter missing) | `AndroidManifest.xml:61-70, 92-97`; `android/app/src/main/kotlin/com/kynetix/app/MainActivity.kt` | Handle both intents and show the privacy policy and health-data rationale. |
| 8 | P0 | **iOS: no HealthKit entitlement or usage strings, no camera/photo usage strings, no privacy manifest** | `ios/Runner/Info.plist`; no `*.entitlements` or `PrivacyInfo.xcprivacy` | Add all of them. Without `NSCameraUsageDescription` the camera path crashes. |
| 9 | P0 | **Connect ChatGPT terms risk + plaintext-looking token storage** | `supabase/functions/openai-link-poll/index.ts:218-224`; `ai-chat-router/index.ts:28` | Legal review (§10.1); encrypt the tokens; RLS deny to clients. |
| 10 | P0 | **Database schema/RLS not in the repo, so it cannot be verified** | `supabase/supabase/` is empty | Commit migrations with RLS for all 12+ user tables; add a test. |
| 11 | P1 | **PII and content in release logs** (`debugPrint` survives release) | `lib/services/auth_service.dart:23,41,87,98`; `lib/screens/ai_coach_screen.dart:170,184,197-201`; ~370 calls total | Gate on `kDebugMode`; redact. |
| 12 | P1 | **Edge Functions log AI content and raw provider bodies** | `supabase/functions/ai-chat-router/index.ts:132,214,345,356,394`; `openai-link-poll/index.ts:309` | Log metadata only. |
| 13 | P1 | **No "not medical advice" / AI-estimate disclaimer in the coach** | No matches for `medical advice`/`disclaimer` in `lib/` | Add it to the AI coach header and first-run screen, and to the Terms. |
| 14 | P1 | **google_fonts runtime fetching enabled** | `lib/config/app_theme.dart` uses `GoogleFonts.*`; no `allowRuntimeFetching = false` anywhere | Disable it in `main.dart`. |
| 15 | P1 | **OFL licences not registered; no licences page** | `assets/google_fonts/OFL*.txt` bundled but no `LicenseRegistry` or `showLicensePage` in `lib/` | Register them and add Profile → Licences. |
| 16 | P1 | **Third-party CDN exercise media + unverified dataset licence** | `lib/services/exercise_media_service.dart:13-20`; `assets/data/exercises_library.json` | Confirm the licence; bundle or self-host the media. |
| 17 | P1 | **Email/phone duplicated into `profiles`** | `lib/services/profile_service.dart:101-104` | Read them from `auth.users`. Drop the duplicate columns unless a feature needs them. |
| 18 | P1 | **Google sign-out does not disconnect**, so the grant stays on the Google account after account deletion | `lib/services/auth_service.dart:68-71` | Use `disconnect()` in the deletion flow. |
| 19 | P2 | **Health permissions requested in a chain without in-context rationale** | `lib/screens/dashboard_screen.dart:360-376` | Show a pre-permission explainer for each data type. |
| 20 | P2 | **Expired device-auth sessions not purged** | `openai_device_auth_sessions` (no cleanup job found) | Scheduled purge. |
| 21 | P2 | **Photos may carry EXIF/GPS** | `lib/screens/ai_coach_screen.dart:163-180` | Verify that `image_picker` re-encoding strips it, or strip it explicitly. |
| 22 | P2 | **No grievance/contact channel in the app** | — | Add Profile → Privacy & Help with grievance contact and the rights request path. |
| 23 | P2 | **CORS `*` on Edge Functions** | `supabase/functions/ai-chat-router/index.ts:22-25` | Restrict if a web client ships. |

### Release sign-off
- [ ] All P0 gaps closed and verified on a physical Android device and an iOS device.
- [ ] `PRIVACY_POLICY.md` matches §2 and §5 exactly and is hosted at a public URL.
- [ ] The privacy policy URL is in the Play Console, App Store Connect, the Google OAuth consent screen, the Health Connect rationale screen and the in-app Profile screen.
- [ ] Play Data Safety, Health Connect declaration, health apps declaration and Apple App Privacy labels are submitted and match the code.
- [ ] Processor DPAs and terms accepted; AI no-training settings confirmed with screenshots archived.
- [ ] Indian counsel has signed off on the Privacy Policy, Terms and consent texts.
