# Kynetix: Product Marketing Context & Growth Strategy

The canonical source of truth for Kynetix product marketing, positioning, customer psychology, competitive moats, conversion architecture, and distribution loops. Built on the playbooks from `coreyhaines31/marketingskills`.

---

## 1. Core Positioning & The Wedge

### 1.1 The One-Liner
> **Real food. Real lifts.** The offline-first, open-source nutrition and workout tracker built specifically for Indian diets and strength training.

### 1.2 The Positioning Formula
* **For:** Indian fitness enthusiasts, lifters, and health-conscious individuals who eat homemade meals (dal, roti, sabzi, curd, paneer) and train consistently.
* **Who Struggle With:** Mainstream fitness apps (MyFitnessPal, HealthifyMe) that lock basic barcode scanning and macro targets behind expensive yearly paywalls (₹3,000–₹5,000/yr), spam user screens with upsell coaching calls and intrusive ad networks, monetize private biometric data, and fail completely on Indian home-cooked portion geometry (katoris, rotis, gravies).
* **Kynetix Is:** An offline-first, MIT-licensed open-source Android app that integrates calibrated Indian nutrition tracking (ICMR-NIN IFCT 2017) with dedicated strength training logging in a single unified interface.
* **Unlike Competitors:** Kynetix is 100% ad-free, runs locally on phone storage via encrypted SQLite, supports natural-language meal logging ("2 roti, 1 katori dal"), includes free barcode scanning, connects seamlessly to Android Health Connect, and features an AI coach (Kyno) that understands South Asian food chemistry and weight lifting together.

---

## 2. Ideal Customer Profiles (ICPs) & Personas

### Persona 1: The South Asian Lifter ("Aarav")
* **Profile:** 24, software engineer in Bengaluru / Gurugram. Trains push-pull-legs 4–5 days/week.
* **Daily Diet:** Mom’s or mess home cooking: rotis, moong dal, paneer bhurji, curd, occasional chicken curry, whey protein.
* **Core Pain:** Uses MyFitnessPal or HealthifyMe, but gets exasperated having to guess grams of raw wheat vs. cooked roti, hates intrusive tele-sales coaching popups, and resents paying ₹3,000/year just to scan a barcode on his peanut butter jar.
* **What Convinces Him:** Natural language logging ("2 roti and dal makhani"), built-in gym workout logging with personal record tracking, zero ads, and transparent data privacy.

### Persona 2: The Privacy & Open-Source Advocate ("Karthik")
* **Profile:** 29, systems engineer, self-hoster, uses F-Droid / GitHub.
* **Core Pain:** Refuses to upload his biometric health telemetry, daily weight fluctuations, and heart rate data to corporate cloud brokers or ad networks.
* **What Convinces Him:** MIT license, open repository on GitHub (`dhruvgupta-24/Kynetix`), 100% offline-first local SQLite architecture, full JSON/CSV data export, zero analytics trackers, and single-tap complete account and data erasure.

### Persona 3: The Dedicated Strength Athlete ("Vikram")
* **Profile:** 27, powerlifting and hypertrophy practitioner.
* **Core Pain:** Currently forced to maintain two separate apps: Strong/Hevy for gym logs and a clunky nutrition app for food. Neither app communicates with the other.
* **What Convinces Him:** Unified workout and nutrition tracking in one lightweight app; plate calculators, rest timers, superset support, Hevy/Strong CSV import, and calorie/protein targets that automatically elevate on heavy training days and reduce on rest days.

---

## 3. Jobs To Be Done (JTBD)

| When I... | I want to... | So I can... |
|---|---|---|
| Sit down for a homemade Indian meal | Type or speak what is on my plate in plain words ("2 roti, dal, half bowl rice") | Log accurate calories and protein in under 10 seconds without weighing every grain of cooked rice. |
| Finish a hard gym workout | Log sets, reps, and RPE with automated rest countdowns and plate math | Ensure progressive overload across weeks without using Excel or switching between two different apps. |
| Look at my daily nutrition progress | See intuitive rings showing remaining calories, protein, and carbs directly on my Android home screen | Stay accountable throughout a busy workday without constantly opening the app. |
| Scan a packaged snack or whey protein pack | Point my camera at the barcode | Log the exact verified pack instantly for free without hitting a subscription paywall. |
| Wonder if my diet is actually working | Ask an AI coach that already analyzed my last 14 days of food and training | Get an honest, non-judgmental pattern breakdown instead of generic web articles. |

---

## 4. Competitive Differentiation Matrix

