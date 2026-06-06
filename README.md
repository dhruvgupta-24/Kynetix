# Kynetix - AI-First Nutrition & Fitness Coach

Kynetix is an AI-first health and training application built with Flutter for Android. It combines natural language meal logging, an AI-powered conversational nutrition coach, calorie-cycled daily targets, Health Connect synchronization, a training journal, and a native Android Home Widget.

---

## What Makes Kynetix Different?

* **Indian Food Optimization**: Natural language meal logging is optimized for Indian diets, portion sizes, and mess/hostel eating patterns.
* **Personal Nutrition Memory**: The engine learns from manual user corrections to refine future AI calorie and protein estimates for recurring meals.
* **ChatGPT Account Linking**: Seamlessly pairs with a user's personal ChatGPT Plus/Developer account to run coaching requests using their own API limits, reducing system infrastructure costs.
* **Multimodal Coaching (Vision)**: An AI nutrition coach capable of analyzing food photos, menus, and delivery app screenshots.
* **Integrated Ecosystem**: Automatically cycles daily calorie and protein targets based on active workout splits (gym days vs. rest days) and step counts.
* **Concentric Progress Widget**: Renders Google Fit-style concentric rings directly on the native Android home screen to track calories and protein in real time.

---

## Product Feature Status

To ensure transparency and prevent documentation drift, the table below maps the current status of Kynetix features:
* **Fully Implemented**: Complete loop (UI + Service + Database) and active in the user flow.
* **Partially Implemented**: Connects UI and code, but has key omissions, incomplete data flows, or known gaps.
* **Infrastructure Exists**: Backend services, models, or database tables are implemented, but are not wired into the main client app flows.
* **Planned Only**: Conceptual placeholder with no code representation.

| Feature | Status | Notes |
| :--- | :--- | :--- |
| **Natural Language Meal Logging** | **Fully Implemented** | Uses direct token parsing + Gemini REST API meal estimation, falling back to a local database. |
| **AI Nutrition Coach (Kyno Chat)** | **Fully Implemented** | Conversational chat interface supporting multi-turn stream messages, suggestion chips, and camera/gallery photos. |
| **Calorie-Cycled Targets (TDEE)** | **Fully Implemented** | Mifflin-St Jeor TDEE formula adjusting for gym day vs. rest day training splits. |
| **Health Connect Integration** | **Fully Implemented** | Deduplicates and syncs daily step counts and body weights. |
| **Workout Recovery Dialog** | **Fully Implemented** | Modal recovery prompt displayed on boot if a draft session is detected. Drafts survive indefinitely. |
| **Planned vs. Executed History** | **Fully Implemented** | Side-by-side planned vs. actual workout logs displaying skips, replacements, and additions. |
| **Partial Workout Status** | **Fully Implemented** | `WorkoutStatus.partial` is saved when ending a workout session early. |
| **RPE Toggle & Dials** | **Fully Implemented** | Settings switch that reveals RPE 6–10 selectors in the unified training console. |
| **Set Type Selector Enhancements** | **Fully Implemented** | Segmented single-row selector with `+ More` button, fade indicators, and active-chip auto-scroll. |
| **ChatGPT Account Linking Flow** | **Fully Implemented** | Device-code OAuth flow. Injects user token server-side in `ai-chat-router` on success. |
| **Home Screen Widget** | **Fully Implemented** | Native Android Widget with 2x2/4x2/4x4 layouts, concentric progress arcs, and midnight rollover. |
| **Achievement System** | **Fully Implemented** | Evaluates and displays training and habit achievements in history and insights screens. |
| **AI Coaching Insights** | **Fully Implemented** | Local deterministic coach summaries displayed on the daily logs screen. |
| **Cloud Sync** | **Partially Implemented** | Hydrates core logs, profiles, and workouts. Some analytics/cache tables are write-only and not restored. |
| **Calorie Carry-Forward** | **Infrastructure Exists** | `carry_forward_record.dart` exists, but lacks active UI settings or roll-over logic. |
| **Wearable Recovery Integration** | **Infrastructure Exists** | `SleepData` and `HrvData` models exist in `recovery_service.dart` but are not wired to sensors or UI. |

---

## Unused / Legacy / Experimental Components

The following elements exist in the repository but are not active in primary user flows. They are documented here to prevent confusion for future developers:

| Component | Category | Status | Purpose / Notes |
| :--- | :--- | :--- | :--- |
| `home_screen.dart` | UI Screen | **Unused** | Residual landing screen replaced by the active tab views in `app_shell.dart`. |
| `SleepData` & `HrvData` | Code Stubs | **Experimental** | Placeholder data structures for future wearable recovery tracking. |
| `carry_forward_record` | Code Stub | **Experimental** | Data model for weekly rolling calorie balances, not integrated with TDEE logic. |

---

## Architecture & Core Flows

