# System Design

## Overview
This app uses a **hybrid nutrition intelligence architecture**.

It is NOT:
- pure AI
- pure parser
- pure food database

It combines:
1. deterministic normalization
2. user memory / recurring defaults
3. heuristic nutrition rules
4. AI estimation
5. post-AI guardrails
6. persistence

This architecture is designed to maximize:
- realism
- speed
- trust
- extensibility

---

# High-Level Architecture

## Core Systems
- Onboarding / Profile System
- Persistence Layer
- Daily Log System
- Target Engine
- Meal Estimation Engine
- Meal Memory System
- Activity / Health Integration
- Coach Insight Foundation

---

# 1. Onboarding / Profile System

## Purpose
Capture enough user information to support:
- calorie target calculation
- protein target calculation
- personalization

## Core Inputs
- name
- age
- gender
- height
- weight
- workout frequency
- goal

## Optional Inputs
- rough body-fat category
- goal speed

## Design Rule
Only collect inputs users can realistically know.

Do not depend on advanced metrics for core app usefulness.

---

# 2. Persistence Layer

## Purpose
Persist app state across restarts.

## Must Persist
- onboarding completion
- user profile
- day logs
- meal entries
- gym-day flags
- settings
- user memory / recurring defaults

## Design Rule
App state must survive cold starts.
Onboarding should not reappear after setup unless explicitly reset.

## Recommended Shape
- lightweight local persistence
- JSON serialization for models
- one clear persistence service

---

# 3. Daily Log System

## Purpose
Represent user nutrition data per calendar day.

## Core Models
- DayLog
- MealEntry
- MealSection
- GymDayStatus

## DayLog should support
- date
- meals by section (breakfast/lunch/dinner/snacks)
- day totals
- gym/rest day state
- optional notes / coach flags later

## Design Rule
Day-level data should be the single source of truth for daily nutrition history.

---

# 4. Target Engine

## Purpose
Generate realistic calorie and protein targets.

This engine should be the single source of truth for:
- dashboard targets
- day-detail targets
- progress header targets
- future coach logic

## Inputs
- user profile
- goal
- workout frequency
- optional gym-day flag
- bounded activity data (Health Connect)
- optional future bodyweight trend data

## Outputs
- maintenance calories
- goal calories
- protein target
- training-day target
- rest-day target
- daily selected target

## Target Design Rules

### Maintenance
Should be based on:
- BMR (e.g. Mifflin-St Jeor)
- conservative activity multiplier
- bounded activity adjustment

Health Connect should only adjust maintenance moderately.

### Goal Logic
Should support:
- fat loss
- maintenance
- muscle gain
- body recomposition

### Protein Logic
Should scale from:
- bodyweight
- goal
- training context

Protein should be realistic and adherence-friendly.

### Important
Targets must not be recalculated separately in different screens.

One target engine → one target model → reused everywhere.

---

# 5. Activity / Health Integration

## Purpose
Use real activity data to modestly improve targets.

## Current Integration
- Health Connect step history
- daily step counts
- recent step trends

## Design Rule
Activity data should improve target realism, but should NOT cause noisy or chaotic target swings.

## Recommended Behavior
- use baseline profile logic first
- apply bounded activity adjustment
- smooth with recent averages if useful

---

# 6. Meal Estimation Engine

## Purpose
Estimate calories and protein realistically from natural language input.

This is the core product intelligence layer.

## Estimation Pipeline

### Layer 1 — Input Normalization
Normalize meal text into structured clues:
- food names
- quantities
- units
- meal context
- modifiers

Examples:
- `2 roti`
- `400 ml milk`
- `thoda paneer`
- `fried`
- `dry`
- `with gravy`
- `restaurant`
- `mess`

---

### Layer 2 — User Memory Lookup
Check for:
- exact saved foods / known brand macros
- recurring meal patterns
- user-specific serving defaults

Examples:
- tofu brand macros
- whey brand macros
- bread label
- peanut butter label
- milk defaults
- recurring rice/roti defaults

---

### Layer 3 — Heuristic Rules
Apply deterministic food and portion logic.

This is important for:
- Indian food realism
- anti-undercounting
- structured consistency

#### Example heuristic categories
- paneer logic
- roti logic
- rice ladle logic
- dal/sabzi accompaniment logic
- restaurant food uplift
- calorie-dense food guardrails

---

### Layer 4 — AI Estimation
Use OpenRouter AI for:
- meal interpretation
- item breakdown
- contextual estimation
- uncertainty reasoning

AI should receive:
- normalized meal text
- relevant user profile context
- relevant portion/memory context
- estimation instructions

AI should NOT be blindly trusted.

---

### Layer 5 — Post-AI Guardrails
Apply post-estimation sanity checks to prevent unrealistic outputs.

Examples:
- known milk quantity too low
- paneer-heavy meal too low
- known labeled food overridden incorrectly
- restaurant meal underestimated

This layer exists to prevent AI from sounding smart while being wrong.

---

# 7. Indian Food Context Rules

These rules are especially important.

## Mess / Hostel / Home Context
Default assumptions should reflect:
- practical Indian serving sizes
- mess/home food portions
- not oversized restaurant assumptions by default

## Milk
- 1 glass milk = 200 ml

## Rice
- 1 ladle rice = moderate cooked serving
- vague rice should not be overestimated by default

## Sabzi / Dal
Sabzi/dal are often contextual accompaniments to carbs, not always full standalone bowls.

## Paneer Exception
Paneer should generally be estimated as fully consumed if taken.

## “Thoda” Rule
Words like:
- thoda
- little
- some
- small

should reduce quantity meaningfully but realistically.

## Restaurant Rule
Restaurant food should generally be estimated more aggressively than mess/home food.

---

# 8. Meal Memory System

## Purpose
Improve estimation over time for recurring users.

## Memory Types
- exact known foods
- recurring meal patterns
- user-specific serving defaults
- labeled product macros

## Priority Order
1. exact known user-specific food / brand
2. recurring user memory
3. deterministic heuristics
4. AI estimation
5. post-AI correction

## Design Rule
Memory should improve personalization without causing dangerous over-merging or bad assumptions.

Different quantities and clearly different meals should remain distinct.

---

# 9. Result / Output Model

## Purpose
Return meal estimates in a useful and trustworthy format.

## Recommended Output Fields
- canonical meal name
- calories
- protein
- optional low/high range
- confidence
- item breakdown
- assumptions
- warnings
- source type (memory / AI / fallback)

## UX Rule
If uncertainty is low:
- show a single estimate

If uncertainty is medium/high:
- show a real range

Do not show fake ranges.

---

# 10. Coach Insight Foundation

## Purpose
Support lightweight future nutrition coaching.

## Example Future Outputs
- “protein is the real issue today”
- “this meal is calorie-dense despite small quantity”
- “skip rice, eat tofu”
- “don’t panic over one high meal”

## Design Rule
This should be a lightweight insight layer, not a bloated chatbot.

---

# 11. High-Level Data Flow

## Meal Logging Flow
Input
→ Normalize
→ Memory Lookup
→ Heuristics
→ AI Estimate
→ Guardrails
→ Result
→ Save to Day Log
→ Persist
→ Update Daily Totals

## Daily Target Flow
Profile
→ Target Engine
→ Activity Adjustment
→ Goal Logic
→ Day Context (gym/rest)
→ Daily Targets
→ Dashboard / Day Screen

---

# 12. Key Design Principles

- single source of truth for targets
- single estimation pipeline for add/edit meal
- AI should assist, not dominate
- realism over fake precision
- trust over pretty numbers
- persistence must be reliable
- personalization should improve a strong base system