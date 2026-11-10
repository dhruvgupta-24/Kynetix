# Kynetix: Community Launch & Distribution Playbook

Practical, zero-spam launch copy and distribution playbooks designed specifically for community platforms. Written in authentic founder voice without marketing fluff.

---

## 1. Reddit: `r/Fitness_India`

* **Target Subreddit:** `r/Fitness_India` (200k+ Indian fitness enthusiasts & lifters)
* **Goal:** Recruit engaged beta testers, collect regional food database feedback, and establish organic goodwill.
* **Flair:** Discussion / OC / Guide

### Post Copy
```markdown
**Title:** I spent months building a free, open-source calorie & workout tracker specifically for Indian food and lifting (no ads, works offline). Looking for feedback!

Hey everyone,

Like many of you here, I’ve been lifting consistently and tracking my food for years. And like most people eating home-cooked Indian meals, I ran into the same frustrating wall with existing apps:

1. **Mainstream apps fail on Indian home food:** Trying to log home meals in MyFitnessPal or western apps is painful. A "katori of dal" or "2 homemade rotis with light ghee" doesn't match generic American food entries, and calculating raw vs. cooked weight every single night burns you out.
2. **Aggressive paywalls & ad bloat:** Mainstream apps now lock basic barcode scanning and macro goals behind ₹3,000–₹5,000/year subscriptions, and local Indian apps often bombard you with coaching calls and ads.
3. **Food and gym are disconnected:** You log meals in one app, and track sets and PRs in another (Hevy/Strong).

I got tired of this, so as an independent developer and lifter, I built **Kynetix** (https://dhruvgupta-24.github.io/Kynetix/).

### What it does:
* **Calibrated for Indian home food:** Calibrated against ICMR-NIN (National Institute of Nutrition IFCT 2017) data. Understands natural Indian portions: katoris (150g), rotis (35g), bowls, plates, and tadka absorption.
* **Natural language meal logging:** Just type what you ate: *"2 roti, dal makhani, half bowl rice"* or snap a quick photo.
* **Full strength training tracker built-in:** Log sets, reps, supersets, warmups, rest timers, and plate math in the same app. Your macro targets automatically adjust on heavy training days vs. rest days.
* **Free barcode scanning:** Uses Open Food Facts for packaged goods with zero paywall.
* **100% Offline-first & Private:** Everything runs locally on phone storage via encrypted SQLite. Zero ads, zero third-party trackers, and Health Connect integration is strictly read-only.
* **Open Source:** The core is completely open-source under the MIT license on GitHub (https://github.com/dhruvgupta-24/Kynetix).

### Current Status:
The app is currently in active beta on Android (Google Play closed beta and direct APK download on GitHub).

I’d genuinely love for fellow lifters here to test it out, stress-test the food database with your home meals, and tell me what’s missing or needs tweaking.

* **Website & direct APK:** https://dhruvgupta-24.github.io/Kynetix/download/
* **Google Play Closed Beta:** https://dhruvgupta-24.github.io/Kynetix/beta/
* **GitHub Repository:** https://github.com/dhruvgupta-24/Kynetix

Any feedback—positive or critical—on portion accuracy, UI speed, or lifting features is hugely appreciated!
```

---

## 2. Reddit: `r/opensource` & `r/androidapps`

### Post Copy
```markdown
**Title:** Kynetix – An offline-first, MIT-licensed calorie & workout tracker with zero ad-tech and local SQLite storage

**URL:** https://github.com/dhruvgupta-24/Kynetix

Hey everyone,

I built **Kynetix**, a fully open-source (MIT), offline-first Android application that combines calibrated nutrition tracking with strength training logging.

Most commercial health and nutrition apps have become heavily monetized data-harvesting platforms: they lock basic barcode scanning behind subscriptions, bundle invasive analytics SDKs, require continuous internet connectivity, and monetize private biometric telemetry.

### Architectural Highlights:
* **Offline-First Storage:** Local SQLite database with AES encryption; syncs with Supabase Row Level Security (RLS) only when online.
* **Zero Ad-Networks / Zero Trackers:** No third-party ad brokers or tracking pixels. All health telemetry stays on device.
* **Native Health Connect Integration:** Read-only ingestion for steps, body weight, sleep stages, and HRV.
* **Calibrated Nutrition Engine:** Calibrated to ICMR-NIN nutritional standards with natural-language text parsing and offline Open Food Facts barcode lookups.
* **Data Sovereignty:** Full one-tap JSON/CSV export and instant, irreversible account deletion.

The app is built with Flutter and Dart, backed by 1,500+ unit and integration tests.

* **GitHub:** https://github.com/dhruvgupta-24/Kynetix
* **Website & Releases:** https://dhruvgupta-24.github.io/Kynetix/

Feedback, issues, and contributions are very welcome!
```

---

## 3. Hacker News: `Show HN`

```text
Title: Show HN: Kynetix – Offline-first, open-source nutrition and workout tracker for Indian diets

Link: https://github.com/dhruvgupta-24/Kynetix

Hey HN,

I’m Dhruv, an independent software engineer from India. I built Kynetix: an offline-first, MIT-licensed Android app that pairs calibrated nutrition tracking with strength training logging.

The Problem:
Commercial nutrition trackers (MyFitnessPal, HealthifyMe) have three major flaws for South Asian diets and privacy-conscious users:
1. Skewed Databases: They assume Western portion geometry (grams of raw ingredients, standardized packaged foods). Indian home cooking revolves around composite gravies, katoris, rotis with varying flour types, and cooking oil absorption factors.
2. Aggressive Monetization: Basic utility features like barcode scanning and custom macro targets are locked behind recurring subscriptions ($80/year or ₹3,000+/year in India), layered with intrusive ad-network SDKs.
3. Siloed Tracking: Gym training (progressive overload, plate math, rest timers) and nutrition logging require maintaining two separate applications that don't share context.

How Kynetix Solves This:
- Calibrated to the Indian Food Composition Tables (ICMR-NIN IFCT 2017) with support for colloquial portion syntax ("2 roti, 1 katori dal").
- Offline-first SQLite local persistence with optional cloud sync over Supabase RLS.
- Free barcode scanning powered by Open Food Facts.
- In-app AI coach (Kyno) that analyzes both lifting logs and nutrition logs together.
- Native Android Health Connect read-only integration.
- Zero advertising, zero third-party tracking pixels, and full JSON/CSV export.

Stack: Flutter, Dart, SQLite, Supabase RLS.

Web & APK: https://dhruvgupta-24.github.io/Kynetix/
Source: https://github.com/dhruvgupta-24/Kynetix

I'd love your feedback on the architecture, offline sync design, and usability!
```

---

## 4. Play Store Closed Beta Recruitment (20-Tester Playbook)

Google Play requires 20 opted-in testers for 14 continuous days before granting production track access.

### Quick Conversion Sequence:
1. **Tester Instructions Page:** Share direct link to `https://dhruvgupta-24.github.io/Kynetix/beta/`.
2. **Two-Step Onboarding:**
   - Step 1: Join the public Google Group with your Play Store account: `https://groups.google.com/g/kynetix-testers`
   - Step 2: Accept the web invite: `https://play.google.com/apps/testing/com.kynetix.app`
3. **Tester Retention Strategy:**
   - Send weekly beta update logs highlighting tester-reported bug fixes.
   - Acknowledge tester contributions in `CONTRIBUTORS.md` and app release notes.
