import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/health_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

MealEntry _meal(DateTime at, double calMin, double calMax, double proMin, double proMax,
    {NutrientRange? carbs, NutrientRange? fat, NutrientRange? fiber}) {
  return MealEntry(
    rawInput: 'Test meal',
    addedAt: at,
    section: MealSection.lunch,
    dayOfWeek: at.weekday,
    parsedFoods: const ['Test meal'],
    finalSavedInput: 'Test meal',
    result: NutritionResult(
      canonicalMeal: 'Test meal',
      items: const [],
      calories: NutrientRange(min: calMin, max: calMax),
      protein: NutrientRange(min: proMin, max: proMax),
      carbohydrates: carbs,
      fat: fat,
      fiber: fiber,
      confidence: 0.9,
      warnings: const [],
      source: 'test',
      createdAt: at,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = UserProfile(
    name: 'Widget User',
    age: 30,
    gender: 'Male',
    height: 178,
    weight: 78,
    workoutDaysMin: 4,
    workoutDaysMax: 5,
    goal: 'Fat Loss',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dayLogStore.clear();
    ProfileService.instance.currentUserProfile = profile;
  });

  tearDown(() {
    dayLogStore.clear();
    ProfileService.instance.currentUserProfile = null;
  });

  test('payload carries the date key of the day it describes, plus tomorrow', () {
    final now = DateTime(2026, 10, 17, 23, 58);
    final p = WidgetService.buildPayload(now: now, profile: profile);
    expect(p['v'], 3);
    expect(p['date_key'], '2026-10-17');
    expect(p['last_update_date'], '2026-10-17');
    expect(p['last_update_time'], '23:58');
    final next = p['next_day'] as Map;
    expect(next['date_key'], '2026-10-18');
    expect(next['calories_target'], isA<int>());
    expect(next['day_label'], isA<String>());
    // Month / year rollover is a real date, not "2026-10-32".
    final eom = WidgetService.buildPayload(now: DateTime(2026, 12, 31, 9), profile: profile);
    expect((eom['next_day'] as Map)['date_key'], '2027-01-01');
  });

  test('targets match the engine called the way the dashboard calls it (with health)', () {
    final now = DateTime(2026, 10, 17, 12);
    final health = HealthSyncResult(
      effectiveAverageSteps: 14000,
      averageDailySteps7d: 14000,
      averageDailySteps14d: 14000,
      averageDailySteps30d: 14000,
      syncedAt: now,
    );
    final engine = NutritionTargetEngine();
    final day = DateTime(2026, 10, 17);
    final withHealth = engine.effectiveTargetForDate(day, profile: profile, health: health);

    final p = WidgetService.buildPayload(now: now, profile: profile, health: health, engine: engine);
    expect(p['calories_target'], withHealth.calories.round());
    expect(p['protein_target'], withHealth.protein.round());
    expect(p['is_training_day'], withHealth.isTrainingDay);
    expect(p['day_label'], withHealth.label);

    // And it is not silently the no-health number when health would change it.
    final noHealth = engine.effectiveTargetForDate(day, profile: profile);
    if (noHealth.calories.round() != withHealth.calories.round()) {
      final pNo = WidgetService.buildPayload(now: now, profile: profile, engine: engine);
      expect(pNo['calories_target'], isNot(p['calories_target']));
    }
  });

  test('consumed is the sum of each entry rounded (same as dashboard displayKcal)', () {
    final now = DateTime(2026, 10, 17, 12);
    final log = logFor(DateTime(2026, 10, 17));
    // calMid 100.5 -> 101 (x3 = 303) ; summing first would give round(301.5) = 302.
    for (var i = 0; i < 3; i++) {
      log.add(MealSection.lunch, _meal(now, 100, 101, 10, 11)); // protein mid 10.5 -> 11
    }
    final p = WidgetService.buildPayload(now: now, profile: profile);
    expect(p['calories_consumed'], 303);
    expect(p['protein_consumed'], 33);
    expect(p['calories_consumed'], WidgetService.displayKcalFor(log));
    expect(p['calories_remaining'], (p['calories_target'] as int) - 303);
    expect(p['protein_remaining'], (p['protein_target'] as int) - 33);
  });

  test('carbs, fat and fiber: DayLog mid totals and the dashboard targets', () {
    final now = DateTime(2026, 10, 17, 12);
    final log = logFor(DateTime(2026, 10, 17));
    log.add(MealSection.lunch, _meal(now, 500, 520, 30, 32,
        carbs: const NutrientRange(min: 60, max: 70),
        fat: const NutrientRange(min: 15, max: 18),
        fiber: const NutrientRange(min: 8, max: 9)));
    log.add(MealSection.dinner, _meal(now, 300, 320, 20, 22,
        carbs: const NutrientRange(min: 30, max: 31))); // no fat / fiber data

    final engine = NutritionTargetEngine();
    final p = WidgetService.buildPayload(now: now, profile: profile, engine: engine);
    expect(p['carbs_consumed'], log.totalCarbsMid.round()); // 65 + 30.5
    expect(p['carbs_consumed'], 96);
    expect(p['fat_consumed'], 17); // 16.5 rounds up
    expect(p['fiber_consumed'], 9); // 8.5 rounds up

    // Targets: the dashboard's AdditionalMacrosCard (macroSplit + fiber rule).
    final t = engine.effectiveTargetForDate(DateTime(2026, 10, 17), profile: profile, log: log);
    final split = engine.macroSplit(t.calories, t.protein, profile: profile);
    expect(p['carbs_target'], split.carbs.round());
    expect(p['fat_target'], split.fat.round());
    expect(p['fiber_target'], (14.0 * t.calories / 1000).clamp(20.0, 60.0).round());
    expect(p['carbs_target'], greaterThan(0));
    expect(p['fat_target'], greaterThan(0));
    expect(p['fiber_target'], inInclusiveRange(20, 60));
  });

  test('next_day and every days[] entry carry carbs, fat and fiber targets', () {
    final engine = NutritionTargetEngine();
    final p = WidgetService.buildPayload(now: DateTime(2026, 10, 17, 9), profile: profile, engine: engine);
    final next = p['next_day'] as Map;
    final t = engine.effectiveTargetForDate(DateTime(2026, 10, 18), profile: profile, log: DayLog());
    final split = engine.macroSplit(t.calories, t.protein, profile: profile);
    expect(next['carbs_target'], split.carbs.round());
    expect(next['fat_target'], split.fat.round());
    expect(next['fiber_target'], WidgetService.fiberTargetFor(t.calories).round());
    final days = p['days'] as List;
    expect(days, hasLength(7));
    for (final d in days.cast<Map>()) {
      expect(d['carbs_target'], isA<int>());
      expect(d['fat_target'], isA<int>());
      expect(d['fiber_target'], isA<int>());
      // A day ahead has nothing eaten: no consumed keys at all.
      expect(d.containsKey('carbs_consumed'), isFalse);
    }
  });

  test('nothing logged: carbs, fat and fiber eaten are 0', () {
    final p = WidgetService.buildPayload(now: DateTime(2026, 10, 17, 9), profile: profile);
    expect(p['carbs_consumed'], 0);
    expect(p['fat_consumed'], 0);
    expect(p['fiber_consumed'], 0);
  });

  test('fiber target follows 14 g per 1,000 kcal, clamped to 20 to 60 g', () {
    expect(WidgetService.fiberTargetFor(2000), 28);
    expect(WidgetService.fiberTargetFor(1000), 20);
    expect(WidgetService.fiberTargetFor(5000), 60);
  });

  test('building the payload never creates a day log', () {
    WidgetService.buildPayload(now: DateTime(2026, 10, 17, 8), profile: profile);
    expect(dayLogStore.containsKey(dateKey(DateTime(2026, 10, 17))), isFalse);
    expect(dayLogStore.containsKey(dateKey(DateTime(2026, 10, 18))), isFalse);
  });

  test('payload is JSON-encodable', () {
    final p = WidgetService.buildPayload(now: DateTime(2026, 10, 17, 8), profile: profile);
    expect(() => jsonEncode(p), returnsNormally);
  });

  test('no profile clears the stored payload (widget shows "Open Kynetix")', () async {
    SharedPreferences.setMockInitialValues({'widget_data_v1': '{"date_key":"2026-10-16"}'});
    ProfileService.instance.currentUserProfile = null;
    await WidgetService.updateWidgetData();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('widget_data_v1'), isNull);
  });

  test('updateWidgetData stores today\'s payload', () async {
    await WidgetService.updateWidgetData();
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('widget_data_v1')!) as Map<String, dynamic>;
    final n = DateTime.now();
    final key = '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    expect(stored['date_key'], key);
    expect(stored['calories_target'], isA<int>());
  });
}
