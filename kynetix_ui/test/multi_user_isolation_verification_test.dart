import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/saved_meal_service.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/models/user_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = 'user-a-1111-uuid';
  const userB = 'user-b-2222-uuid';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
    await GlobalFoodService.instance.init(fetchRemote: false);
  });

  setUp(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  group('Multi-User Isolation & 4-Tier Precedence Tests', () {
    test('Zero cross-user data leakage across switch and logout', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // 1. User A logs in and records workout and meals
      await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);

      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Alice',
        age: 25,
        gender: 'female',
        height: 165.0,
        weight: 60.0,
        goal: 'Fat Loss',
        workoutDaysMin: 3,
        workoutDaysMax: 4,
      );
      await PersistenceService.saveProfile(ProfileService.instance.currentUserProfile!);

      final aliceDayLog = DayLog()
        ..targetCalories = 1800.0
        ..targetProtein = 140.0;
      aliceDayLog.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'oatmeal and berries',
          addedAt: DateTime(2026, 3, 5, 8, 0),
          section: MealSection.breakfast,
          dayOfWeek: 4,
          parsedFoods: const ['oatmeal', 'berries'],
          finalSavedInput: 'oatmeal and berries',
          result: NutritionResult(
            canonicalMeal: 'oatmeal and berries',
            items: const [],
            calories: const NutrientRange(min: 300, max: 300),
            protein: const NutrientRange(min: 10, max: 10),
            confidence: 0.9,
            warnings: const [],
            source: 'test',
            createdAt: DateTime(2026, 3, 5),
          ),
        ),
      );
      dayLogStore['2026-03-05'] = aliceDayLog;
      await PersistenceService.saveDayLogs();

      const aliceSplit = WorkoutSplit(
        id: 'alice_split',
        name: 'Upper Lower',
        days: [
          SplitDay(
            weekday: 1,
            name: 'Upper',
            exercises: [
              Exercise(
                id: 'ex_bench',
                name: 'Bench Press',
                muscleGroup: 'Chest',
                type: ExerciseType.barbellCompound,
              ),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSplit(aliceSplit);

      // Verify User A has active state
      expect(dayLogStore.containsKey('2026-03-05'), isTrue);
      expect(ProfileService.instance.currentUserProfile?.name, equals('Alice'));
      expect(WorkoutService.instance.split.name, equals('Upper Lower'));

      // 2. User A logs out (Hard Boundary)
      await UserSessionCoordinator.instance.clearAllUserServices();

      // Verify in-memory state is completely wiped
      expect(dayLogStore.isEmpty, isTrue, reason: 'dayLogStore must be empty after logout');
      expect(ProfileService.instance.currentUserProfile, isNull, reason: 'Profile must be null after logout');
      expect(WorkoutService.instance.isSetupDone, isFalse, reason: 'Workout split setup must be cleared after logout');
      expect(WorkoutService.instance.sessions.isEmpty, isTrue, reason: 'Workout sessions must be empty after logout');
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isFalse, reason: 'Guard must fail closed');

      // 3. User B logs in
      await UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);

      // User B must see ZERO data from User A
      expect(dayLogStore.isEmpty, isTrue, reason: 'User B must not see User A day logs');
      expect(ProfileService.instance.currentUserProfile, isNull, reason: 'User B must not see User A profile');
      expect(WorkoutService.instance.isSetupDone, isFalse, reason: 'User B must not see User A workout split');
      expect(WorkoutService.instance.sessions.isEmpty, isTrue, reason: 'User B must not see User A workout sessions');

      // User B creates their own profile and workout
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Bob',
        age: 28,
        gender: 'male',
        height: 178.0,
        weight: 78.0,
        goal: 'Strength',
        workoutDaysMin: 5,
        workoutDaysMax: 6,
      );
      await PersistenceService.saveProfile(ProfileService.instance.currentUserProfile!);

      const bobSplit = WorkoutSplit(
        id: 'bob_split',
        name: 'Bro Split',
        days: [
          SplitDay(
            weekday: 2,
            name: 'Legs',
            exercises: [
              Exercise(
                id: 'ex_squat',
                name: 'Squat',
                muscleGroup: 'Legs',
                type: ExerciseType.barbellCompound,
              ),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSplit(bobSplit);

      expect(ProfileService.instance.currentUserProfile?.name, equals('Bob'));
      expect(WorkoutService.instance.split.name, equals('Bro Split'));

      // 4. User B logs out
      await UserSessionCoordinator.instance.clearAllUserServices();

      // 5. User A logs back in
      await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);

      // User A's data must be completely preserved with ZERO contamination from User B
      expect(ProfileService.instance.currentUserProfile?.name, equals('Alice'));
      expect(ProfileService.instance.currentUserProfile?.goal, equals('Fat Loss'));
      expect(WorkoutService.instance.split.name, equals('Upper Lower'));
      expect(dayLogStore.containsKey('2026-03-05'), isTrue);
      expect(dayLogStore['2026-03-05']?.entriesFor(MealSection.breakfast).first.rawInput, equals('oatmeal and berries'));
    });

    test('4-Tier Food Precedence: User Override > Global Default > Library > AI', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Case 1: Standard User B has no override for "roti".
      // Global food service has canonical "roti" at 200 kcal / 6g protein.
      await UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);

      final searchResultsB = SavedMealService.instance.search('roti');
      expect(searchResultsB.isNotEmpty, isTrue);
      final rotiMatchB = searchResultsB.first;
      expect(rotiMatchB.title, equals('roti'));
      expect(rotiMatchB.calories, equals(200.0));
      expect(rotiMatchB.protein, equals(6.0));
      expect(rotiMatchB.mealType, equals(SavedMealType.globalDefault));

      // Pipeline estimation for User B: should resolve to Global Default (200 kcal)
      final estB = await NutritionPipeline.instance.estimateMeal('1 roti');
      expect(estB.calories.mid, equals(200.0));
      expect(estB.protein.mid, equals(6.0));

      // Case 2: User A has a custom override for "roti" (e.g. Grandma's small roti: 120 kcal / 4g protein).
      await UserSessionCoordinator.instance.initializeForUser(userA, prefsOverride: prefs);

      await UserNutritionMemory.instance.saveOverride(
        'roti',
        120.0,
        4.0,
        referenceUnit: 'piece',
        referenceQuantity: 1.0,
      );

      // User A searches for "roti" -> must return User A's override (120 kcal), NOT the global default (200 kcal)
      final searchResultsA = SavedMealService.instance.search('roti');
      expect(searchResultsA.isNotEmpty, isTrue);
      final rotiMatchA = searchResultsA.first;
      expect(rotiMatchA.calories, equals(120.0));
      expect(rotiMatchA.protein, equals(4.0));
      expect(rotiMatchA.mealType, equals(SavedMealType.rememberedFood));

      // Pipeline estimation for User A: must use User Override (120 kcal), NOT global default
      final estA = await NutritionPipeline.instance.estimateMeal('1 roti');
      expect(estA.calories.mid, equals(120.0));
      expect(estA.protein.mid, equals(4.0));

      // Case 3: Switch back to User B -> User B still gets Global Default (200 kcal), NOT User A's override!
      await UserSessionCoordinator.instance.initializeForUser(userB, prefsOverride: prefs);
      final estBAfter = await NutritionPipeline.instance.estimateMeal('1 roti');
      expect(estBAfter.calories.mid, equals(200.0));
      expect(estBAfter.protein.mid, equals(6.0));
    });

    test('Curator privacy: Private logs/workouts of curator account never leak to other users', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const curatorId = 'ff27ad41-1c6d-4f22-aa27-84ceb9a2a344'; // Dhruv
      const regularUserId = 'regular-user-3333-uuid';

      // Curator logs in and creates personal private day logs and workout
      await UserSessionCoordinator.instance.initializeForUser(curatorId, prefsOverride: prefs);

      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv (Curator)',
        age: 24,
        gender: 'male',
        height: 175.0,
        weight: 75.0,
        goal: 'Hypertrophy',
        workoutDaysMin: 4,
        workoutDaysMax: 5,
      );
      await PersistenceService.saveProfile(ProfileService.instance.currentUserProfile!);

      final curatorDayLog = DayLog()
        ..targetCalories = 2600.0
        ..targetProtein = 175.0;
      curatorDayLog.add(
        MealSection.dinner,
        MealEntry(
          rawInput: 'Private Curator Steak and Potatoes',
          addedAt: DateTime(2026, 3, 8, 20, 0),
          section: MealSection.dinner,
          dayOfWeek: 7,
          parsedFoods: ['steak', 'potatoes'],
          finalSavedInput: 'Private Curator Steak and Potatoes',
          result: NutritionResult(
            canonicalMeal: 'steak and potatoes',
            items: const [],
            calories: const NutrientRange(min: 850, max: 850),
            protein: const NutrientRange(min: 70, max: 70),
            confidence: 0.95,
            warnings: const [],
            source: 'test',
            createdAt: DateTime(2026, 3, 8),
          ),
        ),
      );
      dayLogStore['2026-03-08'] = curatorDayLog;
      await PersistenceService.saveDayLogs();

      // Regular user logs in
      await UserSessionCoordinator.instance.initializeForUser(regularUserId, prefsOverride: prefs);

      // Verify regular user does NOT see curator's private steak dinner in day logs or saved meal search
      expect(dayLogStore.containsKey('2026-03-08'), isFalse);
      expect(dayLogStore.values.any((d) => d.allEntries.any((e) => e.rawInput.contains('Curator Steak'))), isFalse);

      final searchResults = SavedMealService.instance.search('Curator Steak');
      expect(searchResults.isEmpty, isTrue, reason: 'Curators private meals must never appear in search for other users');

      // Regular user CAN see curated global defaults (e.g. roti)
      final globalSearch = SavedMealService.instance.search('roti');
      expect(globalSearch.isNotEmpty, isTrue);
      expect(globalSearch.first.mealType, equals(SavedMealType.globalDefault));
    });
  });
}
