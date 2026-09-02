# Kynetix Internship Interview Prep Crash Course

> [!NOTE]
> **Important Interview Context**
> The interviewers **do not have your source code**. They only have:
> 1. The bullet points on your resume.
> 2. What you tell them when they ask.
> 
> Therefore, focus on explaining **architectural decisions, trade-offs, and conceptual workflows** rather than specific code lines. Be prepared to lead the conversation from your resume to these high-yield talking points.

---

## 1. Resume Bullet Points (What the Interviewer Knows)

- **Implemented ChatGPT account linking** using OAuth 2.0 Device Authorization Flow and PKCE across 7 serverless Supabase edge functions, with secure server-side token exchange and refresh handling.
- **Designed a nutrition parsing system** combining rule-based estimation, user meal history, and LLM-assisted parsing, resolving an estimated 80–85% of meal estimates locally and reducing unnecessary AI calls accordingly.

---

## 2. Core Interview Questions & Answers

### Q1: Why did you choose this tech stack?
**Your Answer**:
"I chose a modern, serverless mobile stack to balance rich client-side performance, data privacy, and minimal infrastructure overhead:
*   **Frontend (Flutter & Dart)**: Flutter was chosen to build a premium, highly responsive cross-platform mobile experience. Because fitness apps depend heavily on custom visual indicators (like concentric progress rings and workout charts), Flutter’s rendering engine allowed me to build custom painted UIs with 60 FPS performance. Dart’s async-await model and stream-based architecture fit perfectly with local cache synchronization and background tasks.
*   **Database (Supabase & PostgreSQL)**: Fitness data is highly relational. A user has a profile, which has daily logs, which contain multiple meals and workouts. PostgreSQL is perfect for maintaining this relational integrity. Supabase provided the PostgreSQL backend out-of-the-box and allowed me to use **Row-Level Security (RLS)** to enforce strict data isolation between users directly at the database layer.
*   **Serverless Compute (7 Deno Edge Functions)**: Written in TypeScript, 7 Deno Edge Functions deploy globally with near-zero cold starts (<50ms). This allowed me to handle security-sensitive tasks like OAuth 2.0 Device Authorization Flow & PKCE token exchange, token refresh, and compiling system prompts without maintaining a 24/7 Node/Express server.
*   **AI Engine (Dual-LLM Approach)**: I used a hybrid dual-LLM architecture. When natural language meal parsing escalates past local rules, it uses a lightweight client-side LLM call. For coaching, I routed requests to **OpenAI's Codex backend** via our edge functions using the user's linked ChatGPT OAuth tokens to support multi-turn streaming conversations and progress-aware context injection."

### Q2: What was the biggest technical challenge?
**Your Answer**:
"The biggest challenge was building a natural language meal parser that is **actually accurate for regional cuisines—specifically Indian food**—while keeping API costs and latency near zero. 
Most fitness apps rely on US-centric databases (like USDA) which fail on regional Indian items like *'2 roti and dal'*. Furthermore, calling a large LLM on every single meal log is too slow, too expensive, and doesn't learn from the user's personal context.

To solve this, I designed a hybrid **Nutrition Parsing System** with a 5-tier resolution pipeline:
1.  **User & Personal Meal Memory**: Instant client-side lookups matching exact past meal overrides and saved user recipes.
2.  **Recurring Cache & Known Foods**: Instant matching for recurring brand/packaged items.
3.  **Local Food Library & Rule-Based Estimation**: Built-in 45+ item food database and volumetric rules for Indian food portions (e.g. mapping a 'roti' or 'katori of dal' to standardized macro profiles).
4.  **Local Confidence Gate**: Evaluates coverage and match confidence (requiring ≥90% coverage and ≥85% match confidence) to finalize estimates locally without network overhead.
5.  **LLM-Assisted Escalation**: Only triggers an AI call when local confidence fails or complex/unrecognized multi-item meals are logged.