```
Flutter App (kynetix_ui / Android)
    │
    ├─ Supabase Auth         (Google SSO + email/password)
    ├─ Supabase Postgres     (profiles, day_logs, user_openai_links, workouts)
    └─ Supabase Edge Functions
          │
          ├─ ai-meal-coach        ← Nutrition coach - builds full context,
          │                          fetches meals, targets, food memory,
          │                          then calls ai-chat-router
          │
          └─ ai-chat-router       ← AI provider router
                │
                ├─ PRIMARY:   OpenAI  (using user's linked ChatGPT token if connected)
                │                     Fallback: OpenAI system credentials
                │
                └─ FALLBACK:  OpenRouter
```

### AI Coaching Architecture

Coaching is separated into three clean layers:
1. **Local CoachService** (`lib/services/coach_service.dart`): Operates completely **offline** on the device. Evaluates today's meal logs against targets to print immediate, deterministic coaching blocks (e.g., flagging severe protein deficits, calculating protein requirements per remaining meal, or checking weekly calorie target adherence).
2. **AI Coach Screen** (`lib/screens/ai_coach_screen.dart`): Interactive client interface (the chat window for *Kyno*). Handles multi-turn streaming conversations, camera/gallery uploads, quick suggestion chips, and Markdown response rendering. Encodes weight trends and daily targets as context.
3. **Edge Function AI Chat** (`supabase/functions/ai-meal-coach/`): Server-side context injector. Receives the user's message, loads user profile/day logs/nutrition memory, and builds a system prompt injecting daily calorie/protein stats and overrides. Then it routes the request to the `ai-chat-router` Edge Function, which calls OpenAI (using the user's linked ChatGPT token if connected, or Kynetix's system API key) and streams responses back to the app via Server-Sent Events (SSE).

### Android Home Widget Synchronization
- **Dart SharedPreferences**: When today's meal log, user targets, or profile details change, `WidgetService` calculates today's consumed/remaining calories and protein, serializes them to a JSON string, and saves it in SharedPreferences with the key `widget_data_v1`. Flutter automatically prefixes this key with `flutter.` internally when saving to Android's SharedPreferences XML file.
- **MethodChannel Update Broadcast**: `WidgetService` fires an update call over the MethodChannel `com.kynetix.app/widget`. The native `MainActivity` intercepts it and broadcasts a refresh intent (`AppWidgetManager.ACTION_APPWIDGET_UPDATE`) containing all active widget IDs.
- **Native Render & Layouts**: `KynetixWidgetProvider.kt` intercepts the broadcast, parses the SharedPreferences JSON (reading the `flutter.widget_data_v1` key), dynamically draws concentric rings (outer orange/yellow for calories, inner green/yellow for protein) on a Bitmap via native `Canvas` and `Paint`, and updates `RemoteViews`.
- **Offline Midnight Rollover**: `KynetixWidgetProvider` automatically tracks the `last_update_date` in the SharedPreferences payload. If a new calendar day is reached, the widget provider resets consumed values to `0.0` locally and refreshes the UI without requiring a prior launch of the Flutter app.

---

## AI Routing Rules & Provider Logic

The `ai-chat-router` Edge Function applies the following rules:

| Condition | Provider | Default Configuration |
| :--- | :--- | :--- |
| **Normal message** | OpenAI (primary system or linked ChatGPT account) | Primary Text Model |
| **Message with image** | OpenAI (primary system or linked ChatGPT account) | Primary Vision Model |
| **OpenAI fails (any error)** | OpenRouter (fallback) | Fallback Text Model |
| **Both fail** | Error returned | - |

The AI Coach badge shows **⚡ OpenAI** (green) on success and **↩ OpenRouter** (purple) on fallback.

---

## Database Schema

The backend uses a Supabase PostgreSQL database organized into the following functional domains:

* **Profiles & Authentication**:
  * `profiles` - User bio-metrics (age, weight, height, TDEE goal, activity factors).
  * `user_openai_links` - Stores ChatGPT OAuth tokens and discovered capabilities.
  * `openai_device_auth_sessions` - Manages active pairing session states.
* **Nutrition & Daily Logs**:
  * `day_logs` - Stores daily meal logs (`sections_json`) and gym day overrides.
  * `user_nutrition_memory` - Custom food overrides mapped to personal entries.
  * `user_quick_adds` - Personalized quick-add food item shortcuts.
  * `user_eating_patterns` - Logs corrections and classifications of food types.
  * `user_meal_contexts` - Captures context data for meal recommendation.
* **Training & Splits**:
  * `workout_sessions` - Completed workout logs (exercises, sets, reps, skips).
  * `workout_splits` - Training split configurations (exercise schedules).
* **Insights & Achievements**:
  * `user_achievements` - Unlocked consistency, habit, and nutrition achievements.
  * `user_insights_cache` - Write-only cache backups for weekly/monthly reports.

---

## Project Structure

