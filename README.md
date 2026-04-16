# Kynetix - AI-First Nutrition & Fitness Coach

Kynetix is an Android app built with Flutter for Indian users who want realistic, low-friction calorie and protein tracking. It combines AI-powered meal estimation with a conversational nutrition coach, workout tracking, and Health Connect integration.

---

## What Kynetix Does

- **Natural language meal logging** - type "2 roti dal" and get a realistic calorie + protein estimate tuned for Indian food and mess/hostel eating
- **AI Nutrition Coach** - conversational chat powered by OpenAI, aware of your meals, targets, and eating history
- **Calorie-cycled daily targets** - Mifflin-St Jeor TDEE with gym-day (+120 kcal) and rest-day (−120 kcal) splits
- **Health Connect integration** - reads step history to gently influence maintenance estimate
- **Workout tracker** - logs workouts and flags gym vs rest days
- **Personalized food memory** - remembers your recurring meals and uses them in future estimates

---

## Architecture

```
Flutter App (kynetix_ui / Android)
    │
    ├─ Supabase Auth         (Google SSO + email/password)
    ├─ Supabase Postgres     (profiles, day_logs, user_nutrition_memory, workouts)
    └─ Supabase Edge Functions
          │
          ├─ ai-meal-coach        ← Nutrition coach - builds full context,
          │                          fetches meals, targets, food memory,
          │                          then calls ai-chat-router
          │
          └─ ai-chat-router       ← AI provider router
                │
                ├─ PRIMARY:   OpenAI  gpt-4o-mini (text)
                │                     gpt-4o      (vision / image input)
                └─ FALLBACK:  OpenRouter  deepseek/deepseek-chat-v3-0324
```

**Security principle:** All private AI API keys live exclusively in Supabase Edge Function secrets. The Flutter frontend contains zero private keys.

---

## Key Screens

| Screen | Purpose |
|---|---|
| `auth_screen.dart` | Google Sign-In + email/password auth |
| `onboarding_screen.dart` | Profile setup (age, weight, goal, workout frequency) |
| `home_screen.dart` | Dashboard - daily progress rings, calorie/protein status |
| `dashboard_screen.dart` | Full day view - meals, sections, targets |
| `day_detail_screen.dart` | Per-day meal log and editing |
| `add_meal_screen.dart` | Natural language meal entry + AI estimation |
| `ai_coach_screen.dart` | Conversational AI nutrition coach (with image support) |
| `workout_screen.dart` | Workout log and gym/rest day tracking |
| `workout_session_screen.dart` | Active workout session tracking |
| `workout_setup_screen.dart` | Workout plan configuration |
| `profile_screen.dart` | Settings, profile edit, AI engine info |

---

## Local Development

### Prerequisites

- Flutter SDK ≥ 3.19 / Dart ≥ 3.3
- Android device or emulator (Android-only; iOS not configured)
- Node.js ≥ 18 + Supabase CLI:
  ```bash
  npm install supabase --save-dev
  ```

### Install Flutter dependencies

```bash
cd kynetix_ui
flutter pub get
```

### Copy config files

```bash
# Supabase connection (URL + anon key - safe to share but gitignored)
cp kynetix_ui/lib/config/supabase_secrets.example.dart kynetix_ui/lib/config/supabase_secrets.dart
# Fill in your project URL and anon key

# App secrets (empty shell - no keys needed here)
cp kynetix_ui/lib/config/secrets.example.dart kynetix_ui/lib/config/secrets.dart
```

### Run the app

```bash
cd kynetix_ui
flutter run -d <device_id>
```

---

## Environment Variables

### Flutter - no private AI keys needed ✅

The Flutter app requires **no** OpenAI or OpenRouter API keys. All AI requests are proxied through Supabase Edge Functions which inject secrets server-side.

`supabase_secrets.dart` holds only the Supabase project URL and anon key - both are public-safe but gitignored by convention.

### Edge Functions - local development

Create this file (already gitignored):

```
supabase/functions/.env
```

Contents:

```env
# PRIMARY AI provider
# Get from: https://platform.openai.com/api-keys
OPENAI_API_KEY=your_openai_api_key_here

# FALLBACK AI provider
# Get from: https://openrouter.ai/keys
OPENROUTER_API_KEY=your_openrouter_api_key_here
```

