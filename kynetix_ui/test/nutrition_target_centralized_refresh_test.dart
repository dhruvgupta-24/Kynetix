import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dayLogStore.clear();
    final profile = const UserProfile(
      name: 'Verification User',
      age: 25,
      gender: 'Male',
      height: 180,
      weight: 80,
      workoutDaysMin: 5,
      workoutDaysMax: 6,
      goal: 'Fat Loss',
    );
    ProfileService.instance.currentUserProfile = profile;
  });

  test('Comprehensive Runtime Trace & Verification Across All 9 Scenarios', () async {
    final profile = ProfileService.instance.currentUserProfile!;
    final today = DateTime(2026, 7, 23);
    final dk = dateKey(today);

    final log = logFor(today);

    print('\n==================== COMPREHENSIVE RUNTIME VERIFICATION TRACE ====================');

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 1: Gym → No Gym
    // ─────────────────────────────────────────────────────────────────────────
    log.gymDay = const GymDay(didGym: true);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s1EffBefore = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 1: Gym Day Initial ---');
    print('didGym: ${log.gymDay?.didGym}');
    print('stored targetCalories: ${log.targetCalories}');
    print('stored targetProtein: ${log.targetProtein}');
    print('effectiveTargetForDate: ${s1EffBefore.calories} kcal / ${s1EffBefore.protein} g');
    expect(s1EffBefore.calories, equals(2665.0));
    expect(s1EffBefore.protein, equals(148.0));

    // Toggle Gym -> No Gym
    log.gymDay = log.gymDay!.withGym(false);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s1EffAfter = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 1: Immediately After Gym -> No Gym ---');
    print('didGym: ${log.gymDay?.didGym}');
    print('stored targetCalories: ${log.targetCalories}');
    print('stored targetProtein: ${log.targetProtein}');
    print('effectiveTargetForDate: ${s1EffAfter.calories} kcal / ${s1EffAfter.protein} g');
    expect(s1EffAfter.calories, equals(2425.0));
    expect(s1EffAfter.protein, equals(132.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 2: No Gym → Gym
    // ─────────────────────────────────────────────────────────────────────────
    log.gymDay = log.gymDay!.withGym(true);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s2Eff = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 2: Toggle No Gym -> Gym ---');
    print('didGym: ${log.gymDay?.didGym}');
    print('stored targetCalories: ${log.targetCalories}');
    print('stored targetProtein: ${log.targetProtein}');
    print('effectiveTargetForDate: ${s2Eff.calories} kcal / ${s2Eff.protein} g');
    expect(s2Eff.calories, equals(2665.0));
    expect(s2Eff.protein, equals(148.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 3: Changing Today's Split
    // ─────────────────────────────────────────────────────────────────────────
    log.gymDay = null; // Clear manual toggle to test split-driven target
    final splitWithRestToday = WorkoutSplit(
      id: 'split_1',
      name: 'Custom Split',
      days: [
        const SplitDay(weekday: 4, name: 'Rest Day', exercises: []), // Thursday = Rest (exercises.isEmpty)
      ],
    );
    await WorkoutService.instance.saveSplit(splitWithRestToday);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s3EffRest = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 3: Changing Today\'s Split to Rest Day ---');
    print('stored targetCalories: ${log.targetCalories}');
    print('effectiveTargetForDate: ${s3EffRest.calories} kcal / ${s3EffRest.protein} g');
    expect(s3EffRest.calories, equals(2425.0));

    final splitWithTrainingToday = WorkoutSplit(
      id: 'split_1',
      name: 'Custom Split',
      days: [
        const SplitDay(weekday: 4, name: 'Push Heavy', exercises: [
          Exercise(id: 'bench', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound, defaultTargetSets: 4),
        ]), // Thursday = Training
      ],
    );
    await WorkoutService.instance.saveSplit(splitWithTrainingToday);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s3EffTrain = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('--- SCENARIO 3: Changing Today\'s Split to Push Heavy (Training) ---');
    print('stored targetCalories: ${log.targetCalories}');
    print('effectiveTargetForDate: ${s3EffTrain.calories} kcal / ${s3EffTrain.protein} g');
    expect(s3EffTrain.calories, equals(2665.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 4: Removing Today's Split
    // ─────────────────────────────────────────────────────────────────────────
    final emptySplit = const WorkoutSplit(id: 'empty', name: 'Empty', days: []);
    await WorkoutService.instance.saveSplit(emptySplit);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s4Eff = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 4: Removing Today\'s Split ---');
    print('stored targetCalories: ${log.targetCalories}');
    print('effectiveTargetForDate: ${s4Eff.calories} kcal / ${s4Eff.protein} g');
    expect(s4Eff.calories, equals(2425.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 5: Finishing a Workout
    // ─────────────────────────────────────────────────────────────────────────
    final finishedSession = WorkoutSession(
      id: 'session_1',
      date: today,
      splitDayName: 'Chest Heavy',
      entries: [
        ExerciseEntry(
          exercise: const Exercise(id: 'bench', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
          sets: [
            const SetEntry(weight: 100, reps: 5, setType: SetType.normal),
          ],
        ),
      ],
    );
    await WorkoutService.instance.saveSession(finishedSession);

    final s5Eff = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 5: Finishing a Workout ---');
    print('stored targetCalories: ${log.targetCalories}');
    print('effectiveTargetForDate: ${s5Eff.calories} kcal / ${s5Eff.protein} g');
    expect(s5Eff.calories, equals(2665.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 6: Discarding a Workout
    // ─────────────────────────────────────────────────────────────────────────
    await WorkoutService.instance.saveDraftSession(finishedSession);
    await WorkoutService.instance.clearDraftSession();
    // Delete session from active history to simulate discarding/removing session
    await WorkoutService.instance.deleteSession(finishedSession.id);

    final s6Eff = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 6: Discarding a Workout ---');
    print('stored targetCalories: ${log.targetCalories}');
    print('effectiveTargetForDate: ${s6Eff.calories} kcal / ${s6Eff.protein} g');
    expect(s6Eff.calories, equals(2425.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 7: Manual Calorie Target Override Preserved
    // ─────────────────────────────────────────────────────────────────────────
    log.gymDay = const GymDay(didGym: true, targetCaloriesOverride: 2800.0);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s7Init = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 7: Manual Override Active (2800 kcal) ---');
    print('effectiveTargetForDate: ${s7Init.calories} kcal');
    expect(s7Init.calories, equals(2800.0));

    // Toggle Gym -> No Gym with manual override active
    log.gymDay = log.gymDay!.withGym(false);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    final s7AfterToggle = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('--- SCENARIO 7: Toggle to No Gym (Manual Override Must Be Preserved) ---');
    print('effectiveTargetForDate: ${s7AfterToggle.calories} kcal');
    expect(s7AfterToggle.calories, equals(2800.0)); // Unchanged!

    // Clear override for remaining tests
    log.gymDay = const GymDay(didGym: false);
    await NutritionTargetEngine.instance.refreshTargetForDate(today, force: true);

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 8: App Restart & Persistence
    // ─────────────────────────────────────────────────────────────────────────
    final jsonStr = jsonEncode(log.toJson());
    final restoredLog = DayLog.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    dayLogStore[dk] = restoredLog;

    final s8Eff = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('\n--- SCENARIO 8: App Restart / Serialization Restore ---');
    print('restored targetCalories: ${restoredLog.targetCalories}');
    print('effectiveTargetForDate: ${s8Eff.calories} kcal / ${s8Eff.protein} g');
    expect(s8Eff.calories, equals(2425.0));

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO 9: Midnight / Day Rollover
    // ─────────────────────────────────────────────────────────────────────────
    final tomorrow = today.add(const Duration(days: 1));
    await NutritionTargetEngine.instance.refreshTargetForDate(tomorrow, force: true);
    final s9Eff = NutritionTargetEngine.instance.effectiveTargetForDate(tomorrow, profile: profile);

    print('\n--- SCENARIO 9: Midnight / Day Rollover (Tomorrow) ---');
    print('tomorrow targetCalories: ${s9Eff.calories} kcal');
    expect(s9Eff.calories, isNotNull);

    print('\n==================== ALL 9 VERIFICATION SCENARIOS PASSED ====================\n');
  });
}
