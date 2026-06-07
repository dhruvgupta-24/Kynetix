// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/eating_pattern_service.dart';
import 'package:kynetix/services/food_role_classifier.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart'
    show NutrientRange;

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Build a minimal NutritionItem for testing the anchor pass.
NutritionItem _makeItem(String name, double calories, double protein,
    {bool scalarApplied = false}) {
  return NutritionItem(
    name: name,
    quantity: 1.0,
    unit: 'serving',
    estimated: true,
    mode: EstimationMode.contextualIntake,
    calories: NutrientRange(min: calories * 0.9, max: calories * 1.1),
    protein: NutrientRange(min: protein * 0.9, max: protein * 1.1),
    eatingPatternScalarApplied: scalarApplied,
  );
}

/// Simulates the meal-level portion-anchor pass (stateless, for unit testing).
///
/// Replicates the logic in [NutritionPipeline._applyMealLevelPortionAnchorPass]
/// using [FoodRoleClassifier] and the given [anchor] + [EatingPatternService].
List<NutritionItem> _runPass(
  List<NutritionItem> items,
  PortionAnchor anchor,
  EatingPatternService svc,
) {
  // Guard: already applied?
  if (items.any((i) => i.eatingPatternScalarApplied)) {
    return items;
  }

  final roles = <NutritionItem, FoodRole>{};
  double totalPrimaryCal = 0;
  double totalAccCal = 0;

  for (final item in items) {
    final role = FoodRoleClassifier.classify(item.name);
    roles[item] = role;
    if (role == FoodRole.primary) {
      totalPrimaryCal += item.calories.mid;
    } else if (role == FoodRole.accompaniment) {
      totalAccCal += item.calories.mid;
    }
  }

  final hasPrimary = totalPrimaryCal > 0;
  final hasAccompaniment = totalAccCal > 0;

  double baseCarbServings = 0;
  double baseAccServings = 0;
  for (final item in items) {
    final role = roles[item]!;
    if (role == FoodRole.primary) {
      baseCarbServings += FoodRoleClassifier.estimateServingCount(
          item.name, FoodRole.primary, item.quantity, item.calories.mid);
    } else if (role == FoodRole.accompaniment) {
      baseAccServings += FoodRoleClassifier.estimateServingCount(
          item.name, FoodRole.accompaniment, item.quantity, item.calories.mid);
    }
  }

  baseCarbServings = baseCarbServings.clamp(0.1, 10.0);
  baseAccServings = baseAccServings.clamp(0.1, 10.0);

  double? getScalar(FoodRole r, FoodRole? ctx) =>
      svc.getScalar(r, contextRole: ctx);

  final result = <NutritionItem>[];
  for (final item in items) {
    final role = roles[item]!;
    double? finalScalar;

    if (anchor == PortionAnchor.carbAnchored && hasPrimary && hasAccompaniment) {
      if (role == FoodRole.accompaniment) {
        final expectedAcc = baseCarbServings * 0.5;
        final baseScale = (expectedAcc / baseAccServings).clamp(0.3, 3.0);
        final pattern = getScalar(FoodRole.accompaniment, FoodRole.primary) ?? 0.55;
        finalScalar = (baseScale * pattern).clamp(0.3, 2.5);
      } else {
        finalScalar = getScalar(role, hasAccompaniment ? FoodRole.accompaniment : null);
      }
    } else if (anchor == PortionAnchor.curryAnchored && hasPrimary && hasAccompaniment) {
      if (role == FoodRole.primary) {
        final accPattern = getScalar(FoodRole.accompaniment, FoodRole.primary) ?? 1.40;
        final scaledAcc = baseAccServings * accPattern;
        final expectedCarb = scaledAcc * 1.5;
        final baseScale = (expectedCarb / baseCarbServings).clamp(0.3, 3.0);
        final pattern = getScalar(FoodRole.primary, FoodRole.accompaniment) ?? 0.60;
        finalScalar = (baseScale * pattern).clamp(0.3, 2.5);
      } else if (role == FoodRole.accompaniment) {
        finalScalar = getScalar(FoodRole.accompaniment, FoodRole.primary) ?? 1.40;
      } else {
        finalScalar = getScalar(role, hasPrimary ? FoodRole.primary : null);
      }
    } else {
      final context = (role == FoodRole.primary)
          ? (hasAccompaniment ? FoodRole.accompaniment : null)
          : (role == FoodRole.accompaniment)
              ? (hasPrimary ? FoodRole.primary : null)
              : null;
      finalScalar = getScalar(role, context);
    }

    if (finalScalar != null) {
      result.add(item.withScalar(finalScalar));
    } else {
      result.add(item.withScalar(1.0));
    }
  }

  return result;
}