```
Kynetix/
├── kynetix_ui/                  # Flutter Android app
│   ├── lib/
│   │   ├── config/              # Supabase config + secrets (gitignored)
│   │   ├── models/              # Data models (NutritionResult, etc.)
│   │   ├── screens/             # UI screens (Auth, Onboarding, Dashboard, Workout, etc.)
│   │   ├── services/            # Business logic (AI clients, Health Connect, Sync, etc.)
│   │   └── main.dart
│   ├── assets/branding/         # App icons + splash assets
│   └── test/                    # Integration and unit tests
│
├── supabase/
│   └── functions/
│       ├── ai-chat-router/      # AI provider dispatcher (OpenAI → OpenRouter)
│       ├── ai-meal-coach/       # Context builder + nutrition coach
│       ├── openai-link-*/       # ChatGPT OAuth device pairing functions
│       └── .env.example         # Template for local dev secrets
│
├── docs/                        # PRD, system design, API docs
└── README.md
```

### UI Screens Modules (`lib/screens/`)
* **Authentication & Onboarding**: Handles user login, password recovery, and the interactive onboarding questionnaire.
* **Dashboard & Daily Journal**: Displays daily progress rings, targets, meal categories (Breakfast, Lunch, Dinner, Snacks), and quick additions.
* **AI Chat & Diagnostics**: Contains the conversational chat coach interface (supporting image attachments) and developer diagnostics screens.
* **Workout Setup & Session Tracking**: Coordinates split day layouts, planning targets, and the active workout console.
* **History, Insights & Profile**: Integrates completed session heatmaps, streaks, unlocked achievements, and user preferences.

### Services Modules (`lib/services/`)
* **Core Engines & Parsers**: Natural language token parsing, portion normalization, and calorie estimation.
* **AI & Messaging Clients**: Services communicating with Gemini and Supabase Edge Functions.
* **Device Integrations**: Health Connect steps/weight synchronization and native MethodChannel Android widget callbacks.
* **Data Synchronizers**: Supabase Postgres sync and local SharedPreferences persistence services.
* **Insights & Rules Engines**: Muscle recovery readiness, streak calculator, and habit evaluations.

---

## Local Development

### Prerequisites
- Flutter SDK ≥ 3.19 / Dart ≥ 3.3
- Android device or emulator (Android-only)
- Node.js ≥ 18 + Supabase CLI (`npm install supabase --save-dev`)

### Install Flutter dependencies
```bash
cd kynetix_ui
flutter pub get
```

### Copy config files
```bash
# Supabase connection (URL + anon key)
cp kynetix_ui/lib/config/supabase_secrets.example.dart kynetix_ui/lib/config/supabase_secrets.dart

# App secrets (empty shell - no keys needed here)
cp kynetix_ui/lib/config/secrets.example.dart kynetix_ui/lib/config/secrets.dart
```

### Run the app
```bash
cd kynetix_ui
flutter run
```

---

## Environment Variables & Edge Functions

The Flutter app requires **no** private AI API keys. All AI requests are proxied through Supabase Edge Functions which inject secrets server-side.

### Local Edge Functions Testing
Create `supabase/functions/.env` (already gitignored):
```env
# PRIMARY AI provider
OPENAI_API_KEY=your_openai_api_key_here

# FALLBACK AI provider
OPENROUTER_API_KEY=your_openrouter_api_key_here
```

Run functions locally:
```bash
npx supabase functions serve --env-file supabase/functions/.env
```

### Production Deployment
Set secrets:
```bash
npx supabase secrets set OPENAI_API_KEY=sk-your-key-here --project-ref YOUR_PROJECT_REF
npx supabase secrets set OPENROUTER_API_KEY=sk-or-your-key-here --project-ref YOUR_PROJECT_REF
```

Deploy Edge Functions:
```bash
npx supabase secrets set ...
npx supabase functions deploy ai-chat-router --no-verify-jwt --project-ref YOUR_PROJECT_REF
npx supabase functions deploy ai-meal-coach --no-verify-jwt --project-ref YOUR_PROJECT_REF
```

---

## Security & Secrets Warning

> [!CAUTION]
> **CRITICAL SECURITY REQUIREMENT**
>
> Never commit configuration secrets or private API credentials to the repository. Ensure the following files remain listed in your `.gitignore` and are never staged for commit:
> * `supabase_secrets.dart` (holds public-safe Supabase connection details)
> * `secrets.dart` (holds client API keys)
> * `supabase/functions/.env` (holds private OpenAI and OpenRouter keys)
> * Any files containing user OAuth access/refresh credentials or temporary nonces.

---

## Testing Infrastructure

All automated tests are located in `kynetix_ui/test/` and are organized into the following categories:

* **Integration & End-to-End Tests**:
  * Covers multi-tenant row-level security (RLS) and database isolation.
  * Validates step/weight synchronization logic with Health Connect.
  * Asserts database sync for Completed vs. Partial workout sessions.
  * Verifies AI estimation corrections and portion override workflows.
* **Unit & Behavior Tests**:
  * Asserts calculations for MSJ TDEE equations and activity multipliers.
  * Validates meal classification rules, parsing, and lexicon lookups.
  * Verifies weekly/monthly report calculations and achievement streaks.
  * Tests mock database lookup fallback behaviors when APIs are offline.

### How to Run Tests
To run all test suites:
```bash
cd kynetix_ui
flutter test
```

To run a specific test suite:
```bash
flutter test test/user_isolation_test.dart
```
