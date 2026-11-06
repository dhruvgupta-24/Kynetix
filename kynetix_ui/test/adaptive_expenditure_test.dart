import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/adaptive_expenditure_service.dart';
import 'package:kynetix/services/body_metrics_service.dart';

// What the user really burns, from intake and the weight trend.
void main() {
  final now = DateTime(2026, 11, 6, 10);

  MealEntry meal(double kcal, DateTime at) => MealEntry(
        rawInput: 'x',
        finalSavedInput: 'x',
        section: MealSection.lunch,
        addedAt: at,
        dayOfWeek: at.weekday,
        parsedFoods: const [],
        result: NutritionResult(
          canonicalMeal: 'x',
          items: const [],
          calories: NutrientRange(min: kcal, max: kcal),
          protein: const NutrientRange(min: 100, max: 100),
          confidence: 0.9,
          warnings: const [],
          source: 'test',
          createdAt: at,
        ),
      );

  /// [days] logged days of [kcal] ending yesterday.
  Map<String, DayLog> logs(int days, double kcal) => {
        for (var i = 1; i <= days; i++)
          dateKey(now.subtract(Duration(days: i))): DayLog()
            ..add(MealSection.lunch, meal(kcal, now.subtract(Duration(days: i)))),
      };

  /// Weigh-ins every [every] days over the last 27 days, trend moving
  /// linearly by [totalKg].
  WeightTrend trend(double totalKg, {int every = 3}) {
    final pts = <WeightPoint>[];
    for (var d = 27; d >= 1; d -= every) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      final kg = 80 + totalKg * (27 - d) / 26;
      pts.add(WeightPoint(day, kg, kg, manual: true));
    }
    return WeightTrend(pts);
  }

  test('not ready without enough logged days or weigh-ins', () {
    final e = AdaptiveExpenditureService.estimate(formulaKcal: 2500, logs: logs(5, 2000), trend: trend(0), now: now);
    expect(e.ready, isFalse);
    expect(e.blendedKcal, 2500);
    expect(e.missing, contains('more logged days'));
  });

  test('steady weight means intake is maintenance', () {
    final e = AdaptiveExpenditureService.estimate(formulaKcal: 2500, logs: logs(28, 2200), trend: trend(0), now: now);
    expect(e.ready, isTrue);
    expect(e.observedKcal, closeTo(2200, 1));
    // Blended toward 2200 by the confidence, never past it.
    expect(e.blendedKcal, lessThan(2500));
    expect(e.blendedKcal, greaterThanOrEqualTo(2200));
    expect(e.explanation, contains('held steady'));
  });

  test('losing weight on 2000 kcal means burning more than 2000', () {
    // About 1 kg down over 24 days: 7700 / 24 ≈ 320 kcal a day of deficit.
    final e = AdaptiveExpenditureService.estimate(formulaKcal: 2300, logs: logs(28, 2000), trend: trend(-1), now: now);
    expect(e.observedKcal!, greaterThan(2250));
    expect(e.observedKcal!, lessThan(2400));
    expect(e.explanation, contains('dropped'));
  });

  test('wild data is kept within 30% of the formula', () {
    final e = AdaptiveExpenditureService.estimate(formulaKcal: 2000, logs: logs(28, 4000), trend: trend(0), now: now);
    expect(e.observedKcal, closeTo(2600, 1));
    expect(e.clamped, isTrue);
  });

  test('half-logged days are left out', () {
    final l = logs(28, 2200);
    // Ten days with a single 300 kcal snack logged: incomplete, not counted.
    for (var i = 1; i <= 10; i++) {
      l[dateKey(now.subtract(Duration(days: i)))] = DayLog()..add(MealSection.lunch, meal(300, now.subtract(Duration(days: i))));
    }
    final e = AdaptiveExpenditureService.estimate(formulaKcal: 2500, logs: l, trend: trend(0), now: now);
    expect(e.loggedDays, 18);
    expect(e.avgIntakeKcal, closeTo(2200, 1));
  });

  test('applied value is null unless switched on', () {
    final svc = AdaptiveExpenditureService.instance;
    svc.setForTesting(enabled: false, applied: 2100);
    expect(svc.appliedKcal, isNull);
    svc.setForTesting(enabled: true, applied: 2100);
    expect(svc.appliedKcal, 2100);
    svc.setForTesting(enabled: false, applied: null);
  });
}
