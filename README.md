# ⚡ Kynetix — AI-First Nutrition & Fitness Coach

Kynetix is a modern, premium, AI-first health and training application built with Flutter for Android. By combining natural language meal logging, an AI-powered conversational coach, calorie-cycled daily targets, native Health Connect synchronization, a detailed training journal, and a dynamic home screen widget, Kynetix acts as a seamless digital companion for physical optimization.

Designed with privacy and low operational cost in mind, Kynetix features a unique ChatGPT Account Linking flow. This allows users to pair their personal ChatGPT Plus or developer account to power their AI coaching requests, bypassing expensive server middle-men and keeping user data secure.

---

## ✨ Key Features

*   **🥗 Indian Food Optimization**: Natural language meal logging is fine-tuned to recognize traditional Indian cuisines, variable portion sizes, and typical mess/hostel eating patterns.
*   **🧠 Personal Nutrition Memory**: The local intelligence engine learns directly from your manual edits to calibrate calorie and protein values for recurring or custom meals over time.
*   **🔗 ChatGPT Account Linking**: Seamlessly pairs with a user's personal ChatGPT account via a device-code OAuth flow to execute coaching requests using their own API limits.
*   **👁️ Multimodal Coaching (Vision)**: The conversational coach (*Kyno*) can analyze food photos, restaurant menus, and delivery app screenshots to extract macros and give instant feedback.
*   **🔄 Integrated Ecosystem & Cycling**: Automatically recalculates and cycles calorie and protein targets dynamically based on gym splits (workout vs. rest days) and step counts.
*   **📱 Concentric Progress Widget**: Renders Google Fit-style concentric rings directly on the native Android home screen to track calories and protein intake in real time with offline midnight rollover.
*   **🏆 Achievements & Streaks**: Automatically tracks workout consistency, habit compliance, and nutritional milestones.

---

## 🛠️ Tech Stack

