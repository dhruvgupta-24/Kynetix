# Product Requirements Document (PRD)

## Product Name
AI-first Nutrition & Calorie Tracker

## Product Vision
Build a calorie and protein tracking app that feels like **MyFitnessPal + AI**, but actually works well for:

- Indian food
- hostel/mess food
- home food
- outside/restaurant food
- casual natural language meal logging

The app should behave more like a **realistic human nutrition coach** than a generic food database calculator.

The goal is not fake precision.

The goal is:
- fast logging
- realistic estimates
- practical fat-loss / recomposition usefulness
- daily trust

---

## Product Goals

### Primary Goals
- Make meal logging fast and low-friction
- Estimate calories and protein realistically from natural language
- Work much better for Indian meals than generic apps
- Personalize estimates over time using user memory and recurring foods
- Provide believable daily calorie/protein targets
- Support real daily use, not demo use

### Secondary Goals
- Use Health Connect activity data to improve targets
- Adapt targets based on gym day vs rest day
- Support future coach-like nudges and workout-aware logic

---

## Core Product Principles

### 1. Realism over fake precision
The app should prefer:
- believable estimates
- practical ranges
- confidence-aware outputs

It should avoid:
- pretending certainty where there is uncertainty
- obviously optimistic undercounting

### 2. Fast logging over tedious logging
The app should not require:
- grams for every meal
- barcode scanning for every item
- perfect structured input

Natural logging like this should work well:
- `2 roti dal`
- `3 egg whites with 400 ml milk`
- `2 ladle rice paneer`
- `bread peanut butter`
- `outside burger fries`

### 3. Personalization should improve a strong base engine
The app must work for new users too.

Architecture should be:
1. strong generalized nutrition engine for realistic Indian users
2. personalization layer on top

The app must not be hardcoded around one user only.

### 4. Fat-loss-safe estimation
When uncertain, the app should lean toward:
- realistic
- slightly conservative
- anti-undercounting

This is especially important for:
- paneer
- oily gravies
- restaurant food
- biryani
- snacks
- calorie-dense foods

---

## Target Users

### Primary User Type
Indian users who want practical calorie/protein tracking without weighing every meal.

Examples:
- hostel / college students
- mess food eaters
- home-cooked Indian meal eaters
- gym users trying to lose fat / maintain / recomp
- users who eat a mix of Indian meals and outside food

### User Profiles Supported
The app should work for users with different:
- age
- sex
- weight
- height
- goals
- activity levels
- training frequency

---

## Core User Problems

Existing apps fail because they:
- assume Western food patterns
- handle Indian meals badly
- undercount vague meals
- overcomplicate logging
- give untrustworthy calorie targets
- don’t understand context like roti, ladle, thali, paneer, dal, etc.

This app exists to solve those problems.

---

## MVP Scope (Current Product Scope)

### 1. Onboarding / User Profile
Collect only useful, realistic user inputs:
- name
- age
- gender
- height
- weight
- workout frequency
- goal

Optional additions if useful:
- rough body-fat category
- goal speed (slow / moderate / aggressive)

Do NOT require advanced or unrealistic inputs.

---

### 2. Dashboard / Home Screen
The dashboard should show:
- selected date / calendar
- calorie progress
- protein progress
- daily calorie target
- daily protein target
- maintenance estimate
- streak (real, not fake)
- quick add meal entry
- profile access

Targets should feel coherent and trustworthy.

---

### 3. Day Detail Screen
The day detail screen should support:
- viewing meals for a specific day
- breakfast / lunch / dinner / snacks sections
- adding meals to that day
- gym day / rest day marking
- showing that day’s calorie and protein targets

Gym-day selection should actually affect that day’s targets.

---

### 4. Add Meal Flow
Users should be able to:
- enter meals in natural language
- get calorie/protein estimation
- see result preview
- save meal to daily log

The flow should be:
- fast
- clean
- confidence-aware
- low friction

---

### 5. Meal Editing / Correction
Users should be able to:
- tap a logged meal
- edit meal text / quantity / assumptions
- recalculate estimate
- save corrected result

This is important for:
- trust
- correction
- future personalization

---

### 6. Estimation Engine
The estimation engine should:
- handle natural language Indian meal input
- use user memory where available
- use AI reasoning where helpful
- apply guardrails to prevent obvious undercounting
- return realistic estimates

Outputs should support:
- calories
- protein
- confidence
- optional low/high range
- item breakdown
- assumptions / warnings where useful

---

### 7. Daily Targets Engine
The app should calculate:
- maintenance calories
- goal calories
- protein targets
- gym-day vs rest-day variation

This should be based on:
- user profile
- goal
- training frequency
- bounded Health Connect activity influence

Targets should feel:
- realistic
- sustainable
- useful for actual body composition goals

---

### 8. Activity / Health Integration
The app should support:
- Health Connect integration
- reading step history
- using recent step trends to modestly influence maintenance/targets

Important:
Activity data should improve targets, not make them unstable.

Health Connect should NOT dominate TDEE.

---

### 9. Persistence
The app must persist:
- onboarding completion
- user profile
- day logs
- meals
- settings
- memory/defaults

The app must not reset on restart or ask for onboarding again unnecessarily.

---

## Non-Goals (Current)
Not priorities right now:
- social features
- community challenges
- calorie-burn gamification
- meal photo OCR
- recipe builder
- full workout tracker inside this app
- large coach chat UI

These can come later if useful.

---

## Future Direction

### Coach Layer
Future coach-like logic may include:
- “protein is the issue today, not calories”
- “skip rice, eat tofu”
- “this meal is calorie-dense despite small quantity”
- “don’t panic over one high meal”

### Workout-Aware Nutrition
Future integration with workout data (e.g. GRYND) may allow:
- workout-type-aware nutrition targets
- training load-aware recommendations
- smarter rest-day vs training-day logic

---

## Product Success Criteria

The app is successful if:
- logging is fast enough to use daily
- calorie/protein estimates feel believable
- daily targets feel coherent
- users trust it more than generic calorie apps
- it reduces manual mental calorie estimation effort
- it becomes more accurate over time for recurring users