This design resolves an estimated **80–85% of typical meal estimates locally**, drastically reducing unnecessary AI API calls, lowering latency to sub-second lookup times, and providing personalized accuracy."

### Q3: What would you improve or do differently in hindsight?
**Your Answer**:
"In hindsight, I would improve three key areas:
1.  **Semantic Food Search via Embeddings**: Currently, the Personal Meal Memory matches foods using Levenshtein distance (string similarity). If a user edits *'chapati'* and later logs *'roti'*, string similarity fails to connect them. I would integrate a lightweight, on-device vector database (like Hive or SQLite Vec) to perform semantic vector search on food descriptions offline.
2.  **Deeper Wearable Integration**: I synchronized daily steps using Health Connect to adjust calorie targets. However, incorporating HRV (Heart Rate Variability), resting heart rate, and sleep quality scores would allow the target planning engine to dynamically cycle training intensity and caloric targets based on true physiological recovery rather than just step count.
3.  **Conflict-Free Replicated Data Types (CRDTs)**: While the last-write-wins sync works, in a multi-device setup, offline edits can occasionally overwrite each other. Using CRDTs or delta-based syncing for daily meal logs would make the offline-first sync engine completely bulletproof."

### Q4: How would the system handle scaling to 1,000+ active users tomorrow?
**Your Answer**:
"The architecture is designed to scale horizontally with minimal developer costs:
*   **API Cost Control (OAuth 2.0 Device Auth & PKCE)**: AI features are expensive. To eliminate operational API costs, I built a secure account-linking system using OAuth 2.0 Device Authorization Flow and PKCE across 7 Supabase Edge Functions. Users link their personal ChatGPT accounts, allowing coaching sessions to run on their personal API limits while server-side token exchange and refresh handling protect credentials.
*   **LLM Request Caching & Local Parsing**: A surge of users logging meals would spike AI API costs and rate limits. By resolving an estimated 80–85% of meal estimates locally through the rule-based estimation engine and meal memory, the system intercepts most logs before hitting the LLM API.
*   **Database Connection Pooling**: PostgreSQL has connection limits. Supabase handles scaling via connection poolers (PgBouncer/Supavisor). I would ensure transaction-level pooling is active to handle concurrent client sync sessions.
*   **Optimizing Insights Aggregations**: The dashboard displays weekly and monthly averages. Under load, executing raw SQL `SUM` and `AVG` queries across thousands of users' histories is expensive. I would pre-compute and store these metrics in a read-optimized cache table (`user_insights_cache`) updated asynchronously once a day, reducing database read stress to $O(1)$ during dashboard loads."

---

## 3. The 60-Second Elevator Pitch

> **Interviewer**: *"Tell me about the most interesting project on your resume."*

**Your Answer**:
"I built **Kynetix**, an AI-powered fitness and nutrition app designed with a privacy-first, serverless architecture. 
The app targets two main pain points: the high server and API costs associated with AI coaching, and the inaccuracy of standard databases when logging regional cuisines, particularly Indian foods.

To address cost and privacy, I implemented ChatGPT account linking using OAuth 2.0 Device Authorization Flow and PKCE across 7 serverless Supabase Edge Functions with secure server-side token exchange and refresh handling. For logging, I designed a hybrid **Nutrition Parsing System** combining rule-based estimation, user meal history, and LLM-assisted parsing—resolving an estimated 80–85% of meal estimates locally and eliminating unnecessary AI calls. 

Lastly, to drive adherence, I integrated a custom native **Android Home Widget** that parses local data and renders progress rings offline using a native Kotlin Canvas renderer."

---

## 4. Deep Dive on Resume Bullet Points

