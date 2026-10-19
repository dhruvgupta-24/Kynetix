# Kynetix Privacy Policy

**Effective date:** 20 October 2026

Kynetix is a fitness and nutrition app for Android. It helps you log meals and workouts, estimate calories and protein, and get coaching from Kyno, the app's AI coach. This policy explains what we collect, why, who it goes to, how long we keep it, and the choices you have.

Kynetix is made and run by **Dhruv Gupta**, an individual developer based in India ("we", "us"). Under India's Digital Personal Data Protection Act, 2023 (the "DPDP Act"), we are the Data Fiduciary for your personal data. You can reach us at **kynetix.app@gmail.com**.

---

## 1. The short version

- We collect what you type in or choose to connect: your account details, your body profile, your meal and workout logs and, only if you allow it, steps, weight, sleep and heart rate variability (HRV) from Health Connect.
- Your data is stored with our hosting provider, Supabase, so it syncs and survives a new phone.
- When you use an AI feature, the details needed to answer go to an AI provider. If you don't use the AI features, nothing goes to them.
- AI answers are estimates, not medical advice.
- We do not sell your data. We do not show ads. We do not use third-party analytics, advertising or tracking tools.
- You can delete your account and everything in it from inside the app, at any time. It happens straight away.
- Kynetix is for people aged 18 and over.

---

## 2. What we collect

### 2.1 Account details

- Your email address and password, or your Google account if you choose "Continue with Google". Google shares your name, email address and a sign-in token with us. If your sign-in uses a phone number, we keep that number with your account.
- A record that you agreed to this policy: the policy version, the time you agreed, and your confirmation that you are 18 or older.

### 2.2 Your profile

- Name, age, gender, height, weight, fitness goal, training days per week and portion-size preferences.
- Your calorie and protein targets, any custom targets you set, and the history of changes to them.
- Your average daily step count, if you connect Health Connect, so we can size your calorie target.
- A profile photo, only if you add one. It is kept in private storage that only your account can read.

### 2.3 Food and body logs

- What you eat, as you type or scan it: the foods we recognise, calories and macros, meal times, saved meals and quick-adds.
- Corrections you make to food values, so the app remembers your usual portions.
- Water and weight entries you log.

### 2.4 Training logs

- Your workout splits, sessions, exercises, sets, weights, reps, personal records, achievements and the insights we build from them.

### 2.5 Messages to Kyno

- Your questions and the details needed to answer them go to an AI provider (see Section 4).
- We do not save your Kyno chat history on our servers. The conversation lives only in the app's memory and is gone when the app closes.
- If you report a Kyno reply, we store the reason you picked, your optional note, the reply you reported and the question that led to it, so we can review it.

### 2.6 Photos

- If you attach a photo (a plate, a menu, a label or a delivery screenshot), it goes to an AI provider to be read. We do not store it. The app only sees photos you choose.

### 2.7 Barcodes

- When you scan a packaged food, the barcode number is sent to Open Food Facts, a public food database, to look up the product. Open Food Facts sees your device's IP address when it answers.

### 2.8 Health Connect (only if you allow it)

With your permission, Kynetix **reads** these from Health Connect and never writes to it:

- Steps
- Weight
- Sleep
- Heart rate variability (HRV)

You pick each type on Android's permission screen and can turn access off at any time in Health Connect. We do not copy your raw Health Connect readings to our servers. We save your average daily steps in your profile (Section 2.2) and whether sync is on. When you use Kyno, a summary of your recent steps and weight trend is included in the request so the advice fits you. We never use Health Connect data for advertising and never sell it.

### 2.9 Error reports

When something breaks in the app, it sends an error report to our own database. A report holds the error type, a short technical message, the app version, the platform and your account ID. Email addresses, phone numbers and sign-in tokens are stripped out before the report leaves your phone. We do not use any third-party crash reporting or analytics service.

### 2.10 Technical information

When the app talks to our servers, Supabase receives your IP address and basic request details, and our server functions keep short-lived logs. Exercise images and videos load from GitHub and jsDelivr, which see your IP address when the media loads.

### 2.11 On your phone

To work quickly and offline, the app keeps a copy of your profile, recent logs, food memory, insights and the numbers on the home-screen widget in its private storage. Your sign-in session is kept in Android's secure, encrypted storage.

---

## 3. How we use your information

We use your information only to:

1. Run the app: your account, logging, sync, targets, progress and insights.
2. Run the AI features when you use them: meal estimates from text or photos, Kyno's replies and AI-written summaries.
3. Keep the service secure, stop abuse, and find and fix bugs.
4. Meet our legal obligations.

We will not use your data for a new, unrelated purpose without telling you first and, where the law requires it, asking for your consent.

---

## 4. AI features and your data

Kynetix uses third-party AI models to estimate nutrition and to power Kyno. AI features run only when you use them: describing a meal for an estimate, attaching a photo, or chatting with Kyno.

**What is sent when you use an AI feature**

- Your message or meal description, and any photo you attach.
- Profile details used for coaching: first name, age, gender, height, weight, goal and training days.
- Relevant context from your history: today's log, recent meals and workouts, your most-logged foods, and your recent step and weight trend if you connected Health Connect.

**What is not sent:** your email address, phone number or password.

**Who processes it**

