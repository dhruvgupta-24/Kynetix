import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/kyno_brief_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = UserProfile(
    name: 'Brief',
    age: 24,
    gender: 'Male',
    height: 176,
    weight: 72,
    workoutDaysMin: 4,
    workoutDaysMax: 5,
    goal: kLeanBulk,
  );
  const bench = Exercise(id: 'bench', name: 'Bench press', muscleGroup: 'Chest', type: ExerciseType.dumbbell);

  MealEntry meal(String name, double kcal, double protein, DateTime at, MealSection s) => MealEntry(
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
          protein: NutrientRange(min: protein, max: protein),
          confidence: 0.9,
          warnings: const [],
          source: 'test',
          createdAt: at,
        ),
      );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mockAnonKey');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
    dayLogStore.clear();
    ProfileService.instance.currentUserProfile = profile;
  });

  test('brief carries targets, remaining, eating trend, lift trend and food options', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 13);
    // Two weeks of logs: paneer roti most days, whey often.
    for (var i = 0; i < 14; i++) {
      final d = today.subtract(Duration(days: i));
      final log = DayLog();
      log.add(MealSection.lunch, meal('paneer roti', 620, 32, d, MealSection.lunch));
      if (i.isEven) log.add(MealSection.eveningSnack, meal('1 scoop whey in water', 120, 24, d, MealSection.eveningSnack));
      dayLogStore[dateKey(d)] = log;
    }
    // Bench going up: 60 kg x 8 five weeks ago, 70 kg x 8 this week.
    for (final (daysAgo, kg) in [(35, 60.0), (28, 62.5), (14, 67.5), (3, 70.0)]) {
      await WorkoutService.instance.saveSession(WorkoutSession(
        id: 's$daysAgo',
        date: today.subtract(Duration(days: daysAgo)),
        splitDayName: 'Push',
        entries: [ExerciseEntry(exercise: bench, sets: [SetEntry(weight: kg, reps: 8)])],
      ));
    }

    final brief = KynoBriefService.instance.build(now: today);
    final j = brief.json;

    final t = j['today'] as Map<String, dynamic>;
    expect((t['target'] as Map)['kcal'], greaterThan(1500));
    expect((t['eaten'] as Map)['kcal'], 740);
    expect((t['remaining'] as Map)['kcal'], (t['target'] as Map)['kcal'] - 740);

    final lifts = (j['training'] as Map)['lifts'] as List;
    final b = lifts.firstWhere((l) => l['exercise'] == 'Bench press') as Map;
    expect(b['trend'], 'up');
    expect(b['change_pct'], greaterThan(5));

    final trend = j['eating_trend'] as Map;
    expect((trend['last_7_days'] as Map)['logged_days'], greaterThan(0));

    final food = j['food_options'] as Map;
    expect(food['diet_seen_in_log'], ['veg']);
    expect((food['from_their_log'] as List).isNotEmpty || (food['new_ideas'] as List).isNotEmpty, isTrue);

    expect(jsonEncode(j).length, lessThanOrEqualTo(KynoBriefService.maxChars));
    expect(brief.fuelPlan, isNotNull);
  });

  test('no data: still a valid, small brief', () {
    final brief = KynoBriefService.instance.build();
    expect(brief.json['today'], isNotNull);
    expect((brief.json['training'] as Map)['sessions_logged'], 0);
  });
}