### Client (Frontend)
*   **Framework**: [Flutter](https://flutter.dev) (SDK ≥ 3.19) / [Dart](https://dart.dev) (SDK ≥ 3.3)
*   **Local Storage**: `SharedPreferences` for fast key-value caching and offline widget updates.
*   **Device Integration**: Android `Health Connect` for steps and bodyweight aggregation.
*   **UI Assets**: Custom Google Fonts (`Inter`, `Outfit`), icons (`CupertinoIcons`, `MaterialIcons`), and adaptive branding.

### Backend (Serverless & Database)
*   **Platform**: [Supabase](https://supabase.com)
*   **Database**: PostgreSQL with Row-Level Security (RLS) policies for strict tenant isolation.
*   **Functions**: Supabase Edge Functions (Deno runtime) for AI routing and OAuth flows.
*   **AI Models**: Gemini REST API (client-side natural language parsing) and OpenAI GPT-4o / OpenRouter (server-side context-aware coaching).

---

## 🏗️ Architecture & Core Flows

```
                   ┌──────────────────────────────────────────┐
                   │        Flutter App (kynetix_ui)          │
                   └──────┬────────────────────────────┬──────┘
                          │                            │
                          ▼                            ▼
              ┌──────────────────────┐      ┌──────────────────────┐
              │    Supabase Auth     │      │  Supabase Postgres   │
              │  (Google / Password) │      │  (Row-Level Security)│
              └──────────────────────┘      └──────────────────────┘
                          │                            ▲
                          ▼                            │ (Database reads/writes)
              ┌────────────────────────────────────────┴──────┐
              │           Supabase Edge Functions             │
              └───────────┬────────────────────────────┬──────┘
                          │                            │
                          ▼ (AI Coaching context)      ▼ (OAuth pairing logic)
              ┌──────────────────────┐      ┌──────────────────────┐
              │    ai-meal-coach     │      │   openai-link-flow   │
              └───────────┬──────────┘      └──────────────────────┘
                          │
                          ▼ (System prompts + logs)
              ┌──────────────────────┐
              │   ai-chat-router     │
              └───────────┬──────────┘
                          │
            ┌─────────────┴─────────────┐
            ▼ (Primary Router)          ▼ (Secondary Fallback)
  ┌──────────────────┐        ┌──────────────────┐
  │   OpenAI API     │        │  OpenRouter API  │
  │ (User or System) │        │ (Fallback Model) │
  └──────────────────┘        └──────────────────┘
```

### 1. AI Coaching Architecture
Coaching is separated into three distinct, robust layers:
*   **Local Coach Service** (`coach_service.dart`): Operates entirely **offline** on-device. Evaluates daily meal logs against targets to print immediate, deterministic coaching blocks (e.g., flagging protein deficits, calculating protein requirements per remaining meal, or checking weekly calorie target adherence).
*   **AI Coach Chat Screen** (`ai_coach_screen.dart`): Interactive client interface for *Kyno*. Handles multi-turn streaming conversations, markdown rendering, suggestion chips, and camera/gallery uploads. Encodes weight trends and daily targets as system context.
*   **Edge Function Context Injector** (`supabase/functions/ai-meal-coach/`): Receives the user's message, loads user profile metrics, day logs, and custom nutrition memory. It builds a system prompt injecting daily stats and routes it to `ai-chat-router`.

### 2. Provider Routing & Failover
The `ai-chat-router` edge function acts as an intelligent gateway:
*   **Normal Message**: Routed to OpenAI (using the user's linked ChatGPT account if connected, or Kynetix's system API key).
*   **Multimodal Message**: Routed to OpenAI Vision models.
*   **Failover**: If OpenAI fails, the router seamlessly falls back to OpenRouter to ensure continuity. The client displays a visual badge indicating the active provider (⚡ OpenAI or ↩ OpenRouter).

### 3. Android Home Widget Synchronization
*   **Dart SharedPreferences**: When today's meal log, user targets, or profile details change, `WidgetService` calculates today's consumed/remaining calories and protein, serializes them to a JSON string, and saves it in SharedPreferences with the key `widget_data_v1` (prefixed as `flutter.widget_data_v1` by Flutter).
*   **MethodChannel Update**: `WidgetService` fires an update call over the MethodChannel `com.kynetix.app/widget`. The native `MainActivity` intercepts it and broadcasts a refresh intent (`AppWidgetManager.ACTION_APPWIDGET_UPDATE`).
*   **Native Render**: `KynetixWidgetProvider.kt` intercepts the broadcast, parses the JSON payload, dynamically draws concentric progress rings (outer orange/yellow for calories, inner green/yellow for protein) on a Bitmap via native `Canvas`, and updates `RemoteViews`.
*   **Midnight Rollover**: The widget provider tracks the date of the last update. At midnight, it resets values to `0.0` locally without requiring the user to open the Flutter app.

---

## 📸 Recommended Showcase Screenshots

*To showcase Kynetix in a public context, capture and save the following screenshots in `/docs/images/` and link them here:*

*   [ ] **Dashboard**: The primary screen showing the daily progress rings, meal entries categorized by meal section (Breakfast, Lunch, Dinner, Snacks), and quick-add shortcuts.
*   [ ] **Day Detail**: The detailed timeline of a specific day's meals, calorie allocations, and manual portion correction indicators.
*   [ ] **Insights Screen**: A visual breakdown of weekly step counts, body weight trends, training frequency heatmaps, and unlocked achievements.
*   [ ] **Workout Tracking**: The active console showing current sets, reps, previous weight logs, RPE selector dials, and set-type chips.
*   [ ] **Home Screen Widget**: A screenshot of the Android home screen showcasing the 2x2 or 4x2 concentric progress widget in action.

---

## 🗄️ Database Schema

The backend uses a Supabase PostgreSQL database organized into the following functional domains:

*   **Profiles & Authentication**:
    *   `profiles` - User bio-metrics (age, weight, height, TDEE goal, activity factors).
    *   `user_openai_links` - Stores ChatGPT OAuth tokens and discovered capabilities.
    *   `openai_device_auth_sessions` - Manages active pairing session states.
*   **Nutrition & Daily Logs**:
    *   `day_logs` - Stores daily meal logs (`sections_json`) and gym day overrides.
    *   `user_nutrition_memory` - Custom food overrides mapped to personal entries.
    *   `user_quick_adds` - Personalized quick-add food item shortcuts.
    *   `user_eating_patterns` - Logs corrections and classifications of food types.
    *   `user_meal_contexts` - Captures context data for meal recommendation.
*   **Training & Splits**:
    *   `workout_sessions` - Completed workout logs (exercises, sets, reps, skips).
    *   `workout_splits` - Training split configurations (exercise schedules).
*   **Insights & Achievements**:
    *   `user_achievements` - Unlocked consistency, habit, and nutrition achievements.
    *   `user_insights_cache` - Write-only cache backups for weekly/monthly reports.

---

## 📂 Project Structure

```
Kynetix/
├── kynetix_ui/                  # Flutter Android app codebase
│   ├── lib/
│   │   ├── config/              # App themes, secrets templates, and client clients
│   │   ├── models/              # Immutable data models (DayLog, WorkoutSession, etc.)
│   │   ├── screens/             # UI views (Auth, Dashboard, AI Coach, Active Workout)
│   │   ├── services/            # Core business logic, parsers, and local-to-cloud sync
│   │   └── main.dart            # Flutter entry point
│   ├── assets/branding/         # App launcher icons and splash assets
│   ├── test/                    # Integration, unit, and layout regression test suites
│   └── pubspec.yaml             # Flutter pub dependencies and asset definitions
│
├── supabase/                    # Backend database and edge functions configuration
│   └── functions/
│       ├── ai-chat-router/      # AI API dispatcher (OpenAI → OpenRouter failover)
│       ├── ai-meal-coach/       # Context builder + nutrition coach prompt injector
│       ├── openai-link-*/       # ChatGPT OAuth pairing device flow
│       └── shared/              # Shared TypeScript utilities
│
├── docs/                        # Specifications, PRDs, and architecture documents
│   ├── Dev_Rules.md             # Developer conventions
│   ├── PROJECT_CONTEXT.md       # High-level repo summary
│   ├── system_design.md         # Database and infrastructure design
│   └── prd.md                   # Product Requirements Document
│
├── pad_assets_smartly.py        # Python script to pad branding assets for Android squircle
└── README.md                    # Public documentation (this file)
```

---

## 🚀 Setup & Local Development

### 1. Prerequisites
*   Flutter SDK (v3.19.0 or higher)
*   Dart SDK (v3.3.0 or higher)
*   Android SDK & Emulator / USB-connected Android Device
*   Node.js (v18+) & Supabase CLI (`npm install supabase --save-dev`)

### 2. Client Setup
1.  Navigate to the client directory and fetch packages:
    ```bash
    cd kynetix_ui
    flutter pub get
    ```
2.  Set up local configuration files:
    ```bash
    # Copy templates
    cp lib/config/supabase_secrets.example.dart lib/config/supabase_secrets.dart
    cp lib/config/secrets.example.dart lib/config/secrets.dart
    ```
3.  Fill in `supabase_secrets.dart` with your Supabase project URL and Anonymous API key.

### 3. Serverless Backend Setup
1.  Install Supabase CLI and start local services (optional for offline testing):
    ```bash
    npx supabase start
    ```
2.  Set up Edge Functions environment secrets. Create a `supabase/functions/.env` file:
    ```env
    OPENAI_API_KEY=your_openai_key_here
    OPENROUTER_API_KEY=your_openrouter_key_here
    ```
3.  Serve the functions locally:
    ```bash
    npx supabase functions serve --env-file supabase/functions/.env
    ```

### 4. Running the Application
Launch the Flutter application on your connected emulator or device:
```bash
cd kynetix_ui
flutter run
```

---

## 🧪 Testing

Kynetix uses a comprehensive automated testing structure spanning unit, integration, and UI layout regression tests.

### How to Run Tests
*   Run the **entire test suite**:
    ```bash
    cd kynetix_ui
    flutter test
    ```
*   Run a **specific test file** (e.g., Row-Level Security isolation test):
    ```bash
    flutter test test/user_isolation_test.dart
    ```

### Test Directory Overview (`kynetix_ui/test/`)
*   `user_isolation_test.dart`: Verifies Row-Level Security (RLS) and multi-tenant data boundaries.
*   `meal_consistency_fixes_test.dart`: Ensures manual macro corrections calibrate correctly.
*   `workout_session_state_test.dart`: Validates active workout flows and session drafts.
*   `weekly_training_insights_test.dart`: Asserts target cyclings and achievement rules.

---

## 🛡️ Security & Git Best Practices

> [!CAUTION]
> **CRITICAL SECURITY REQUIREMENT**
>
> Never commit configuration secrets or private API credentials to the repository. Ensure the following files remain in your `.gitignore` and are never staged:
> *   `kynetix_ui/lib/config/supabase_secrets.dart`
> *   `kynetix_ui/lib/config/secrets.dart`
> *   `supabase/functions/.env`
> *   Any OAuth tokens or credentials files.

---

## 🗺️ Future Roadmap

*   **⚡ Calorie Carry-Forward**: Complete the UI settings and rolling balance logic to automatically carry over leftover/excess calories across the week.
*   **⌚ Wearable Integration**: Connect the backend `SleepData` and `HrvData` models to physical wearable sensors to refine daily targets based on actual physical recovery metrics.
*   **📊 Dynamic Charting**: Integrate interactive weight trend charts and macro-nutrient breakdown graphs on the Insights page.
