import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

MealEntry _meal(String name, DateTime at, {double kcal = 400}) => MealEntry(
      rawInput: name,
      finalSavedInput: name,
      section: MealSection.lunch,
      addedAt: at,
      dayOfWeek: at.weekday,
      parsedFoods: [name],
      result: NutritionResult.createCustom(
        canonicalMeal: name,
        calories: kcal,
        protein: 30,
        carbohydrates: 40,
        fat: 10,
        fiber: 5,
        source: 'test',
        items: [
          NutritionItem(
            name: name,
            quantity: 1,
            unit: 'serving',
            estimated: false,
            mode: EstimationMode.directQuantity,
            calories: NutrientRange(min: kcal, max: kcal),
            protein: const NutrientRange(min: 30, max: 30),
          ),
        ],
      ),
    );

void _seedDays(int count) {
  final start = DateTime(2026, 1, 1);
  for (int d = 0; d < count; d++) {
    final date = start.add(Duration(days: d));
    final log = DayLog()..add(MealSection.lunch, _meal('meal "$d" ü', date));
    log.targetCalories = 2000;
    log.targetProtein = 140;
    dayLogStore[dateKey(date)] = log;
  }
}

String _referenceEncode() =>
    jsonEncode({for (final e in dayLogStore.entries) e.key: e.value.toJson()});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSessionCoordinator.instance.clearAllUserServices();
    await WorkoutService.instance.init();
    await PersistenceService.load();
    dayLogStore.clear();
    PersistenceService.postSaveEffectsDelay = Duration.zero;
  });

  test('encoder output is byte-identical to jsonEncode of the store', () {
    _seedDays(12);
    expect(encodeDayLogsForTest(Map.of(dayLogStore)), equals(_referenceEncode()));
  });

  test('isolate-encoded write (large store) persists byte-identical JSON', () async {
    _seedDays(PersistenceService.isolateEncodeThreshold + 20);
    await PersistenceService.saveDayLogs();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('day_logs_v1'), equals(_referenceEncode()));
  });

  test('a burst of saves coalesces without losing any meal', () async {
    _seedDays(5);
    final day = DateTime(2026, 1, 3);
    final futures = <Future<void>>[];
    for (int i = 0; i < 10; i++) {
      logFor(day).add(MealSection.dinner, _meal('burst $i', day.add(Duration(minutes: i))));
      futures.add(PersistenceService.saveDayLogs());
    }
    await Future.wait(futures);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('day_logs_v1')!) as Map<String, dynamic>;
    final restored = DayLog.fromJson(stored[dateKey(day)] as Map<String, dynamic>);
    expect(restored.entriesFor(MealSection.dinner).length, 10);
    expect(prefs.getString('day_logs_v1'), equals(_referenceEncode()));
  });

  test('a queued write keeps the owner captured at call time across a user switch', () async {
    await PersistenceService.setCachedOwnerId('user_a');
    _seedDays(3);
    final aliceSave = PersistenceService.saveDayLogs(); // queued for user_a
    final aliceJson = _referenceEncode();

    // Switch the in-memory store to another account before the write runs.
    dayLogStore.clear();
    await PersistenceService.setCachedOwnerId('user_b');
    final bobDay = DateTime(2026, 5, 5);
    logFor(bobDay).add(MealSection.lunch, _meal('bob meal', bobDay));
    final bobSave = PersistenceService.saveDayLogs();
    await Future.wait([aliceSave, bobSave]);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('day_logs_v1_user_a'), equals(aliceJson));
    final bob = jsonDecode(prefs.getString('day_logs_v1_user_b')!) as Map<String, dynamic>;
    expect(bob.keys, [dateKey(bobDay)]);
  });

  test('flushForSessionEnd lands un-awaited saves before logout clears memory', () async {
    await PersistenceService.setCachedOwnerId('user_c');
    _seedDays(4);
    PersistenceService.saveDay(DateTime(2026, 1, 2)).ignore(); // optimistic UI path
    await UserSessionCoordinator.instance.clearAllUserServices();

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('day_logs_v1_user_c')!) as Map<String, dynamic>;
    expect(stored.length, 4);
  });

  test('deferred insights recompute is applied before any reader sees reports', () async {
    PersistenceService.postSaveEffectsDelay = const Duration(seconds: 30);
    NutritionHydrationGuard.instance.markComplete('guest');
    const profile = UserProfile(
      name: 'T', age: 25, gender: 'Male', height: 175, weight: 75,
      workoutDaysMin: 3, workoutDaysMax: 3, goal: 'Fat Loss',
    );
    ProfileService.instance.currentUserProfile = profile;
    final day = DateTime(2026, 6, 3);
    for (int i = 1; i <= 7; i++) {
      final d = DateTime(2026, 6, i);
      logFor(d).add(MealSection.lunch, _meal('eggs', d));
    }
    await PersistenceService.saveDay(day);
    expect(InsightsReportService.instance.hasPendingRecompute, isTrue);

    final report = InsightsReportService.instance.weeklyFor('2026-W23');
    expect(InsightsReportService.instance.hasPendingRecompute, isFalse);
    expect(report, isNotNull);
    expect(report!.loggedDaysCount, 7);

    await PersistenceService.flushAll();
    PersistenceService.postSaveEffectsDelay = Duration.zero;
  });
}
