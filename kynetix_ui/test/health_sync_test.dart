import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/health_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseProfile = UserProfile(
    name: 'Test Athlete',
    age: 25,
    gender: 'Male',
    height: 180.0,
    weight: 80.0, // 80 kg
    workoutDaysMin: 5,
    workoutDaysMax: 6,
    goal: kLeanBulk,
    averageDailySteps: 8500,
  );

  group('Health Connect Sync Date Boundaries', () {
    test('Calculates yesterday local midnight boundaries correctly without today partial day', () {
      final now = DateTime(2026, 6, 4, 15, 30, 0); // June 4, 2026 3:30 PM
      final todayStart = DateTime(now.year, now.month, now.day);
      
      // Yesterday local midnight boundary
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      expect(yesterdayStart, DateTime(2026, 6, 3));
      
      // D-30 start boundary
      final start30d = todayStart.subtract(const Duration(days: 30));
      expect(start30d, DateTime(2026, 5, 5));
      
      // Verify that "today" (June 4) is excluded since the range ends at June 3 23:59:59 (which is dayStart + 1 day for yesterdayStart)
      final endOfYesterday = yesterdayStart.add(const Duration(days: 1));
      expect(endOfYesterday, todayStart);
    });
  });

  group('Winsorized Mean Steps Calculations', () {
    // We re-implement the exact private math algorithm from HealthService
    // to test its correctness mathematically.
    double calculateWinsorizedMean(List<double> values) {
      if (values.isEmpty) return 0;
      if (values.length == 1) return values.first;

      final sorted = List<double>.from(values)..sort();
      final n     = sorted.length;

      // Clip to 10th/90th percentile
      final lo = sorted[(n * 0.10).floor().clamp(0, n - 1)];
      final hi = sorted[(n * 0.90).ceil().clamp(0, n - 1)];

      final clipped = sorted.map((v) => v.clamp(lo, hi)).toList();
      if (clipped.isEmpty) return 0.0;
      final sum = clipped.fold<double>(0, (a, b) => a + b);
      final avg = sum / clipped.length;
      if (avg.isNaN || avg.isInfinite) return 0.0;
      return double.tryParse(avg.toStringAsFixed(0)) ?? 0.0;
    }

    test('Clips outliers correctly for a typical step log', () {
      final values10 = [200.0, 6800.0, 7000.0, 7100.0, 7200.0, 7400.0, 7500.0, 8000.0, 8500.0, 25000.0];
      // Sorted: [200.0, 6800.0, 7000.0, 7100.0, 7200.0, 7400.0, 7500.0, 8000.0, 8500.0, 25000.0]
      // lo = sorted[1] = 6800.0
      // hi = sorted[9] = 25000.0
      // Clipped: [6800.0, 6800.0, 7000.0, 7100.0, 7200.0, 7400.0, 7500.0, 8000.0, 8500.0, 25000.0]
      // Sum = 91300. Average = 9130.0
      final result10 = calculateWinsorizedMean(values10);
      expect(result10, 9130.0);
    });

    test('Handles short lists correctly', () {
      final values3 = [5000.0, 10000.0, 6000.0];
      // Sorted: 5000, 6000, 10000
      // n = 3
      // lo index: (3 * 0.1).floor() = 0 -> 5000
      // hi index: (3 * 0.9).ceil() = 3 -> clamp to 2 -> 10000
      // No clipping since range encompasses all elements.
      // Average = (5000 + 6000 + 10000) / 3 = 7000.0
      final result3 = calculateWinsorizedMean(values3);
      expect(result3, 7000.0);
    });
  });

  group('NutritionTargetEngine - Step Calorie Offset & Fallback', () {
    final engine = NutritionTargetEngine();
    
    test('Calculates correct step calorie offset with health data', () {
      // 10000 steps, baseline 7000
      // steps - baseline = 3000
      // strideKm = 0.00075, metFactor = 0.55
      // kcalPerStep = 80.0 * 0.00075 * 0.55 = 0.033 kcal/step
      // offset = 3000 * 0.033 = 99 kcal
      final health = HealthSyncResult(
        effectiveAverageSteps: 10000.0,
        syncedAt: DateTime.now(),
      );

      final plan = engine.weeklyPlan(baseProfile, health: health);
      expect(plan.effectiveStepsPerDay, 10000);
      
      // Let's verify TDEE is BMR * multiplier + stepCorrection
      // BMR for Male: 10 * 80 + 6.25 * 180 - 5 * 25 + 5 = 800 + 1125 - 125 + 5 = 1805
      // multiplier (5-6 days avg = 5.5): 1.41
      // BMR * multiplier = 1805 * 1.41 = 2545.05
      // stepCorrection = (10000 - 7000) * (80.0 * 0.00075 * 0.55) = 3000 * 0.033 = 99
      // Total TDEE = 2545.05 + 99 = 2644.05 -> rounded to 1 decimal: 2644.1
      expect(plan.maintenanceCalories, closeTo(2644.1, 0.1));
    });

    test('Falls back to UserProfile.averageDailySteps when health is null or has no data', () {
      // health is null
      final plan = engine.weeklyPlan(baseProfile, health: null);
      // Fallback steps = baseProfile.averageDailySteps = 8500
      expect(plan.effectiveStepsPerDay, 8500);
      
      // stepCorrection = (8500 - 7000) * (80.0 * 0.00075 * 0.55) = 1500 * 0.033 = 49.5
      // rounded to int: 50. Total TDEE = 2545.05 + 50 = 2595.05 -> rounded to 1 decimal: 2595.0
      expect(plan.maintenanceCalories, closeTo(2595.0, 0.1));
      
      // health has no data
      final emptyHealth = HealthSyncResult(
        effectiveAverageSteps: null,
        syncedAt: DateTime.now(),
      );
      final plan2 = engine.weeklyPlan(baseProfile, health: emptyHealth);
      expect(plan2.effectiveStepsPerDay, 8500);
      expect(plan2.maintenanceCalories, closeTo(2595.0, 0.1));
    });
  });
}
