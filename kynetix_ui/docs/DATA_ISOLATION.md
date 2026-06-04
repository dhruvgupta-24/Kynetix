# Data Isolation Architecture Contract

## Purpose

This document defines the **user isolation guarantees** for Kynetix's nutrition memory layer.
It is a binding architecture contract: any future change that weakens these guarantees is a
**security regression** and must be explicitly reviewed.

---

## Threat Model

| Threat | Description |
|--------|-------------|
| **Cross-user data bleed** | User A's personal food overrides or recurring meals are served to User B after an account switch on the same device. |
| **Race-condition bleed** | A cache read wins a race against `clearAll()`, returning stale user-A data while user-B's session is hydrating. |
| **Partial-clear bleed** | One cache layer is cleared but another is not, leaving stale data in memory even though SharedPreferences is clean. |

---

## Fail-Closed Design

All three nutrition memory stores implement **fail-closed semantics**:

> If the guard is not in the `Ready` state for the **currently authenticated user**, every
> lookup returns `null`. The system prefers returning no data over returning wrong data.

This applies to:
- `UserNutritionMemory.lookup()` — per-ingredient atomic corrections
- `MealMemory.lookup()` / `lookupRecurring()` — AI-confirmed recurring meals
- `MealMemory.lookupExactKnownFood()` — user-learned known foods (bootstrap defaults always safe)
- `PersonalNutritionMemory.lookupExact()` — user-added overrides only (built-ins always safe)
- `PersonalNutritionMemory.lookupTemplate()` — user-added overrides only (built-ins always safe)

### Defense-in-Depth Cache Ownership Verification

To guard against edge cases where the authentication context changes without triggering a full reset, each individual cache layer implements cache-level ownership verification:
1. When any write is performed (e.g. `saveOverride`, `store`, `storeKnownFood`), the cache saves the active user ID (`_ownerUserId = NutritionHydrationGuard.instance.currentUserId`).
2. During initialization (`init()`), each cache loads its cached owner ID from SharedPreferences (`cached_owner_user_id_v1`).
3. On every read lookup of user-specific data, the cache verifies that `_ownerUserId == currentUserId` (retrieved via `NutritionHydrationGuard.instance.currentUserId`, which delegates to Supabase auth in production and supports test overrides).
4. If there is a mismatch, the lookup **fails closed** and returns `null`. Any mismatch in `_LoggedInGateState` (or on app cold launch) immediately triggers a call to `PersistenceService.reset()` to purge the stale user's profile and cache.

---

## Gate: NutritionHydrationGuard

`NutritionHydrationGuard` is a singleton with three states:

```
NotReady  ──beginHydration()──▶  Hydrating  ──markComplete(userId)──▶  Ready
   ▲                                                                        │
   └─────────────────────── reset() ◀──────────────────────────────────────┘
```

| State | `isReadyForCurrentUser` | Meaning |
|-------|------------------------|---------|
| `NotReady` | `false` | Pre-login or post-logout. All caches blocked. |
| `Hydrating` | `false` | Cloud sync in progress. Caches blocked until complete. |
| `Ready(userId)` | `true` only when `userId == currentAuthUserId` | Data safe to serve. |

The guard stores the **userId it was hydrated for**. Even in `Ready` state, if the
authenticated user changes (e.g. deep-link or OS-level account switch) without going through
the proper logout sequence, all caches will return `null`.

---

## Account Switch Sequence (Enforced)

The following sequence is enforced in `AuthService.signOut()` and `PersistenceService.reset()`.
The order is **not negotiable** — deviating from it reopens the race condition.

```
1. NutritionHydrationGuard.instance.reset()   ← FIRST: closes the gate
2. PersonalNutritionMemory.instance.clearAll()
3. MealMemory.instance.clearAll()
4. UserNutritionMemory.instance.clearAll()
5. QuickAddService.instance.resetAll()
6. EatingPatternService.instance.resetAll()
7. WorkoutService.instance.clearAll()
8. SharedPreferences explicit key removal (belt-and-suspenders)
9. supabase.auth.signOut()                    ← LAST: revokes JWT
```