### Bullet 1: Implemented ChatGPT Account Linking via OAuth 2.0 & PKCE (7 Edge Functions)
*   **OAuth 2.0 Device Authorization Flow & PKCE**: Users connect their ChatGPT account directly from the mobile app via a 6-digit user code prompt (`openai-link-start`). The client polls (`openai-link-poll`) until the user approves on OpenAI's authorization page. Proof Key for Code Exchange (PKCE) prevents authorization code injection attacks.
*   **7 Serverless Supabase Edge Functions**:
    1. `ai-chat-router`: Central AI provider router (routes to Codex backend `chatgpt.com/backend-api/codex/responses` using user's OAuth token, or OpenRouter fallback).
    2. `ai-meal-coach`: Context-injecting AI coach supplying daily targets, meal logs, and user profile data into system prompts.
    3. `openai-link-start`: Initiates OAuth 2.0 Device Authorization Flow with PKCE code challenge.
    4. `openai-link-poll`: Polls OpenAI token endpoint for authorization completion.
    5. `openai-link-status`: Returns connection status and discovered Codex model (`selected_model`).
    6. `openai-link-verify`: Discovers and verifies accessible ChatGPT models for the account.
    7. `openai-link-disconnect`: Revokes link and clears stored OAuth tokens from Supabase DB.
*   **Secure Server-Side Token Exchange & Refresh Handling**: Access tokens and refresh tokens are stored exclusively in Supabase PostgreSQL (`user_openai_links`) protected by RLS. The shared helper `oauth_refresh.ts` automatically detects expired tokens and performs server-side refresh before executing AI calls—preventing token exposure to the client.

### Bullet 2: Designed a Nutrition Parsing System (80–85% Local Resolution)
*   **5-Tier Hybrid Resolution Pipeline**:
    ```
    User Input ("1 bowl upma") 
      ├──> Tier 1: User & Personal Memory (Exact overrides / saved recipes)
      ├──> Tier 2: Recurring Cache & Known Foods
      ├──> Tier 3: Local Food Library & Rule-Based Heuristics (45+ items, volumetric defaults)
      ├──> Tier 4: Local Confidence Gate (Coverage ≥90%, Match ≥85% → AI BLOCKED)
      └──> Tier 5: LLM-Assisted Parsing Escalation (Only for complex/unrecognized inputs)
    ```
*   **80–85% Local Resolution Rate**: By prioritizing local memory lookups and built-in food heuristics, 80–85% of typical user inputs are resolved locally without making an LLM API call, keeping latency sub-second and API costs minimal.
*   **Meal Memory Calibration**: When a user inputs natural language (e.g., *"2 scrambled eggs and toast"*), the engine checks local memory first. If the user previously corrected the protein value from 12g to 18g, the edit is stored in [eating_pattern_service.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/eating_pattern_service.dart). Subsequent logs apply a computed scalar multiplier ($1.5x$), calibrating the parser to the user's habits over time.
*   **Indian Food Heuristics**: Indian cuisine is hard to estimate because dishes like 'dal' range from watery to dense. The engine uses heuristics to classify inputs (e.g., 'katori' or 'bowl' to standard volumetric estimates) and cross-references them with regional macro profiles.

---

## 5. System Architecture & Component Communication

```
┌────────────────────────────────────────────────────────┐
│               Flutter Client Application               │
│                                                        │
│  [Local UI] ──> [Target Engine] ──> [SQLite Cache]     │
└──────┬───────────────────┬─────────────────────┬───────┘
       │ (MethodChannel)   │ (HTTPS Sync)        │ (SSE / Chat)
       ▼                   ▼                     ▼
┌──────────────┐   ┌───────────────┐     ┌──────────────────────┐
│Android Widget│   │ Supabase DB   │     │ 7 Edge Functions     │
│ (Kotlin)     │   │ (Postgres RLS)│     │ (Deno / TypeScript)  │
└──────────────┘   └───────────────┘     └──────────┬───────────┘
                                                    │
                                                    ▼
                                         ┌──────────────────────┐
                                         │ ChatGPT / Codex API  │
                                         │ (OAuth 2.0 + PKCE)   │
                                         └──────────────────────┘
```

---

## 6. Follow-Up "Survival" Questions (Edge Cases)

#### 1. "How do you guarantee database privacy?"
*   **Answer**: "We enforce Row-Level Security (RLS) on Supabase PostgreSQL. Every database table has an isolation policy (e.g., `user_id = auth.uid()`). When the Flutter client connects, it passes the user's JWT. PostgreSQL intercepts the query and automatically appends the user filter to the SQL execution plan, making it impossible for one user's session to read or modify another user's rows."

#### 2. "How does the home screen widget update offline?"
*   **Answer**: "Because Flutter cannot natively draw widgets, I used a hybrid caching approach. When targets change, Flutter serializes progress metrics to a shared `SharedPreferences` file and triggers a MethodChannel update. On the Android side, a native Kotlin widget provider ([KynetixWidgetProvider.kt](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/android/app/src/main/kotlin/com/kynetix/app/KynetixWidgetProvider.kt)) intercepts the broadcast, parses the JSON from the shared cache, and draws concentric rings onto a bitmap using the native Android Canvas API. At midnight, the widget provider resets itself to zero completely offline."

#### 3. "How does the local-to-cloud sync handle connection drops?"
*   **Answer**: "We use an offline-first repository pattern. All user inputs (meals, workouts) are written immediately to a local SQLite database with a `synced` flag set to `false`. A background sync service monitors network changes. When online, it fetches unsynced rows, pushes them to Supabase, and updates their local status. Conflict resolution uses a *last-write-wins* mechanism based on UTC timestamps."

#### 4. "How did you manage prompt token costs for the AI coach?"
*   **Answer**: "Sending a user's entire historical conversation with every message would blow up token usage and costs. To mitigate this, we maintain chat history locally and only package the **last 10 messages** as conversational context. We pair this with today's raw numbers (target vs consumed macros), keeping the prompt payload minimal and predictable."

#### 5. "Why use Gemini for meal parsing but OpenAI for coaching?"
*   **Answer**: "Gemini provides a fast, direct SDK for simple extraction tasks when meal parsing escalates past the local estimation rules. The coaching workflow, however, requires retrieving database context, enforcing system prompts, and authenticating via linked ChatGPT OAuth tokens across our 7 serverless edge functions."

---

## 7. Key Modules Reference (For Quick Review)

*   **[nutrition_pipeline.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/nutrition_pipeline.dart)**: Core 5-tier nutrition parsing pipeline evaluating local memory, rule-based heuristics, confidence gates, and LLM escalation.
*   **[mock_estimation_service.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/mock_estimation_service.dart)**: Local food library database (45+ entries) and token coverage/confidence analysis.
*   **[supabase/functions/ai-chat-router/index.ts](file:///c:/Users/Dhruv/Desktop/Kynetix/supabase/functions/ai-chat-router/index.ts)**: Edge function routing requests to Codex backend via user OAuth token or OpenRouter.
*   **[supabase/functions/shared/oauth_refresh.ts](file:///c:/Users/Dhruv/Desktop/Kynetix/supabase/functions/shared/oauth_refresh.ts)**: Handles server-side OAuth token refresh logic.
*   **[nutrition_target_engine.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/nutrition_target_engine.dart)**: Centralizes math for BMR, calorie cycling, and dynamic step adjustments.
*   **[widget_service.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/widget_service.dart)**: Handles MethodChannel communication and serializing widget payloads.
*   **[KynetixWidgetProvider.kt](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/android/app/src/main/kotlin/com/kynetix/app/KynetixWidgetProvider.kt)**: Native Kotlin widget provider that draws concentric rings on the Android Canvas.
*   **[ai_coach_service.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/ai_coach_service.dart)**: Manages stream buffers and SSE connections for the conversational interface.
*   **[health_service.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/health_service.dart)**: Integrates with Android Health Connect to read daily steps.
*   **[eating_pattern_service.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/lib/services/eating_pattern_service.dart)**: Manages custom food calibration data and applies scalars.
*   **[user_isolation_test.dart](file:///c:/Users/Dhruv/Desktop/Kynetix/kynetix_ui/test/user_isolation_test.dart)**: Confirms PostgreSQL tenant separation via simulated unauthorized sessions.

