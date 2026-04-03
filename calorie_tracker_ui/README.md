# Kynetix

Kynetix is an AI-powered fitness and nutrition tracking application built natively in Flutter. Designed primarily for realistic Indian diet tracking and active weight training, it prioritizes rapid logging, deterministic portions, and context-aware behavioral estimation over exact database micromanagement.

## Core Features

- **Smart Meal Estimation:** Integrates AI (OpenRouter) with an Indian-food aware deterministic pipeline to rapidly gauge calories and protein from natural language without manual search.
- **Personal Nutrition Memory Layer:** Learns frequently logged meals and applies precise, recurring rules before falling back to generalized models.
- **Coach-style Guidance:** Live, contextual feedback that adjusts to the time of day, current progress, and gym frequency.
- **Dynamic Targeting:** Engine recalculates calorie and protein baselines intelligently depending on training days vs. rest days.
- **Workout Journaling:** First-class workout tracker connected directly to the nutrition pipeline logic.

## Tech Stack

- **Framework:** Flutter / Dart
- **Storage:** Local persistence layer using core SQLite / SharedPreferences rules. Cloud-free and self-contained.
- **Intelligence:** OpenRouter API (DeepSeek backing) layered securely on the deterministic estimation service.

## Running the Project Locally

1. **Install Dependencies**
   Run the following in the project root:
   ```bash
   flutter pub get
   ```

2. **Configure Secrets**
   OpenRouter API keys are safely isolated from tracking. To run AI estimations locally:
   - Duplicate `lib/config/secrets.example.dart`.
   - Rename to `lib/config/secrets.dart`.
   - Insert your real OpenRouter token:
     ```dart
     class AppSecrets {
       static const openRouterApiKey = 'sk-or-v1-...';
     }
     ```

3. **Build & Run**
   Launch via standard execution parameters:
   ```bash
   flutter run
   ```

## Architecture Notes

Kynetix differs from standard calorie trackers via its specialized intelligence layering. It explicitly treats foods probabilistically through contextual logic (e.g. tracking "portions consumed" rather than "portions served" in typical generic food databases), saving time and preventing fake-precision reporting.
