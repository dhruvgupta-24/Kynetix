> **DRAFT: NOT FOR PUBLICATION.** This policy is a draft written from the Kynetix code as of 2026-10-16. Qualified Indian legal counsel must review it before it is published or linked from the app or store listings. Everything in `[square brackets]` is a placeholder the owner must fill in. Lines marked **(Requires feature)** describe things the app must support **before** this policy goes live. See `LEGAL_PRIVACY_AND_COMPLIANCE.md` §14.

# Kynetix Privacy Policy

**Effective date:** [Effective date]
**Version:** [1.0]

Kynetix is a fitness and nutrition app. It helps you log meals and workouts, estimate calories and protein, and get coaching from our AI assistant, Kyno. This policy explains what we collect, why, who we share it with, and the choices you have.

Kynetix is provided by **[Company legal name]**, [registered address] ("we", "us"). For the purposes of India's Digital Personal Data Protection Act, 2023, we are the *Data Fiduciary* for your personal data.

---

## 1. The short version

- We collect what you type or choose to connect: your account details, your body profile, your meal and workout logs, and, if you allow it, step, weight, sleep and heart-rate-variability data from Health Connect or Apple Health.
- To give you AI estimates and coaching, we send parts of your data to AI providers. **This only happens when you use the AI features.** These providers process your data outside India.
- AI answers are **estimates, not medical advice**. Your own logged entries always take priority over AI suggestions.
- We do **not** sell your data. We do **not** show ads. We do **not** use your data to train AI models, and we configure our AI providers not to train on it.
- You can see, correct and delete your data, and delete your account from inside the app.
- Before you use Kynetix, we ask you to agree to this policy and to confirm that you are 18 or older.
- Kynetix is for people **18 and older**.

---

## 2. What we collect

### 2.1 Information you give us

| What | Examples | Why |
|---|---|---|
| **Account details** | Email address and password; **or** mobile phone number (verified with a one-time code by SMS); **or** your Google account (name and email shared by Google when you choose "Sign in with Google") | To create your account, sign you in and keep it secure |
| **Body and goal profile** | Name, age, gender, height, weight, fitness goal, training days per week, portion-size preferences, custom calorie and protein targets and the history of changes to them | To calculate your daily targets and personalise the app |
| **Meal logs** | What you ate (as you type it), the items we recognise, calories and macros, meal times, saved and recurring meals, quick-adds, and corrections you make to food values | To track your nutrition and remember your usual foods |
| **Workout logs** | Workout splits, sessions, exercises, sets, weights and reps, exercise preferences, achievements | To track your training and show your progress |
| **Messages to Kyno (AI coach)** | Questions you type and replies you receive | To answer your questions |
| **Photos you attach** | Photos of plates, menus or delivery screenshots that you take or pick from your gallery to ask Kyno about | To estimate what is in the photo. We only access photos you choose. |

### 2.2 Information from Health Connect (Android) or Apple Health (iOS), only if you allow it

With your permission, Kynetix **reads** (and never writes):
- **Steps.** Shows your activity and adjusts calorie estimates.
- **Body weight readings.** Shows weight trends.
- **Sleep sessions** and **heart-rate variability.** Shows recovery insights.

You choose each type of data in your phone's permission screen, and you can turn access off at any time in Health Connect or Apple Health settings. Step, sleep and heart-rate-variability data stays **on your device**. A short **summary of your weight trend** (for example, your current weight and 7-day change) is included in requests to the AI coach so it can give relevant advice. See Section 4.

We use Health Connect and Apple Health data only to provide the features described here. We never use it for advertising, never sell it, and never store it in iCloud.

### 2.3 Information collected automatically

- **Technical information.** When the app talks to our servers, our hosting provider receives your IP address and basic request details, and our server functions keep short-lived logs. These include your account ID and technical details such as error codes.
- **Exercise images and videos.** These load from public content networks ([jsDelivr / GitHub: confirm or replace]). Those services see your device's IP address when the media loads.
- **No analytics, advertising or tracking tools.** Kynetix does not include advertising, analytics, attribution or session-recording SDKs, and does not track you across other apps or websites.

### 2.4 Information stored on your device