After step 1, **any nutrition memory read returns `null`**, regardless of what data is still
in in-memory maps. Steps 2–4 then wipe the in-memory maps. Step 8 ensures the SharedPreferences
backing store is also clean.

---

## Login / Re-hydration Sequence

```
supabase.auth.signIn / signInWithIdToken
  │
  ▼
AuthGate detects new session
  │
  ├── Quick-pass path (onboarding done + local profile cached):
  │     NutritionHydrationGuard.instance.markComplete(session.user.id)
  │     → Show AppShell immediately
  │     → CloudSyncService.hydrateFromCloud() runs in background
  │         (markComplete already called, so guard is Ready during sync)
  │
  └── Full sync path:
        CloudSyncService.hydrateFromCloud()
          ├── beginHydration()         ← gate enters Hydrating
          ├── ... fetch from Supabase ...
          └── markComplete(userId)     ← gate enters Ready(userId)
```

After `markComplete(userId)`, all cache lookups are unblocked for that specific user.

---

## Per-Service Isolation Details

### `UserNutritionMemory`
- **Scope:** Per-ingredient atomic calorie/protein corrections made by the user.
- **Guard check:** `lookup()` returns `null` if guard is not ready.
- **`clearAll()`:** Clears `_overrides`, sets `_ready = false`, removes `user_meal_overrides_v1` pref.
- **Re-init:** `init()` is called again on next login via `PersistenceService.load()`.

### `MealMemory`
- **Scope:** AI-confirmed recurring meals, candidate promotions, user-learned known foods.
- **Guard check:** `lookup()`, `lookupRecurring()`, and `lookupExactKnownFood()` all check the guard.
  - Exception: bootstrap-compiled `_knownFoods` entries (identical for all users) are always served.
- **`clearAll()`:** Clears `_store`, `_candidates`, `_knownFoods`, sets `_initialized = false`,
  removes all three pref keys, then immediately restores bootstrap defaults.

### `PersonalNutritionMemory`
- **Scope:** User-added personal food overrides and templates.
- **Guard check:** `lookupExact()` and `lookupTemplate()` gate on guard for user overrides only.
  - Built-in `_defaultTemplates` (compiled-in, identical for all users) are always served.
- **`clearAll()`:** Clears `_userOverrides`, sets `_initialized = false`, removes `personal_nutrition_memory_v1` pref.

---

## What Is NOT Isolated

The following are **intentionally shared** across users and are safe to serve before hydration:

| Data | Reason |
|------|--------|
| `_defaultTemplates` in `PersonalNutritionMemory` | Compiled-in constants, identical for all users. |
| Bootstrap `_defaultKnownFoods` in `MealMemory` | Compiled-in constants, identical for all users. |
| `UserProfile` / `currentUserProfile` | Wiped by `PersistenceService.reset()` at logout. |
| Day logs | Wiped by `PersistenceService.reset()` at logout. |

---

## Testing

The isolation guarantees are verified by `test/user_isolation_test.dart`, which covers:

1. Guard starts in `NotReady` state.
2. All caches return `null` when guard is `NotReady`.
3. Guard transitions correctly: `NotReady → Hydrating → Ready`.
4. Caches return data after `markComplete()`.
5. `reset()` returns guard to `NotReady`.
6. Caches return `null` again after `reset()`.
7. `markComplete()` with wrong userId leaves guard in `NotReady`.
8. Full account-switch sequence produces clean isolation.
9. `clearAll()` on each service wipes in-memory + SharedPreferences data.
10. Bootstrap defaults are served even when guard is `NotReady` (known foods only).
11. User overrides in `PersonalNutritionMemory` are blocked when guard not ready.
12. Built-in templates in `PersonalNutritionMemory` are served even when guard not ready.
13. `MealMemory.lookupExactKnownFood()` serves bootstrap defaults before guard is ready.
14. `UserNutritionMemory.lookup()` returns `null` when guard is `NotReady`.