/// Returns the midpoint calorie value for a list of items.
double _totalCalMid(List<NutritionItem> items) =>
    items.fold(0.0, (s, i) => s + i.calories.mid);


// ─── Eating Style Estimation Tests ────────────────────────────────────────────
//
// These tests verify that EatingPatternService.seedFromPortionAnchor() correctly
// bootstraps the scalar system so that meal estimation is immediately affected
// by the declared Eating Style, without requiring any real user corrections.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EatingPatternService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    svc = EatingPatternService.instance;
    // Always start from a clean state to avoid inter-test pollution.
    svc.resetAll();
    // Load restores from SharedPreferences (empty in these tests).
    await svc.load();
  });

  // ── 1. Carb-Anchored seeding ─────────────────────────────────────────────────

  group('seedFromPortionAnchor — carbAnchored', () {
    test('scalar for accompaniment-in-primary-context is < 1.0', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final scalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      // Carb-anchored seed: 0.55× — scalar must be below 1.0
      expect(scalar, lessThan(1.0),
          reason: 'Carb-anchored: dal/sabzi should be estimated smaller');
      expect(scalar, greaterThan(0.2),
          reason: 'Scalar should not be unreasonably low');
    });

    test('primary items are unaffected (no primary seed for carbAnchored)', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final scalar = svc.getScalar(
        FoodRole.primary,
        contextRole: FoodRole.accompaniment,
      );
      // No seed for primary under carbAnchored — scalar should be near 1.0
      expect(scalar, isNull,
          reason: 'Primary (roti/rice) should not be adjusted for carbAnchored');
    });

    test('calorie estimate for dal is lower under carbAnchored vs balanced', () {
      // Balanced baseline — no seed
      final baseScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final anchoredScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      // Since baseScalar is null (no corrections/seed), we compare against 1.0 or use null-fallback logic.
      expect(anchoredScalar, isNotNull);
      expect(anchoredScalar!, lessThan(baseScalar ?? 1.0),
          reason: 'Carb-anchored must produce a lower scalar than balanced '
              '(less dal estimated)');
    });
  });

  // ── 2. Curry-Anchored seeding ─────────────────────────────────────────────────

  group('seedFromPortionAnchor — curryAnchored', () {
    test('scalar for accompaniment-in-primary-context is > 1.0', () {
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);

      final scalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      // Curry-anchored seed: 1.40× — scalar must be above 1.0
      expect(scalar, greaterThan(1.0),
          reason: 'Curry-anchored: dal/sabzi should be estimated larger');
    });

    test('scalar for primary-in-accompaniment-context is < 1.0', () {
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);

      final scalar = svc.getScalar(
        FoodRole.primary,
        contextRole: FoodRole.accompaniment,
      );
      // Curry-anchored seed for primary: 0.60×
      expect(scalar, lessThan(1.0),
          reason: 'Curry-anchored: roti/rice should be estimated smaller');
    });

    test('calorie estimate for dal is higher under curryAnchored vs balanced', () {
      final baseScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);

      final anchoredScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      expect(anchoredScalar, isNotNull);
      expect(anchoredScalar!, greaterThan(baseScalar ?? 1.0),
          reason: 'Curry-anchored must produce a higher scalar than balanced '
              '(more dal estimated)');
    });

    test('carbAnchored vs curryAnchored produce opposite results', () async {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
      final carbScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      svc.resetAll();
      await svc.load();
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);
      final curryScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      expect(carbScalar, isNotNull);
      expect(curryScalar, isNotNull);
      expect(carbScalar!, lessThan(curryScalar!),
          reason: 'carbAnchored < balanced < curryAnchored for accompaniment scalar');
    });
  });

  // ── 3. Balanced — no synthetic tilt ─────────────────────────────────────────

  group('seedFromPortionAnchor — balanced', () {
    test('does not insert records that skew scalar away from 1.0', () {
      svc.seedFromPortionAnchor(PortionAnchor.balanced);

      // With balanced seed + no corrections, scalar should be null (not enough data yet)
      final scalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNull,
          reason: 'Balanced should not skew the scalar or trigger any adjustment without real corrections');
    });
  });

  // ── 4. Idempotency ────────────────────────────────────────────────────────────

  group('seedFromPortionAnchor — idempotency', () {
    test('calling twice with same anchor is a no-op', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
      final scalar1 = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored); // duplicate call
      final scalar2 = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      expect(scalar1, equals(scalar2),
          reason: 'Second identical seed must not double-weight the records');
    });

    test('switching anchor removes old seed', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
      final carbScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(carbScalar, isNotNull);
      expect(carbScalar!, lessThan(1.0));

      // Switch to curry-anchored — should remove the carb seed records.
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);
      final curryScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(curryScalar, isNotNull);
      expect(curryScalar!, greaterThan(1.0),
          reason: 'Old carb seed must be replaced by curry seed, not accumulated');
    });
  });

  // ── 5. Real corrections override the seed ─────────────────────────────────────

  group('Real corrections override seeded behavior', () {
    test('3 real carb-anchored corrections override curry seed', () {
      // Start with curry-anchored seed (forces high scalar).
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);
      final beforeScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(beforeScalar, isNotNull);
      expect(beforeScalar!, greaterThan(1.0));

      // User consistently corrects dal downward (carb-anchored behavior).
      // pipelineEstimate=200, userCorrected=100 → ratio ≈ 0.5
      final now = DateTime.now();
      for (int i = 0; i < 3; i++) {
        svc.recordIngredientCorrection(
          correctedItemRole: FoodRole.accompaniment,
          mealHasPrimary: true,
          pipelineCalEstimate: 200.0,
          userCorrectedCal: 100.0,
          timestamp: now.subtract(Duration(hours: i)),
        );
      }

      final afterScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(afterScalar, isNotNull);
      // Real corrections at weight ≈ 1.0 each should pull scalar down.
      expect(afterScalar!, lessThan(beforeScalar),
          reason: 'Real corrections must gradually override the seed');
    });

    test('5 real corrections significantly reduce seed influence', () {
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);

      final seedScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(seedScalar, isNotNull);

      // 5 real corrections at ratio=0.5 (dal estimated to half of pipeline)
      final now = DateTime.now();
      for (int i = 0; i < 5; i++) {
        svc.recordIngredientCorrection(
          correctedItemRole: FoodRole.accompaniment,
          mealHasPrimary: true,
          pipelineCalEstimate: 200.0,
          userCorrectedCal: 100.0,
          timestamp: now.subtract(Duration(hours: i)),
        );
      }

      final updatedScalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(updatedScalar, isNotNull);

      // 5 recent corrections (weight ~1.0 each) vs 4 seed records (weight ~0.25)
      // Total correction influence should significantly dominate.
      expect(updatedScalar!, lessThan(seedScalar! * 0.85),
          reason: '5 real corrections at opposite direction should dominate seed');
    });
  });

  // ── 6. Persistence through save/load cycle ────────────────────────────────────

  group('Seeded anchor persists through save/load', () {
    test('carbAnchored seed survives save + load', () async {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
      await svc.save();

      // Simulate fresh load.
      svc.resetAll();
      await svc.load();

      final scalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNotNull);
      expect(scalar!, lessThan(1.0),
          reason: 'Seed records must survive save + load so the effect persists '
              'across app restarts');
    });

    test('seeded anchor sentinel survives save + load', () async {
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);
      await svc.save();

      svc.resetAll();
      await svc.load();

      // Re-seeding with the same anchor should be a no-op (idempotency).
      // If the sentinel was not restored, this would double-weight.
      final beforeReseeding = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(beforeReseeding, isNotNull);

      // Calling seed again — should be no-op because sentinel is restored.
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);

      final afterReseeding = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );

      expect(beforeReseeding, equals(afterReseeding),
          reason: 'Re-seeding with same anchor after load must not double-weight');
    });
  });

  // ── 7. Edge cases ─────────────────────────────────────────────────────────────

  group('Edge cases', () {
    test('seed on empty service does not throw', () {
      expect(() => svc.seedFromPortionAnchor(PortionAnchor.carbAnchored),
          returnsNormally);
    });

    test('resetAll clears seed anchor tracking', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
      svc.resetAll();

      // After reset, re-seeding same anchor should work (not be a no-op).
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
      final scalar = svc.getScalar(
        FoodRole.accompaniment,
        contextRole: FoodRole.primary,
      );
      expect(scalar, isNotNull);
      expect(scalar!, lessThan(1.0),
          reason: 'Seed should be re-applicable after resetAll');
    });

    test('protein food role is unaffected by any anchor seed', () {
      for (final anchor in PortionAnchor.values) {
        svc.resetAll();
        svc.seedFromPortionAnchor(anchor);

        final scalar = svc.getScalar(
          FoodRole.protein,
          contextRole: FoodRole.primary,
        );
        // Protein items (eggs, chicken, paneer pieces) should never be
        // seeded — they are independent of eating style.
        expect(scalar, isNull,
            reason: 'anchor=${anchor.name}: protein role must not be seeded');
      }
    });

    test('addOn food role is unaffected by any anchor seed', () {
      for (final anchor in PortionAnchor.values) {
        svc.resetAll();
        svc.seedFromPortionAnchor(anchor);

        final scalar = svc.getScalar(
          FoodRole.addOn,
          contextRole: null,
        );
        expect(scalar, isNull,
            reason: 'anchor=${anchor.name}: addOn role must not be seeded');
      }
    });
  });

  // ── 8. Double-application guard ───────────────────────────────────────────────
  //
  // Verifies that calling _runPass (the meal-level Portion Anchor pass) on the
  // same item list twice produces IDENTICAL output — i.e. scalars do not
  // compound across repeated calls, and the eatingPatternScalarApplied flag
  // correctly short-circuits the second invocation.

  group('Double-application guard', () {
    test('running the pass twice yields identical calories', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final items = [
        _makeItem('roti', 80.0, 3.0),   // primary
        _makeItem('dal', 120.0, 7.0),    // accompaniment
      ];

      final pass1 = _runPass(items, PortionAnchor.carbAnchored, svc);
      final pass2 = _runPass(pass1, PortionAnchor.carbAnchored, svc);

      expect(_totalCalMid(pass1), closeTo(_totalCalMid(pass2), 0.01),
          reason: 'Second pass must be a no-op; calories must not drift');
    });

    test('all items have eatingPatternScalarApplied == true after first pass', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final items = [
        _makeItem('roti', 80.0, 3.0),
        _makeItem('dal', 120.0, 7.0),
      ];

      final pass1 = _runPass(items, PortionAnchor.carbAnchored, svc);

      for (final item in pass1) {
        expect(item.eatingPatternScalarApplied, isTrue,
            reason: '"${item.name}" must be marked as scalar-applied after first pass');
      }
    });

    test('second pass is skipped when guard flag is present (curry-anchored)', () {
      svc.seedFromPortionAnchor(PortionAnchor.curryAnchored);

      final items = [
        _makeItem('rice', 200.0, 4.0),     // primary
        _makeItem('rajma', 160.0, 9.0),    // accompaniment
      ];

      final pass1 = _runPass(items, PortionAnchor.curryAnchored, svc);
      final pass2 = _runPass(pass1, PortionAnchor.curryAnchored, svc);

      // If the second pass were executed, protein items would compound again.
      expect(_totalCalMid(pass1), closeTo(_totalCalMid(pass2), 0.01),
          reason: 'Curry-anchored: second pass must be no-op');
    });

    test('items constructed with scalarApplied=true are never re-processed', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      // Simulate items that came from memory and already had the flag set.
      final items = [
        _makeItem('roti', 80.0, 3.0, scalarApplied: true),
        _makeItem('dal', 120.0, 7.0, scalarApplied: true),
      ];

      final result = _runPass(items, PortionAnchor.carbAnchored, svc);

      // Pass must be skipped; calories must be exactly the same (no scaling).
      expect(_totalCalMid(items), closeTo(_totalCalMid(result), 0.01),
          reason: 'Pre-flagged items must not be re-scaled');
    });

    test('running pass three times does not drift (extended idempotency)', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final items = [
        _makeItem('roti', 80.0, 3.0),
        _makeItem('dal', 120.0, 7.0),
        _makeItem('sabzi', 90.0, 3.0),
      ];

      final pass1 = _runPass(items, PortionAnchor.carbAnchored, svc);
      final pass2 = _runPass(pass1, PortionAnchor.carbAnchored, svc);
      final pass3 = _runPass(pass2, PortionAnchor.carbAnchored, svc);

      expect(_totalCalMid(pass1), closeTo(_totalCalMid(pass3), 0.01),
          reason: 'Three consecutive passes must all produce the same total');
    });
  });

  // ── 9. Progressive carb-load scaling ─────────────────────────────────────────
  //
  // Verifies that adding more carb sources proportionally increases the
  // estimated dal/accompaniment portion under carb-anchored eating style.
  //
  // Expectation:
  //   dal(2 roti) < dal(2 roti + rice) < dal(2 roti + 2 rice)
  //
  // The pass produces a higher accompaniment estimate when the total primary
  // serving count is larger, because the "expected accompaniment" is a function
  // of baseCarbServings (0.5 × baseCarbServings).

  group('Progressive carb-load scaling (carb-anchored)', () {
    setUp(() {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);
    });

    // Helper: build a roti item with explicit serving count embedded in quantity.
    NutritionItem _roti(double count) => NutritionItem(
          name: 'roti',
          quantity: count,
          unit: 'serving',
          estimated: true,
          mode: EstimationMode.contextualIntake,
          calories: NutrientRange(min: count * 72, max: count * 88),
          protein: NutrientRange(min: count * 2.7, max: count * 3.3),
        );

    NutritionItem _rice(double cal) => _makeItem('rice', cal, 3.0);
    NutritionItem _dal(double cal) => _makeItem('dal', cal, 6.0);

    double _dalCalInMeal(List<NutritionItem> passResult) {
      return passResult
          .where((i) => FoodRoleClassifier.classify(i.name) == FoodRole.accompaniment)
          .fold(0.0, (s, i) => s + i.calories.mid);
    }

    test('2 roti + dal baseline', () {
      final items = [_roti(2), _dal(120.0)];
      final result = _runPass(items, PortionAnchor.carbAnchored, svc);
      final dalCal = _dalCalInMeal(result);

      // Dal must be scaled down from raw 120 kcal under carb-anchored.
      expect(dalCal, lessThan(120.0),
          reason: 'Carb-anchored: dal must be estimated below its raw value');
      expect(dalCal, greaterThan(20.0),
          reason: 'Dal must not be clamped to near-zero');
    });

    test('2 roti + rice + dal produces higher dal than 2 roti alone', () {
      final mealA = [_roti(2), _dal(120.0)];              // 2 roti + dal
      final mealB = [_roti(2), _rice(200.0), _dal(120.0)]; // 2 roti + rice + dal

      final passA = _runPass(mealA, PortionAnchor.carbAnchored, svc);
      final passB = _runPass(mealB, PortionAnchor.carbAnchored, svc);

      final dalA = _dalCalInMeal(passA);
      final dalB = _dalCalInMeal(passB);

      expect(dalB, greaterThan(dalA),
          reason: 'Adding rice to roti+dal must produce more dal (more carbs → more acc)');
    });

    test('2 roti + 2 rice + dal produces higher dal than 2 roti + 1 rice', () {
      final mealB = [_roti(2), _rice(200.0), _dal(120.0)];        // 2 roti + 1 rice + dal
      final mealC = [_roti(2), _rice(200.0), _rice(200.0), _dal(120.0)]; // 2 roti + 2 rice + dal

      final passB = _runPass(mealB, PortionAnchor.carbAnchored, svc);
      final passC = _runPass(mealC, PortionAnchor.carbAnchored, svc);

      final dalB = _dalCalInMeal(passB);
      final dalC = _dalCalInMid(passC);

      expect(dalC, greaterThan(dalB),
          reason: 'Two rice servings must produce even higher dal estimate than one');
    });

    test('progressive ordering holds across all three loads', () {
      final mealA = [_roti(2), _dal(120.0)];
      final mealB = [_roti(2), _rice(200.0), _dal(120.0)];
      final mealC = [_roti(2), _rice(200.0), _rice(200.0), _dal(120.0)];

      final dalA = _dalCalInMeal(_runPass(mealA, PortionAnchor.carbAnchored, svc));
      final dalB = _dalCalInMeal(_runPass(mealB, PortionAnchor.carbAnchored, svc));
      final dalC = _dalCalInMid(_runPass(mealC, PortionAnchor.carbAnchored, svc));

      expect(dalA, lessThan(dalB),
          reason: '2 roti: dal_A < dal_B');
      expect(dalB, lessThan(dalC),
          reason: '2 roti + rice: dal_B < dal_C');
    });
  });

  // ── 10. Solo-meal no-op behavior ──────────────────────────────────────────────
  //
  // Ensures the pass is effectively a no-op (only 1.0× or seeded scalar applied)
  // when a meal contains:
  //   (a) only primary foods (no accompaniment detected)
  //   (b) only accompaniment foods (no primary detected)
  //   (c) only protein foods
  //   (d) a "completeMeal" food with no mixed context
  //
  // In these cases, the anchor condition `hasPrimary && hasAccompaniment` is
  // false, so the meal-level scaling logic should not fire the ratio adjustment.

  group('Solo-meal no-op behavior', () {
    test('only-carbs meal: roti alone — no accompaniment scaling fires', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final items = [_makeItem('roti', 160.0, 6.0)];
      final raw = _totalCalMid(items);

      // With carb-anchored but no accompaniment, the pass should apply the
      // item-level scalar (if any) for primary-without-accompaniment context,
      // which is null for carbAnchored (no primary seed). Expect scalar ≈ 1.0.
      final result = _runPass(items, PortionAnchor.carbAnchored, svc);
      final adjusted = _totalCalMid(result);

      // The ratio-based accompaniment scaling must NOT fire (no dal in meal).
      // At most the item-level learned scalar for primary may apply.
      // We only assert it does not reduce roti calories — roti is not adjusted downward.
      expect(adjusted, greaterThanOrEqualTo(raw * 0.95),
          reason: 'Solo roti meal: no downward scaling on the carb item itself');
    });

    test('only-accompaniment meal: dal alone — ratio pass is skipped', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final items = [_makeItem('dal', 120.0, 7.0)];
      final raw = _totalCalMid(items);

      final result = _runPass(items, PortionAnchor.carbAnchored, svc);
      final adjusted = _totalCalMid(result);

      // Without a primary food, the carbAnchored ratio formula cannot fire.
      // Dal may receive the item-level seed scalar but not the ratio correction.
      // It should remain relatively close to raw (within the clamped scalar range).
      expect(adjusted, greaterThan(raw * 0.25),
          reason: 'Solo dal meal must not be reduced to near-zero');
      expect(adjusted, lessThan(raw * 3.0),
          reason: 'Solo dal meal must not be inflated unreasonably');
    });

    test('only-protein meal: paneer alone — neither ratio branch fires', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      final items = [_makeItem('paneer', 270.0, 18.0)];
      final raw = _totalCalMid(items);

      final result = _runPass(items, PortionAnchor.carbAnchored, svc);
      final adjusted = _totalCalMid(result);

      // paneer classifies as protein — neither primary nor accompaniment.
      // The anchor pass must not touch it (no ratio, no seeded scalar for protein).
      expect(adjusted, closeTo(raw, 1.0),
          reason: 'Protein-only food must not be scaled by the anchor pass');
    });

    test('completeMeal food: banana — no scaling applied', () {
      svc.seedFromPortionAnchor(PortionAnchor.carbAnchored);

      // banana is not in any keyword list → FoodRole.completeMeal
      final items = [_makeItem('banana', 90.0, 1.1)];
      final raw = _totalCalMid(items);

      final result = _runPass(items, PortionAnchor.carbAnchored, svc);
      final adjusted = _totalCalMid(result);

      expect(adjusted, closeTo(raw, 1.0),
          reason: 'completeMeal items must not be altered by the anchor pass');
    });

    test('balanced anchor: no ratio adjustment regardless of meal composition', () {
      svc.seedFromPortionAnchor(PortionAnchor.balanced);

      final items = [
        _makeItem('roti', 80.0, 3.0),
        _makeItem('dal', 120.0, 7.0),
      ];
      final raw = _totalCalMid(items);

      final result = _runPass(items, PortionAnchor.balanced, svc);
      final adjusted = _totalCalMid(result);

      // Balanced inserts no seed records, so getScalar returns null → withScalar(1.0).
      expect(adjusted, closeTo(raw, 1.0),
          reason: 'Balanced anchor must not change any item calories');
    });

    test('null anchor (no profile): no ratio adjustment', () {
      // No seed applied — simulates a fresh user with no eating style set.

      final items = [
        _makeItem('roti', 80.0, 3.0),
        _makeItem('dal', 120.0, 7.0),
      ];
      final raw = _totalCalMid(items);

      // Pass with balanced to simulate "no anchor" — same behaviour as null.
      final result = _runPass(items, PortionAnchor.balanced, svc);
      final adjusted = _totalCalMid(result);

      expect(adjusted, closeTo(raw, 1.0),
          reason: 'No eating style → 1.0× scalar across all items');
    });
  });
}

// Private helper reused by progressive tests (mirrors _dalCalInMeal for rice-heavy lists).
double _dalCalInMid(List<NutritionItem> passResult) {
  return passResult
      .where((i) => FoodRoleClassifier.classify(i.name) == FoodRole.accompaniment)
      .fold(0.0, (s, i) => s + i.calories.mid);
}
