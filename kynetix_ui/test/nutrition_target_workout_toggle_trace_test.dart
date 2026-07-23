import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Runtime Trace: Nutrition Target Gym Toggle Behavior', () async {
    SharedPreferences.setMockInitialValues({});

    final profile = const UserProfile(
      name: 'Trace User',
      age: 25,
      gender: 'Male',
      height: 180,
      weight: 80,
      workoutDaysMin: 5,
      workoutDaysMax: 6,
      goal: 'Fat Loss',
    );
    ProfileService.instance.currentUserProfile = profile;

    final today = DateTime(2026, 7, 23);
    final dk = dateKey(today);

    // Initialize clean day log with Gym = true
    dayLogStore.clear();
    final log = DayLog();
    log.gymDay = const GymDay(didGym: true);
    
    // Calculate initial target and freeze onto DayLog as happens during initial load/save
    final initialTarget = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile, forceRecalculate: true);
    log.targetCalories = initialTarget.calories;
    log.targetProtein = initialTarget.protein;
    dayLogStore[dk] = log;

    print('\n==================== RUNTIME TRACE START ====================');
    print('--- INITIAL STATE (Gym: True) ---');
    print('didGym: ${log.gymDay?.didGym}');
    print('gymDay: ${log.gymDay}');
    print('targetCalories stored on DayLog: ${log.targetCalories}');
    print('targetProtein stored on DayLog: ${log.targetProtein}');
    
    final effTargetInit = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('effectiveTargetForDate result: ${effTargetInit.calories} kcal / ${effTargetInit.protein} g');
    
    final dayTargetInit = NutritionTargetEngine.instance.dayTarget(profile, isGymDay: log.gymDay?.didGym == true);
    print('dayTarget result: ${dayTargetInit.calories} kcal / ${dayTargetInit.protein} g');
    print('forceRecalculate: false');
    print('target source / label: ${effTargetInit.label} (${effTargetInit.note})');

    print('\n--- TOGGLE TO NO GYM (_toggleGym(false)) ---');
    // Execute toggle to No Gym (what _toggleGym(false) does)
    log.gymDay = log.gymDay!.withGym(false);
    
    print('IMMEDIATELY AFTER _toggleGym(false) (Before Persistence / Rebuild):');
    print('didGym: ${log.gymDay?.didGym}');
    print('gymDay: ${log.gymDay}');
    print('targetCalories stored on DayLog: ${log.targetCalories}');
    print('targetProtein stored on DayLog: ${log.targetProtein}');
    
    final effTargetAfterToggle = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('effectiveTargetForDate result: ${effTargetAfterToggle.calories} kcal / ${effTargetAfterToggle.protein} g');
    
    final dayTargetAfterToggle = NutritionTargetEngine.instance.dayTarget(profile, isGymDay: log.gymDay?.didGym == true);
    print('dayTarget result: ${dayTargetAfterToggle.calories} kcal / ${dayTargetAfterToggle.protein} g');
    print('target source / label: ${effTargetAfterToggle.label} (${effTargetAfterToggle.note})');

    print('\n--- TOGGLE BACK TO GYM (_toggleGym(true)) ---');
    log.gymDay = log.gymDay!.withGym(true);

    print('AFTER TOGGLE BACK TO GYM & REBUILD:');
    print('didGym: ${log.gymDay?.didGym}');
    print('targetCalories stored on DayLog: ${log.targetCalories}');
    print('targetProtein stored on DayLog: ${log.targetProtein}');
    final effTargetBackToGym = NutritionTargetEngine.instance.effectiveTargetForDate(today, profile: profile);
    print('effectiveTargetForDate result: ${effTargetBackToGym.calories} kcal / ${effTargetBackToGym.protein} g');
    print('==================== RUNTIME TRACE END ====================\n');
  });
}