Run functions locally:

```bash
npx supabase functions serve --env-file supabase/functions/.env
```

---

## Production Setup

### 1. Set Supabase secrets

```bash
npx supabase secrets set OPENAI_API_KEY=sk-your-key-here --project-ref YOUR_PROJECT_REF
npx supabase secrets set OPENROUTER_API_KEY=sk-or-your-key-here --project-ref YOUR_PROJECT_REF
```

Verify:

```bash
npx supabase secrets list --project-ref YOUR_PROJECT_REF
```

### 2. Deploy Edge Functions

```bash
npx supabase functions deploy ai-chat-router --no-verify-jwt --project-ref YOUR_PROJECT_REF
npx supabase functions deploy ai-meal-coach --no-verify-jwt --project-ref YOUR_PROJECT_REF
```

---

## AI Provider Routing

| Condition | Provider | Model |
|---|---|---|
| Normal message | OpenAI (primary) | `gpt-4o-mini` |
| Message with image | OpenAI (primary) | `gpt-4o` (vision) |
| OpenAI fails (any error) | OpenRouter (fallback) | `deepseek/deepseek-chat-v3-0324` |
| Both fail | Error returned | - |

The AI Coach badge shows **⚡ OpenAI** (green) on success, **↩ OpenRouter** (purple) on fallback.

---

## Database Tables

| Table | Purpose |
|---|---|
| `profiles` | User profile (weight, height, age, goal, workout frequency) |
| `day_logs` | Daily meal log - `sections_json` stores meals by section |
| `user_nutrition_memory` | Learned food values from past logs |
| `workouts` | Workout sessions |

---

## Security

| Item | Status |
|---|---|
| `OPENAI_API_KEY` | Supabase secrets only - never in Flutter |
| `OPENROUTER_API_KEY` | Supabase secrets only - never in Flutter |
| `supabase_secrets.dart` | Gitignored (Supabase URL + anon key) |
| `secrets.dart` | Gitignored (empty - no keys) |
| `supabase/functions/.env` | Gitignored |
| Flutter → `api.openai.com` | ❌ Never - all calls go through Edge Functions |
| Flutter → `openrouter.ai` | ❌ Never - all calls go through Edge Functions |

---

## Project Structure

```
Kynetix/
├── kynetix_ui/                  # Flutter Android app
│   ├── lib/
│   │   ├── config/              # Supabase config + secrets (gitignored)
│   │   ├── models/              # Data models (NutritionResult, etc.)
│   │   ├── screens/             # 14 UI screens
│   │   ├── services/            # Business logic, AI client, Health Connect
│   │   └── main.dart
│   └── assets/branding/         # App icons + splash
│
├── supabase/
│   └── functions/
│       ├── ai-chat-router/      # AI provider dispatcher (OpenAI → OpenRouter)
│       ├── ai-meal-coach/       # Context builder + nutrition coach
│       └── .env.example         # Template for local dev secrets
│
├── docs/                        # PRD, system design, API docs
└── README.md
```

---

## Debugging AI Issues

Check logs in the Supabase dashboard: **Dashboard → Functions → ai-meal-coach / ai-chat-router → Logs**

### Expected log flow (success)

```
[ai-meal-coach] user=<uuid> date=20260416 hasImage=false
[AI ROUTER] user=<uuid> msgs=2 openai_key=sk-...xxxx
[AI ROUTER] provider=OPENAI success
```

### Common errors

| Log / Error | Meaning | Fix |
|---|---|---|
| `Auth failed: Unsupported JWT algorithm ES256` | supabase-js version mismatch | Redeploy functions (already fixed in v2+) |
| `OPENAI_API_KEY not set` | Secret missing in Supabase | Run `npx supabase secrets set OPENAI_API_KEY=...` |
| `HTTP 401` from OpenAI | API key invalid or expired | Rotate key at platform.openai.com |
| `OpenAI failed → fallback to OpenRouter` | OpenAI quota/error, using fallback | Normal - check if OpenAI key needs top-up |
| `all providers failed` | Both OpenAI and OpenRouter failed | Check both API keys |
