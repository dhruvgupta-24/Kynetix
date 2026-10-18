import 'package:flutter_test/flutter_test.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/meal_repeat_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;

void main() {
  MealEntry meal(String name, double kcal, DateTime at, [MealSection s = MealSection.lunch]) => MealEntry(
        rawInput: name,
        finalSavedInput: name,
        section: s,
        addedAt: at,
        dayOfWeek: at.weekday,
        parsedFoods: [name],
        result: NutritionResult(
          canonicalMeal: name,
          items: const [],
          calories: NutrientRange(min: kcal, max: kcal),
          protein: NutrientRange(min: 20, max: 20),
          confidence: 0.9,
          warnings: const [],
          source: 'test',
          createdAt: at,
        ),
      );

  final today = DateTime(2026, 10, 17);
  DateTime ago(int d, [int h = 13]) => DateTime(2026, 10, 17 - d, h);

  Map<String, DayLog> store() {
    final s = <String, DayLog>{};
    for (var d = 1; d <= 5; d++) {
      final log = DayLog()..add(MealSection.lunch, meal('dal rice', 520, ago(d)));
      if (d <= 2) log.add(MealSection.eveningSnack, meal('whey shake', 120, ago(d, 17), MealSection.eveningSnack));
      s[dateKey(ago(d))] = log;
    }
    s[dateKey(today)] = DayLog()..add(MealSection.breakfast, meal('poha', 250, DateTime(2026, 10, 17, 9)));
    return s;
  }

  test('recent foods: most logged first, nothing already logged today', () {
    final s = store();
    s[dateKey(today)]!.add(MealSection.lunch, meal('whey shake', 120, DateTime(2026, 10, 17, 10)));
    final recent = MealRepeatService.recentFoods(date: today, store: s);
    expect(recent.first.name, 'dal rice');
    expect(recent.first.times, 5);
    expect(recent.map((r) => r.name), isNot(contains('whey shake')));
  });

  test('yesterday returns the previous day', () {
    final y = MealRepeatService.yesterday(today, store: store());
    expect(y.map((e) => e.finalSavedInput), containsAll(['dal rice', 'whey shake']));
  });

  test('relog copies exact numbers as new entries; undo removes only the copies', () async {
    dayLogStore
      ..clear()
      ..addAll(store());
    final sources = MealRepeatService.yesterday(today);
    final added = await MealRepeatService.relog(today, sources, persist: false);
    final log = dayLogStore[dateKey(today)]!;
    expect(log.allEntries.length, 3);
    for (final e in added) {
      expect(sources.any((s) => s.addedAt == e.addedAt), isFalse, reason: 'fresh timestamps');
    }
    expect(added.map((e) => e.calMid), [520, 120]);
    await MealRepeatService.undo(today, added, persist: false);
    expect(log.allEntries.map((e) => e.finalSavedInput), ['poha']);
  });
}
