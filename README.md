# Kynetix — AI Nutrition Coach

Kynetix is a Flutter-based personal nutrition coaching app for Indian users, featuring AI-powered meal estimation, calorie tracking, and a conversational AI coach backed by OpenAI.

---

## Architecture

```
Flutter App (kynetix_ui)
    │
    ├─ Supabase Auth (user identity)
    ├─ Supabase Postgres (day logs, profiles, nutrition memory)
    └─ Supabase Edge Functions
          │
          ├─ ai-meal-coach        ← context builder (fetches user data, builds system prompt)
          └─ ai-chat-router       ← AI provider router
                │
                ├─ OpenAI (PRIMARY)    gpt-4o-mini / gpt-4o for vision
                └─ OpenRouter (FALLBACK)  deepseek/deepseek-chat-v3-0324
```

**Key principle:** All private API keys live exclusively in Supabase Edge Function secrets. The Flutter frontend never contains or transmits provider API keys.

---

## Local Development

### Prerequisites

- Flutter SDK ≥ 3.19
- Dart SDK ≥ 3.3
- Node.js ≥ 18 (for Supabase CLI)
- Supabase CLI: `npm install supabase --save-dev`

### Install Flutter dependencies

```bash
cd kynetix_ui
flutter pub get
```

### Run the Flutter app

```bash
flutter run -d <device_id>
```

---

## Environment Variables

### Flutter — no secrets needed ✅

The Flutter app requires **zero private API keys**. All AI requests are routed through Supabase Edge Functions, which inject secrets server-side.

The only config Flutter needs is `lib/config/supabase_secrets.dart` (Supabase URL + anon key — both are public-safe):

```dart
class SupabaseSecrets {
  static const url      = 'https://your-project.supabase.co';
  static const anonKey  = 'eyJ...your anon key...';
}
```

### Edge Functions — local development

Create this file (it is gitignored):

```
supabase/functions/.env
```

Contents:

```env
# PRIMARY AI provider — standard OpenAI API key
# Get from: https://platform.openai.com/api-keys
OPENAI_API_KEY=your_openai_api_key_here

# FALLBACK AI provider — OpenRouter key
# Get from: https://openrouter.ai/keys
OPENROUTER_API_KEY=your_openrouter_api_key_here
```

Then run functions locally:

```bash
npx supabase functions serve --env-file supabase/functions/.env
```

---

## Production Setup

### Set Supabase secrets (production)

```bash
npx supabase secrets set OPENAI_API_KEY=sk-your-key-here --project-ref YOUR_PROJECT_REF
npx supabase secrets set OPENROUTER_API_KEY=sk-or-your-key-here --project-ref YOUR_PROJECT_REF
```

> ⚠️ **Never** put these keys in Flutter source code, `.env` committed to git, or any client-side file.

### Verify secrets are set

```bash
npx supabase secrets list --project-ref YOUR_PROJECT_REF
```

---

## Deploy Edge Functions

```bash
# Deploy AI router (primary AI dispatcher)
npx supabase functions deploy ai-chat-router --no-verify-jwt --project-ref YOUR_PROJECT_REF

# Deploy meal coach (context builder + router caller)
npx supabase functions deploy ai-meal-coach --no-verify-jwt --project-ref YOUR_PROJECT_REF
```

---

## AI Provider Routing

| Scenario | Provider used |
|---|---|
| Normal request | OpenAI `gpt-4o-mini` |
| Request with image | OpenAI `gpt-4o` (vision) |
| OpenAI fails (any error) | OpenRouter `deepseek-chat-v3-0324` |
| Both fail | Error returned to client |

The badge in the AI Coach screen shows **⚡ OpenAI** (green) for primary success, or **↩ OpenRouter** (purple) for fallback.

---

## Security

- ✅ `OPENAI_API_KEY` — Supabase secrets only, never in Flutter
- ✅ `OPENROUTER_API_KEY` — Supabase secrets only, never in Flutter
- ✅ `supabase_secrets.dart` — gitignored (Supabase URL + anon key are public-safe but kept local)
- ✅ `secrets.dart` — gitignored (empty; no keys)
- ✅ `.env` files — gitignored at root and in `supabase/functions/`
- ✅ No direct calls from Flutter to `api.openai.com` or `openrouter.ai`

---

## Debugging

### AI requests not working?

Check Supabase Dashboard:
**Dashboard → Functions → ai-chat-router → Logs**

Successful flow:
```
[AI ROUTER] provider=OPENAI success
```

Fallback:
```
[AI ROUTER] OpenAI failed → fallback to OpenRouter
[AI ROUTER] provider=OPENROUTER success
```

Both failed:
```
[AI ROUTER] all providers failed
```

### Common issues

| Error | Fix |
|---|---|
| `OPENAI_API_KEY not set` | Run `npx supabase secrets set OPENAI_API_KEY=...` |
| `401 Unauthorized` | API key is invalid or expired — rotate at platform.openai.com |
| `429 Rate limit` | OpenAI quota hit — OpenRouter fallback will handle it |
| No AI response in app | Check `ai-meal-coach` logs — may be a profile/auth issue |

---

## Project Structure

```
Kynetix/
├── kynetix_ui/                  # Flutter app
│   ├── lib/
│   │   ├── config/              # Supabase config (gitignored secrets)
│   │   ├── models/              # Data models
│   │   ├── screens/             # UI screens
│   │   ├── services/            # Business logic & API clients
│   │   └── main.dart
│   └── assets/
│       └── branding/            # App icons & splash assets
│
├── supabase/
│   └── functions/
│       ├── ai-chat-router/      # AI provider dispatcher
│       │   └── index.ts
│       ├── ai-meal-coach/       # Context builder + coach
│       │   └── index.ts
│       └── .env.example         # Template for local secrets
│
├── engine/                      # Nutrition estimation engine
├── parser/                      # Food parsing logic
├── processor/                   # Data processing utilities
└── README.md
```