| Capability | Kynetix | MyFitnessPal | HealthifyMe | Hevy / Strong |
|---|---|---|---|---|
| **Licence & Openness** | **MIT Open Source (GitHub)** | Proprietary Closed | Proprietary Closed | Proprietary Closed |
| **Monetization & Ads** | **100% Free Core, Zero Ads** | Ads + ₹3,000–₹5,000/yr | Ads + ₹2,000–₹6,000/yr + coaching calls | Freemium ($30–$40/yr for unlimited routines) |
| **Indian Nutrition Geometry** | **ICMR-NIN IFCT 2017 calibrated (katori, roti, plate)** | Crowdsourced, heavily Western-skewed | Indian database present | None (Workout only) |
| **Barcode Scanning** | **Built-in Free (Open Food Facts)** | Locked behind Premium paywall | Basic | None |
| **Combined Food + Gym Tracker** | **Yes (Unified in one app)** | Food only (Workouts rudimentary) | Food only (Workouts rudimentary) | Workout only (No food tracking) |
| **Offline-First Storage** | **Yes (Local SQLite + encrypted sync)** | No (Requires persistent connection) | No (Requires persistent connection) | Strong is offline; Hevy is cloud-dependent |
| **Health Connect Integration** | **Native Read-Only (Steps, Weight, Sleep, HRV)** | Basic sync | Basic sync | Limited |
| **AI Context Architecture** | **Kyno reads BOTH meals and gym sets** | Generic LLM tips | "Ria" chatbot / Human upsell | None |
| **Data Sovereignty** | **Full JSON & CSV Export / Complete Erasure** | Limited export behind paid tiers | Restricted | CSV export |

---

## 5. Voice, Tone & Anti-AI Copywriting Rules

To maintain high trust, authority, and authenticity, all Kynetix marketing and documentation follows strict editorial guardrails:

### 5.1 The Banned Words List
Never use generic AI fluff or over-hyped tech tropes:
* ❌ *Banned:* "game-changer", "unleash", "supercharge", "delve", "testament", "seamlessly", "dive deep into", "revolutionary", "state-of-the-art".
* ✅ *Replacement:* Use direct verbs and concrete numbers: "saves 45 seconds", "stores locally on phone", "calibrated to ICMR-NIN standards", "tracks sets and PRs".

### 5.2 Voice Principles
1. **Fact-First, Zero Fluff:** State exactly what the app does, what it costs (free), what platforms it supports (Android beta), and what it does not do (it is not a clinical medical device).
2. **Respect for South Asian Food Culture:** Avoid framing Indian food as "bad" or "untrackable". Treat homemade roti, dal, chana, and curd as legitimate nutritional building blocks.
3. **Respect for User Autonomy:** No fear-mongering, no guilt-tripping notifications, no aggressive streak pressure.

---

## 6. Organic Growth & Acquisition Funnels

```
                       [ Organic Search / AI Answer Engines (AEO/GEO) ]
                                            │
                        ┌───────────────────┴───────────────────┐
                        ▼                                       ▼
        ┌───────────────────────────────┐       ┌───────────────────────────────┐
        │   Free Client-Side Tools      │       │   Competitor Comparisons      │
        │   • Indian Food Protein Calc  │       │   • Kynetix vs MyFitnessPal   │
        │   • Roti / Dal Macro Finder   │       │   • Kynetix vs HealthifyMe    │
        │   • South Asian TDEE Calc     │       │   • Kynetix vs Hevy / Strong  │
        └───────────────┬───────────────┘       └───────────────┬───────────────┘
                        │                                       │
                        └───────────────────┬───────────────────┘
                                            │
                                            ▼
                        ┌───────────────────────────────────────┐
                        │    Landing Page / Download Funnel     │
                        │    • Value Clarity & Preempt Fears    │
                        │    • Direct APK + Google Play Beta    │
                        └───────────────────┬───────────────────┘
                                            │
                                            ▼
                        ┌───────────────────────────────────────┐
                        │   Activation & Retention Loops        │
                        │   • <60s First Meal / Set Logged      │
                        │   • Home Screen Widgets (4 Sizes)     │
                        │   • Shareable Workout Damage Cards    │
                        └───────────────────────────────────────┘
```

1. **Top of Funnel (AEO / GEO / Programmatic SEO):**
   - 10+ regional food and exercise calculators on `site/tools/` answering exact long-tail search intent.
   - Quotable 40–60 word answer boxes at the top of every guide for ChatGPT, Claude, and Perplexity citation.
2. **Middle of Funnel (Competitor Alternative Searches):**
   - Objective comparison pages capturing high-intent searchers seeking alternatives to MyFitnessPal and HealthifyMe.
3. **Bottom of Funnel (Zero-Friction Conversion):**
   - Dual-path installation: Instant Google Play Closed Beta access or direct standalone signed APK download with SHA-256 verification.
4. **Viral Retention Loop (Share Cards & Widgets):**
   - 5 stylized post-workout share cards ("Receipt: Paid in Sweat. No refunds", "Skyline: Every set to scale", "In Real Terms: 33 auto rickshaws moved") designed for Instagram Stories and WhatsApp fitness groups.
