// ignore_for_file: avoid_print
// user_isolation_test.dart
//
// Verifies the fail-closed user isolation guarantees for the nutrition memory
// layer.  These tests do NOT require a live Supabase connection — all remote
// calls are stubbed by the mock-auth override on NutritionHydrationGuard.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/personal_nutrition_memory.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

const _userA = 'user-a-uuid-1234';
const _userB = 'user-b-uuid-5678';

/// Put the guard into the NotReady state and clear the userId override so
/// that `isReadyForCurrentUser` correctly returns false.
void _resetGuard() {
  NutritionHydrationGuard.instance.reset();
  NutritionHydrationGuard.instance.currentUserIdOverride = null;
}

/// Bring the guard into Ready state for [userId].
void _hydrateAs(String userId) {
  NutritionHydrationGuard.instance.currentUserIdOverride = userId;
  NutritionHydrationGuard.instance.markComplete(userId);
}

// ──────────────────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    // Fresh prefs + closed guard before every test.
    SharedPreferences.setMockInitialValues({});
    _resetGuard();
    // Re-init all memory singletons with empty prefs.
    await UserNutritionMemory.instance.clearAll();
    await MealMemory.instance.clearAll();
    await PersonalNutritionMemory.instance.clearAll();
  });

  // ── 1. Guard initial state ──────────────────────────────────────────────────

  group('Guard initial state', () {
    test('1a: Guard starts in NotReady state', () {
      expect(NutritionHydrationGuard.instance.stateName, 'NotReady');
      expect(NutritionHydrationGuard.instance.hydratedUserId, isNull);
    });

    test('1b: isReadyForCurrentUser is false when NotReady', () {
      NutritionHydrationGuard.instance.currentUserIdOverride = _userA;
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isFalse);
    });

    test('1c: isReadyForCurrentUser is false when Hydrating', () {
      NutritionHydrationGuard.instance.currentUserIdOverride = _userA;
      NutritionHydrationGuard.instance.beginHydration();
      expect(NutritionHydrationGuard.instance.stateName, 'Hydrating');
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isFalse);
    });
  });

  // ── 2. All caches block when guard is NotReady ──────────────────────────────

  group('Caches blocked when NotReady', () {
    test('2a: UserNutritionMemory.lookup() returns null when guard NotReady', () async {
      // Hydrate as user A, save an override, then reset guard.
      _hydrateAs(_userA);
      await UserNutritionMemory.instance.init();
      await UserNutritionMemory.instance.saveOverride(
        'test food',
        100.0, 10.0,
        referenceQuantity: 1.0,
        referenceUnit: 'serving',
      );
      // Close the gate.
      _resetGuard();

      final result = UserNutritionMemory.instance.lookup('test food');
      expect(result, isNull,
          reason: 'lookup() must fail-closed when guard is NotReady');
    });

    test('2b: MealMemory.lookup() returns null when guard NotReady', () async {
      _hydrateAs(_userA);
      await MealMemory.instance.init();
      await MealMemory.instance.store(
        '2 roti dal',
        _stubResult('2 roti dal', 480, 14),
      );
      _resetGuard();

      final result = MealMemory.instance.lookup('2 roti dal');
      expect(result, isNull,
          reason: 'MealMemory.lookup() must fail-closed when guard is NotReady');
    });

    test('2c: MealMemory.lookupRecurring() returns null when guard NotReady', () async {
      _hydrateAs(_userA);
      await MealMemory.instance.init();
      await MealMemory.instance.store(
        '1 scoop whey water',
        _stubResult('1 scoop whey water', 115, 22),
      );
      _resetGuard();

      final result = MealMemory.instance.lookupRecurring('1 scoop whey water');
      expect(result, isNull,
          reason: 'lookupRecurring() must fail-closed when guard is NotReady');
    });

    test('2d: PersonalNutritionMemory.lookupExact() blocks user overrides when NotReady', () async {
      _hydrateAs(_userA);
      await PersonalNutritionMemory.instance.init();
      await PersonalNutritionMemory.instance.saveOverride(
        rawInput: 'custom protein bar',
        label: 'Custom Protein Bar',
        kcal: 250,
        protein: 20,
      );
      _resetGuard();

      final result = PersonalNutritionMemory.instance.lookupExact('custom protein bar');
      expect(result, isNull,
          reason: 'lookupExact() must block user overrides when guard is NotReady');
    });

    test('2e: PersonalNutritionMemory.lookupTemplate() blocks user overrides when NotReady', () async {
      _hydrateAs(_userA);
      await PersonalNutritionMemory.instance.init();
      await PersonalNutritionMemory.instance.saveOverride(
        rawInput: 'custom bar snack',
        label: 'Custom Bar Snack',
        kcal: 200,
        protein: 15,
        keywords: ['custom', 'bar', 'snack'],
      );
      _resetGuard();

      final result = PersonalNutritionMemory.instance.lookupTemplate('my custom bar snack');
      expect(result, isNull,
          reason: 'lookupTemplate() must block user overrides when guard is NotReady');
    });
  });

  // ── 3. Guard state transitions ──────────────────────────────────────────────

  group('Guard state transitions', () {
    test('3a: NotReady → Hydrating → Ready transition', () {
      expect(NutritionHydrationGuard.instance.stateName, 'NotReady');

      NutritionHydrationGuard.instance.beginHydration();
      expect(NutritionHydrationGuard.instance.stateName, 'Hydrating');

      NutritionHydrationGuard.instance.currentUserIdOverride = _userA;
      NutritionHydrationGuard.instance.markComplete(_userA);
      expect(NutritionHydrationGuard.instance.stateName, 'Ready');
      expect(NutritionHydrationGuard.instance.hydratedUserId, _userA);
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isTrue);
    });

    test('3b: markComplete(null) stays NotReady', () {
      NutritionHydrationGuard.instance.beginHydration();
      NutritionHydrationGuard.instance.currentUserIdOverride = null;
      NutritionHydrationGuard.instance.markComplete(null);
      expect(NutritionHydrationGuard.instance.stateName, 'NotReady');
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isFalse);
    });

    test('3c: reset() returns guard to NotReady from Ready', () {
      _hydrateAs(_userA);
      expect(NutritionHydrationGuard.instance.stateName, 'Ready');

      NutritionHydrationGuard.instance.reset();
      expect(NutritionHydrationGuard.instance.stateName, 'NotReady');
      expect(NutritionHydrationGuard.instance.hydratedUserId, isNull);
    });
  });

  // ── 4. Caches return data after markComplete ────────────────────────────────

  group('Caches unblocked after markComplete', () {
    test('4a: UserNutritionMemory.lookup() returns data after hydration', () async {
      _hydrateAs(_userA);
      await UserNutritionMemory.instance.init();
      await UserNutritionMemory.instance.saveOverride(
        'chicken breast',
        165.0, 31.0,
        referenceQuantity: 100.0,
        referenceUnit: 'g',
      );

      final result = UserNutritionMemory.instance.lookup('chicken breast');
      expect(result, isNotNull);
    });

    test('4b: MealMemory.lookup() returns data after hydration', () async {
      _hydrateAs(_userA);
      await MealMemory.instance.init();
      await MealMemory.instance.store(
        '2 roti sabzi',
        _stubResult('2 roti sabzi', 370, 10),
      );

      final result = MealMemory.instance.lookup('2 roti sabzi');
      expect(result, isNotNull);
    });
  });

  // ── 5. Cross-user data bleed prevention ────────────────────────────────────

  group('Cross-user isolation', () {
    test('5a: User B cannot see User A data after account switch', () async {
      // ── Session A ──
      _hydrateAs(_userA);
      await UserNutritionMemory.instance.init();
      await UserNutritionMemory.instance.saveOverride(
        'user a special meal',
        300.0, 25.0,
        referenceQuantity: 1.0,
        referenceUnit: 'serving',
      );

      // Verify data exists for A.
      expect(UserNutritionMemory.instance.lookup('user a special meal'), isNotNull);

      // ── Account switch sequence ──
      NutritionHydrationGuard.instance.reset();
      await UserNutritionMemory.instance.clearAll();
      await MealMemory.instance.clearAll();
      await PersonalNutritionMemory.instance.clearAll();

      // ── Session B (guard not yet marked complete) ──
      NutritionHydrationGuard.instance.currentUserIdOverride = _userB;
      // Guard is still NotReady. No data should be served.
      expect(
        UserNutritionMemory.instance.lookup('user a special meal'),
        isNull,
        reason: 'User B should not see User A data while guard is NotReady',
      );

      // ── After B's hydration ──
      NutritionHydrationGuard.instance.markComplete(_userB);
      await UserNutritionMemory.instance.init();
      // clearAll() was called, so user A's entry is gone from prefs → no match.
      expect(
        UserNutritionMemory.instance.lookup('user a special meal'),
        isNull,
        reason: 'User A data must be wiped from prefs before B logs in',
      );
    });

    test('5b: Ownership mismatch: guard ready for A, but B is logged in', () {
      // Guard is ready for user A but current user is B.
      NutritionHydrationGuard.instance.markComplete(_userA);
      NutritionHydrationGuard.instance.currentUserIdOverride = _userB;

      expect(
        NutritionHydrationGuard.instance.isReadyForCurrentUser,
        isFalse,
        reason: 'isReadyForCurrentUser must return false on userId mismatch',
      );
    });
  });

  // ── 6. clearAll() wipes memory + prefs ─────────────────────────────────────

  group('clearAll wipes in-memory and prefs', () {
    test('6a: UserNutritionMemory.clearAll() wipes overrides', () async {
      _hydrateAs(_userA);
      await UserNutritionMemory.instance.init();
      await UserNutritionMemory.instance.saveOverride(
        'test ingredient',
        50.0, 5.0,
        referenceQuantity: 1.0,
        referenceUnit: 'serving',
      );
      expect(UserNutritionMemory.instance.allOverrides.length, 1);

      await UserNutritionMemory.instance.clearAll();
      expect(UserNutritionMemory.instance.allOverrides.isEmpty, isTrue);

      // Re-init should load nothing from prefs (pref was deleted).
      await UserNutritionMemory.instance.init();
      expect(UserNutritionMemory.instance.allOverrides.isEmpty, isTrue);
    });

    test('6b: MealMemory.clearAll() wipes recurring store', () async {
      _hydrateAs(_userA);
      await MealMemory.instance.init();
      await MealMemory.instance.store(
        'oreo biscuit',
        _stubResult('oreo biscuit', 480, 5),
      );
      expect(MealMemory.instance.allEntries.isNotEmpty, isTrue);

      await MealMemory.instance.clearAll();
      expect(MealMemory.instance.allEntries.isEmpty, isTrue);
    });

    test('6c: PersonalNutritionMemory.clearAll() wipes user overrides', () async {
      _hydrateAs(_userA);
      await PersonalNutritionMemory.instance.init();
      await PersonalNutritionMemory.instance.saveOverride(
        rawInput: 'my protein bar',
        label: 'My Protein Bar',
        kcal: 220,
        protein: 18,
      );
      expect(PersonalNutritionMemory.instance.allUserOverrides.isNotEmpty, isTrue);

      await PersonalNutritionMemory.instance.clearAll();
      expect(PersonalNutritionMemory.instance.allUserOverrides.isEmpty, isTrue);
    });
  });

  // ── 7. Bootstrap defaults always safe ──────────────────────────────────────

  group('Bootstrap defaults served without hydration', () {
    test('7a: MealMemory.lookupExactKnownFood() serves bootstrap data when NotReady', () async {
      // Guard is NotReady; bootstrap defaults should still be served.
      await MealMemory.instance.init();

      // '1 scoop whey' is a compiled-in bootstrap entry.
      final result = MealMemory.instance.lookupExactKnownFood('1 scoop whey');
      expect(
        result,
        isNotNull,
        reason: 'Bootstrap compiled-in known foods are identical for all users and must be safe before hydration',
      );
    });

    test('7b: MealMemory.lookupExactKnownFood() blocks user-learned entries when NotReady', () async {
      _hydrateAs(_userA);
      await MealMemory.instance.init();
      // Store a user-learned known food (NOT in the compiled-in bootstrap).
      await MealMemory.instance.storeKnownFood(
        'user specific snack',
        _stubResult('user specific snack', 150, 8),
      );
      // Verify it's accessible when guard is ready.
      expect(MealMemory.instance.lookupExactKnownFood('user specific snack'), isNotNull);

      // Close the gate.
      _resetGuard();

      // Must return null — this is user-specific, not a bootstrap default.
      final result = MealMemory.instance.lookupExactKnownFood('user specific snack');
      expect(
        result,
        isNull,
        reason: 'User-learned known foods must be blocked when guard is NotReady',
      );
    });

    test('7c: PersonalNutritionMemory built-in templates served without hydration', () async {
      // Guard is NotReady.
      await PersonalNutritionMemory.instance.init();

      // '1 roti' is a compiled-in default.
      final result = PersonalNutritionMemory.instance.lookupExact('1 roti');
      expect(
        result,
        isNotNull,
        reason: 'Compiled-in personal defaults are identical for all users and must be safe before hydration',
      );
    });
  });

  // ── 8. Full account-switch sequence ────────────────────────────────────────

  group('Full account-switch produces clean isolation', () {
    test('8a: Complete switch sequence wipes all user data', () async {
      // Session A setup.
      _hydrateAs(_userA);
      await UserNutritionMemory.instance.init();
      await MealMemory.instance.init();
      await PersonalNutritionMemory.instance.init();

      await UserNutritionMemory.instance.saveOverride(
        'my special food', 400.0, 35.0,
        referenceQuantity: 1.0, referenceUnit: 'serving',
      );
      await MealMemory.instance.store('my lunch', _stubResult('my lunch', 600, 25));
      await PersonalNutritionMemory.instance.saveOverride(
        rawInput: 'my custom snack',
        label: 'My Custom Snack',
        kcal: 180, protein: 12,
      );

      // Verify data is present.
      expect(UserNutritionMemory.instance.lookup('my special food'), isNotNull);
      expect(MealMemory.instance.lookup('my lunch'), isNotNull);
      expect(PersonalNutritionMemory.instance.lookupExact('my custom snack'), isNotNull);

      // ── Account switch sequence (mirrors AuthService.signOut + PersistenceService.reset) ──
      NutritionHydrationGuard.instance.reset();               // Step 1
      await PersonalNutritionMemory.instance.clearAll();      // Step 2
      await MealMemory.instance.clearAll();                   // Step 3
      await UserNutritionMemory.instance.clearAll();          // Step 4

      // ── Verify complete wipe ──
      NutritionHydrationGuard.instance.currentUserIdOverride = _userB;

      expect(
        UserNutritionMemory.instance.lookup('my special food'),
        isNull,
        reason: 'UserNutritionMemory must be clear after account switch',
      );
      expect(
        MealMemory.instance.lookup('my lunch'),
        isNull,
        reason: 'MealMemory must be clear after account switch',
      );
      expect(
        PersonalNutritionMemory.instance.lookupExact('my custom snack'),
        isNull,
        reason: 'PersonalNutritionMemory must be clear after account switch',
      );

      // ── User B hydrates ──
      NutritionHydrationGuard.instance.markComplete(_userB);
      await UserNutritionMemory.instance.init();
      await MealMemory.instance.init();
      await PersonalNutritionMemory.instance.init();

      // User A's data must not re-appear for user B.
      expect(UserNutritionMemory.instance.lookup('my special food'), isNull);
      expect(MealMemory.instance.lookup('my lunch'), isNull);
      expect(PersonalNutritionMemory.instance.lookupExact('my custom snack'), isNull);
    });
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// Stub helpers
// ──────────────────────────────────────────────────────────────────────────────

NutritionResult _stubResult(String label, double kcal, double protein) {
  final cal = NutrientRange(min: kcal, max: kcal);
  final pro = NutrientRange(min: protein, max: protein);
  return NutritionResult(
    canonicalMeal: label,
    items: [
      NutritionItem(
        name: label,
        quantity: 1,
        unit: 'serving',
        estimated: false,
        mode: EstimationMode.packagedKnown,
        calories: cal,
        protein: pro,
      ),
    ],
    calories: cal,
    protein: pro,
    confidence: 0.98,
    warnings: const [],
    source: 'test_stub',
    createdAt: DateTime.now(),
  );
}
