import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/workout_service.dart';

/// One answer to "what is today, training-wise?" for the Nutrition day screen,
/// the Train tab and the targets: a logged session > the user's pick > split.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bench = Exercise(id: 'bench', name: 'Bench press', muscleGroup: 'Chest', type: ExerciseType.dumbbell);
  const row = Exercise(id: 'row', name: 'Barbell row', muscleGroup: 'Back', type: ExerciseType.dumbbell);

  final today = DateTime.now();
  final todayWeekday = today.weekday;

  WorkoutSplit splitWithTodayAs(String name) => WorkoutSplit(
        id: 'ppl',
        name: 'PPL',
        days: [
          SplitDay(weekday: todayWeekday, name: name, exercises: const [bench]),
          SplitDay(weekday: todayWeekday % 7 + 1, name: 'Pull', exercises: const [row]),
        ],
      );

  WorkoutSession sessionNamed(String name) => WorkoutSession(
        id: 'session-$name',
        date: today,
        splitDayName: name,
        entries: [
          ExerciseEntry(exercise: name == 'Pull' ? row : bench, sets: [const SetEntry(weight: 60, reps: 8)]),
        ],
      );

  const profile = UserProfile(
    name: 'Sync',
    age: 26,
    gender: 'Male',
    height: 178,
    weight: 74,
    workoutDaysMin: 4,
    workoutDaysMax: 5,
    goal: kLeanBulk,
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
    await WorkoutService.instance.saveSplit(splitWithTodayAs('Push'));
  });

  test('with no pick the split decides, on both tabs', () {
    final plan = WorkoutService.instance.planFor(today);
    expect(plan.source, DayPlanSource.split);
    expect(plan.isTraining, isTrue);
    expect(plan.name, 'Push');
    expect(WorkoutService.instance.todaySplitDay?.name, 'Push');
  });

  test('saying No on the day screen makes Train show a rest day', () {
    logFor(today).gymDay = const GymDay.unpicked().withGym(false);
    final plan = WorkoutService.instance.planFor(today);
    expect(plan.isRest, isTrue);
    expect(plan.source, DayPlanSource.manual);
    expect(WorkoutService.instance.todaySplitDay, isNull);
    final target = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile, forceRecalculate: true);
    expect(target.isTrainingDay, isFalse);
    expect(target.label, 'Rest Day');
  });

  test('picking Pull on the day screen makes Train show Pull', () {
    logFor(today).gymDay = const GymDay.unpicked().withUserOverride(splitName: 'Pull', type: WorkoutType.pull);
    expect(WorkoutService.instance.todaySplitDay?.name, 'Pull');
    expect(WorkoutService.instance.planFor(today).label, 'Pull day');
  });

  test('a pick outside the split becomes a custom session on Train', () {
    logFor(today).gymDay = const GymDay.unpicked().withUserOverride(splitName: 'Cardio', type: WorkoutType.cardio);
    final day = WorkoutService.instance.todaySplitDay;
    expect(day?.name, 'Cardio');
  });

  test('a logged workout wins and is written to the day', () async {
    logFor(today).gymDay = const GymDay.unpicked().withGym(false);
    await WorkoutService.instance.saveSession(sessionNamed('Pull'));
    final plan = WorkoutService.instance.planFor(today);
    expect(plan.source, DayPlanSource.session);
    expect(plan.name, 'Pull');
    final gym = dayLogStore[dateKey(today)]!.gymDay!;
    expect(gym.didGym, isTrue);
    expect(gym.splitDayName, 'Pull');
    expect(gym.manual, isTrue);
  });

  test('deleting the only workout puts the day back on the split', () async {
    await WorkoutService.instance.saveSession(sessionNamed('Pull'));
    await WorkoutService.instance.deleteSession('session-Pull');
    final plan = WorkoutService.instance.planFor(today);
    expect(plan.source, DayPlanSource.split);
    expect(plan.name, 'Push');
  });

  test('a calorie override alone does not decide the training day', () {
    logFor(today).gymDay = const GymDay.unpicked(targetCaloriesOverride: 2400);
    final plan = WorkoutService.instance.planFor(today);
    expect(plan.source, DayPlanSource.split);
    expect(plan.isTraining, isTrue);
  });

  test('rest clears the split name so a rest day is never "Push day"', () {
    final gym = const GymDay.unpicked()
        .withUserOverride(splitName: 'Push', type: WorkoutType.push)
        .withGym(false);
    expect(gym.splitDayName, isNull);
  });

  test('records saved before the flag existed still count as a pick', () {
    final legacy = GymDay.fromJson(jsonDecode('{"didGym": false}') as Map<String, dynamic>);
    expect(legacy.manual, isTrue);
    final roundTrip = GymDay.fromJson(const GymDay.unpicked(targetCaloriesOverride: 2000).toJson());
    expect(roundTrip.manual, isFalse);
    expect(roundTrip.targetCaloriesOverride, 2000);
  });
}
