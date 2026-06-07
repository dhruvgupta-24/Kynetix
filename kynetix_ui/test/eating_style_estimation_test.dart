// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/eating_pattern_service.dart';
import 'package:kynetix/services/food_role_classifier.dart';

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
}