To work quickly and offline, the app keeps a copy of your profile, recent logs, food memories, insights, and the numbers shown on the Kynetix home-screen widget (today's calories and protein) in the app's private storage on your phone. Signing out clears it from the app's memory and the widget. Deleting your account removes your account's copy from the phone (see Section 8). The app also stores a record that you agreed to this policy (see Section 3A).

---

## 3. How we use your information

We use your information only to:
1. Provide the app: your account, logging, sync across devices, targets, progress and insights.
2. Provide AI features: meal estimates from text or photos, coaching replies and AI-generated reports, **when you use them**.
3. Keep the service secure, prevent abuse, and fix problems.
4. Meet our legal obligations and respond to lawful requests.

We will not use your data for a new, unrelated purpose without telling you first and, where the law requires it, asking for your consent.

---

## 3A. Your agreement to this policy

- **New accounts.** The first step of setting up Kynetix shows a short privacy notice with a link to this policy. To continue, you tick "I agree to the Privacy Policy" and "I'm 18 or older".
- **Existing accounts.** If you signed up before we asked for this, you see the same notice once after you sign in, before the app opens.
- **What we record.** The policy version you agreed to, the time you agreed, and your 18+ confirmation. We keep this on your phone and on your profile on our servers.
- **If you don't agree,** you can't use Kynetix. You can still read this policy and sign out. Nothing new is collected.
- **When this policy changes** in a way that needs your agreement again, we show the notice again (see Section 12).

---

## 4. AI features and your data

Kynetix uses third-party AI models to estimate nutrition and to power Kyno.

**What is sent when you use an AI feature:**
- your message or meal description, and any photos you attach;
- your profile details used for coaching (age, gender, height, weight, goal, training frequency) [and your first name: *owner: remove before launch; see compliance doc gap #4*];
- relevant context from your Kynetix history: today's log, up to the last 30 days of meal and workout logs, your most-used foods, and a summary of your weight trend if you connected Health Connect or Apple Health.

**What is not sent:** your email address, phone number or password.

**Who processes it:**
- **By default**, requests go through our servers to **OpenRouter**, an AI gateway, which passes them to a model provider such as **DeepSeek**, **Google (Gemini)** or **NVIDIA**. These providers are located outside India, mainly in the United States. [Owner: confirm the final model list.]
- **If you choose "Connect ChatGPT"**, your requests go to **OpenAI** using *your own* ChatGPT account. OpenAI's handling of that data follows your ChatGPT account settings and OpenAI's privacy policy. We ask OpenAI not to store these conversations in your ChatGPT history. We securely store the sign-in tokens needed to make requests for you, and we delete them when you disconnect.

**Our commitments:**
- We do **not** use your data to train or improve AI models. We configure our AI gateway to send your data only to providers that do not train on it or keep it beyond what is needed to answer your request. [Owner: confirm OpenRouter settings before publishing.]
- AI results are clearly labelled (for example, the "AI" badge on meal estimates). They are **estimates** and may be wrong. You can always edit them, and your edits are what Kynetix saves.
- Kyno does not provide medical advice, diagnosis or treatment. Talk to a qualified doctor or dietitian before making major changes to your diet or training, especially if you have a medical condition, are pregnant, or have a history of disordered eating.

**Your choice:** **(Requires feature)** Before your data is first sent to an AI provider, we will ask for your permission. You can turn AI features off at any time in [Profile → Privacy]. Basic meal logging still works without AI, using on-device estimates.

---

## 5. Who we share data with

We share data only with service providers that help us run Kynetix, and only as needed:

| Provider | What they do | Data involved | Location |
|---|---|---|---|
| **Supabase, Inc.** | Hosts our database, sign-in system and server functions | Account, profile, logs, AI-coach connection status, server logs | [Supabase project region: e.g. Mumbai, India / other] |
| **[SMS provider]** (via Supabase) | Sends one-time sign-in codes | Phone number | [Location] |
| **Google** | "Sign in with Google" | Your Google account email and name, and a sign-in token | Global |
| **OpenRouter, Inc.** and the AI model providers it routes to (DeepSeek, Google, NVIDIA) | AI estimates and coaching | See Section 4 | Outside India (mainly USA) |
| **OpenAI**, only if you connect ChatGPT | AI coaching through your own account | See Section 4 | USA |
| **Content networks** ([jsDelivr / GitHub]) | Deliver exercise images and videos | Your IP address | Global |

We may also disclose information if the law requires it, to protect people's safety, or as part of a merger or acquisition (in which case this policy, or one at least as protective, will continue to apply).

**We do not sell your personal data, and we do not share it for advertising.**

---

## 6. International transfers

Some of our providers process data outside India, in particular the AI providers in Section 5. We transfer data only as Indian law permits, and we choose providers with appropriate security and contractual protections.

---

## 7. How long we keep data

- **Your account data and logs** are kept while your account is active.
- **When you delete your account**, we delete your profile, logs, workouts, food memories, AI-coach connection and sign-in record from our live systems within [N] days. Copies in our hosting provider's backups are deleted automatically within [backup retention period, e.g. 7–30 days].
- **ChatGPT connection tokens** are deleted as soon as you disconnect.
- **Server logs** are kept for up to [30] days.
- **Photos** you send to Kyno are not stored by us after the request is processed.
- **Data on your phone** is removed when you sign out or uninstall the app.

---

## 8. Your rights and choices

Under Indian law you can:
- **Access.** Get a summary of the personal data we hold about you and who we have shared it with.
- **Correct or update.** Fix inaccurate or incomplete data. You can edit most of it directly in the app.
- **Erase.** Ask us to delete your data, or delete your account (see below).
- **Withdraw consent.** For example, turn off Health Connect / Apple Health access, AI features or the ChatGPT connection. Withdrawing consent stops future processing for that purpose but does not affect what was already done lawfully.
- **Nominate.** Name someone to exercise these rights for you if you die or become unable to.
- **Complain.** Raise a grievance with us (Section 11). If you are not satisfied, you may complain to the Data Protection Board of India.

**Delete your account:** In the app, go to **[Profile → Delete account & data]**. The screen lists what is deleted: your meals, calories and macros, workouts, profile and targets, ChatGPT link, saved meals, food memories, insights and everything else. To confirm, you type DELETE. We then delete your account and data from our servers. Once our servers confirm, the app removes your account's data from your phone and signs you out. Data of other accounts on the same phone, and device settings such as the app theme, are kept. **Deletion can't be undone.** If the deletion fails (for example, you are offline), nothing is deleted and you can try again. If you no longer have the app, request deletion at **[deletion request URL]** or email **[privacy contact email]** from the address linked to your account.

To exercise any other right, email **[privacy contact email]**. We may need to verify your identity first. We aim to respond within [timeframe: counsel to confirm the statutory period].

---

## 9. Children

Kynetix is intended only for people **aged 18 and over**. We do not knowingly collect personal data from anyone under 18. Before you use the app, you confirm that you are 18 or older. During setup, the app asks for your age and will not create a profile for anyone under 18. If we learn that someone under 18 has an account, we will lock it and delete their data. If you believe a minor is using Kynetix, contact **[privacy contact email]**.

---

## 10. Security

We protect your data with encrypted connections (HTTPS) between the app and our servers, access controls that limit each user to their own data, sign-in tokens kept on our servers and never exposed to the app, and AI provider keys held only on our servers. No system is perfectly secure. If a personal data breach affects you, we will tell you and the authorities as Indian law requires.

---

## 11. Contact and grievance officer

**Grievance Officer:** [Grievance officer name]
**Email:** [Grievance officer email]
**Address:** [Company legal name], [registered address]
**General privacy questions:** [privacy contact email]

We aim to acknowledge grievances within [24–48 hours] and resolve them within [timeframe: counsel to confirm].

---

## 12. Changes to this policy

We will update this policy when our practices change. If we make a significant change, especially one affecting how AI or health data is used, we will notify you in the app before it takes effect and, where required, ask for your consent again. The version and effective date at the top show the current version.

---

## 13. Third-party terms and open-source

- Health Connect is provided by Google, and Apple Health by Apple. Their own terms and privacy policies apply to data stored in them.
- If you connect ChatGPT, OpenAI's terms and privacy policy apply to your ChatGPT account.
- Kynetix includes open-source software and fonts (including Inter and Bricolage Grotesque under the SIL Open Font License 1.1). **(Requires feature)** Licence notices are available in [Profile → Open-source licences].
