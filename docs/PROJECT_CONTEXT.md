# Project Context

## What this project is
This is a Flutter mobile app:
AI-first calorie and nutrition tracker.

It is designed for:
- real daily use
- Indian food
- hostel/mess food
- home food
- outside food

This is NOT a demo or hackathon project.

---

## Current Status

The app already has:

- onboarding flow (profile setup)
- dashboard with calories/protein targets
- day detail screen with meal logging
- natural language meal input
- AI estimation via OpenRouter (working)
- fallback estimator
- meal memory/cache system
- Health Connect integration (steps working)

However, the system still needs:
- accurate target engine
- improved estimation logic
- better persistence
- better consistency across screens

---

## Core Product Philosophy

### 1. Realism > fake precision
Estimates must be believable, not artificially low.

### 2. Fast logging > perfect logging
User should log meals quickly using natural language.

### 3. Trust > pretty UI
If numbers are wrong, the product fails.

### 4. Personalization improves a strong base
The system must:
- work for new users
- improve over time with memory

NOT:
- be hardcoded for one user

---

## Target Behavior

The app should feel like:
- MyFitnessPal + AI
- but smarter for Indian food
- smarter for portion estimation
- smarter for real-world eating patterns

---

## What the app must do well

- estimate Indian meals realistically
- avoid undercounting calorie-dense foods
- give believable calorie/protein targets
- handle vague inputs like:
  - "2 roti dal"
  - "paneer"
  - "rice thoda"
- adapt to gym vs rest days
- persist data properly

---

## What the app must NOT do

- no fake precision
- no random inflated/deflated calories
- no duplicate logic paths
- no UI-only fixes without logic fixes
- no hardcoding values for specific users

---

## Important Implementation Rules

- single source of truth for targets
- single estimation pipeline
- AI must not override known user data
- guardrails must prevent obvious undercounting
- persistence must be reliable

---

## AI Development Rules (CRITICAL)

When modifying this project:

- always inspect existing code before adding new logic
- do NOT create duplicate services or pipelines
- do NOT leave old logic active
- refactor instead of patching blindly
- keep architecture clean and extensible

---

## Long-Term Direction

Future improvements may include:
- coach insights ("eat more protein", etc.)
- workout-aware nutrition (GRYND integration)
- adaptive targets based on progress

---

## Summary

This is a serious product build.

Every change should improve:
- accuracy
- trust
- usability

Not just “make it work”.