- **Google (Gemini API), Groq and OpenRouter.** Our servers send each request to one of these. OpenRouter passes requests on to the company that makes the chosen model, for example Google, NVIDIA or DeepSeek.
- **OpenAI, only if you choose "Connect ChatGPT".** Your requests then go to OpenAI using your own ChatGPT account, and OpenAI's handling follows your ChatGPT settings and OpenAI's privacy policy. We ask OpenAI not to store these conversations. We store the sign-in tokens needed to make requests for you on our servers and delete them when you disconnect.

These providers are based outside India, mainly in the United States.

**Our commitments**

- We do not use your data to train AI models. Each provider handles requests under its own terms. Depending on the provider, it may keep request data for a limited time, for example to prevent abuse.
- AI numbers are estimates and can be wrong. You can always edit them, and your edits are what Kynetix saves.
- Kyno does not give medical advice, diagnosis or treatment. Talk to a qualified doctor or dietitian before major changes to your diet or training, especially if you have a medical condition, are pregnant, or have a history of disordered eating.

**Your choice**

When you set up Kynetix, the privacy notice tells you that AI features send data to AI providers, some outside India. If you would rather not send anything to AI providers, don't use the AI features. You can still log food by barcode, quick-add or by typing in the numbers yourself, and log workouts without any AI. You can disconnect ChatGPT at any time in Settings.

---

## 5. Who we share data with

We share data only with the services that help run Kynetix, and only what each one needs:

| Service | What it does | Data involved |
|---|---|---|
| Supabase | Hosts our database, sign-in and server functions | Your account, profile, logs, error reports and Kyno reports |
| Google | "Continue with Google" sign-in, and Gemini AI | Sign-in details; AI requests as in Section 4 |
| Groq and OpenRouter | AI estimates and coaching | AI requests as in Section 4 |
| OpenAI | Only if you connect ChatGPT | AI requests as in Section 4 |
| Open Food Facts | Barcode lookups | The barcode number and your IP address |
| GitHub and jsDelivr | Deliver exercise images and videos | Your IP address |

We may also disclose information if the law requires it or to protect someone's safety.

**We do not sell your personal data, we do not share it for advertising, and we do not use third-party analytics.**

---

## 6. Transfers outside India

Some of these services process data outside India, in particular the AI providers and possibly our hosting provider's servers. We transfer data only as Indian law permits.

---

## 7. How long we keep data

- **Your account data and logs** are kept while your account exists.
- **When you delete your account,** your profile, logs, workouts, food memory, insights, error reports, Kyno reports, ChatGPT connection, profile photo and sign-in are deleted from our live database straight away.
- **Backups and server logs** are purged within 30 days.
- **ChatGPT connection tokens** are deleted as soon as you disconnect.
- **Photos** you send to Kyno are not stored by us.
- **Kyno chat history** is not stored by us.
- **Data on your phone** is cleared when you sign out, delete your account or uninstall the app.

---

## 8. Your rights

Under the DPDP Act you can:

- **Access** a summary of the personal data we hold about you and who we have shared it with.
- **Correct or update** inaccurate or incomplete data. Most of it you can edit directly in the app.
- **Erase** your data, or delete your account (see below).
- **Withdraw consent,** for example by turning off Health Connect access or disconnecting ChatGPT. This stops future processing for that purpose.
- **Nominate** someone to exercise these rights for you if you die or become unable to.
- **Raise a grievance** with us (Section 11). If you are not satisfied with our answer, you can complain to the Data Protection Board of India.

To use any of these rights, email **kynetix.app@gmail.com** from the address linked to your account. We may need to confirm it's you. We respond within 30 days.

### Delete your account

In the app, tap your profile picture or initials to open your profile and settings, scroll to **Account**, tap **Delete account**, then type DELETE to confirm. Your account and all its data are deleted from our servers straight away, then the app clears your data from the phone and signs you out. This can't be undone. If deletion fails, for example because you are offline, nothing is deleted and you can try again.

No longer have the app? Email **kynetix.app@gmail.com** from your account's email address with the subject "Delete my Kynetix account". We confirm it's you and delete the account within 30 days. Details: https://dhruvgupta-24.github.io/Kynetix/delete-account/

---

## 9. Children

Kynetix is only for people aged 18 and over. During setup you confirm that you are 18 or older, and the app will not create a profile for anyone younger. If we learn that someone under 18 has an account, we will delete it and its data. If you believe a minor is using Kynetix, email **kynetix.app@gmail.com**.

---

## 10. Security

Data travels between the app and our servers over encrypted connections (HTTPS). Database access rules limit each account to its own data. AI provider keys and ChatGPT tokens stay on our servers and are never sent to the app. Your sign-in session is kept in encrypted storage on your phone. No system is perfectly secure. If a personal data breach affects you, we will tell you and the authorities as Indian law requires.

---

## 11. Contact and Grievance Officer

**Grievance Officer:** Dhruv Gupta

**Email:** kynetix.app@gmail.com

**Location:** India

We acknowledge grievances as soon as we can and resolve them within 30 days.

---

## 12. Changes to this policy

We update this policy when our practices change. If a change is significant, especially one about AI or health data, we will tell you in the app before it takes effect and, where required, ask for your agreement again. The effective date at the top shows the current version.

---

## 13. Third-party terms and open source

- Health Connect is provided by Google. Google's terms and privacy policy apply to data stored in it.
- If you connect ChatGPT, OpenAI's terms and privacy policy apply to your ChatGPT account.
- Kynetix includes open-source software and fonts, including Inter and Bricolage Grotesque under the SIL Open Font License 1.1. Licence notices are in the app under Settings, Open-source licences.
