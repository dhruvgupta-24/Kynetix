# Development Rules

## General Rules

- Do not create duplicate logic for the same feature
- Do not leave unused or dead code behind
- Do not hardcode values inside UI widgets
- Always reuse existing models/services where possible

---

## Estimation System Rules

- AI must not override known user-specific food data
- Paneer must never be undercounted as a small sabzi
- Milk quantities must be respected (e.g., 400 ml ≠ 150 kcal)
- Restaurant food must not be treated like home food

---

## Target Engine Rules

- One target engine only
- All screens must use the same target values
- Health Connect must only adjust targets moderately

---

## Persistence Rules

- App must not reset on restart
- Onboarding must run only once
- Profile, logs, and meals must persist

---

## UX Rules

- Do not show fake ranges (e.g., 235–235)
- Show ranges only when uncertainty exists
- Keep UI clean and not cluttered

---

## Code Quality Rules

- Prefer refactoring over patching
- Keep code modular and readable
- Avoid unnecessary complexity