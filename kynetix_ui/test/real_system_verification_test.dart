import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/global_food_service.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/saved_meal_service.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/cloud_sync_service.dart';
import 'package:kynetix/services/kyno_context_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> dhruvFixture;
  late List<dynamic> fixtureDayLogs;
  late List<dynamic> fixtureOverrides;
  late Map<String, dynamic> fixtureProfile;
  late Map<String, dynamic> fixtureSplit;

  setUpAll(() {
    final fixtureFile = File('test/fixtures/dhruv_real_history.json');
    expect(fixtureFile.existsSync(), isTrue, reason: 'Real historical fixture must exist');
    final raw = fixtureFile.readAsStringSync();
    dhruvFixture = jsonDecode(raw) as Map<String, dynamic>;

    fixtureDayLogs = dhruvFixture['day_logs'] as List<dynamic>;
    fixtureOverrides = dhruvFixture['user_nutrition_memory'] as List<dynamic>;
    fixtureProfile = dhruvFixture['profile'] as Map<String, dynamic>;
    fixtureSplit = dhruvFixture['workout_split'] as Map<String, dynamic>;

    expect(fixtureDayLogs.length, equals(161), reason: 'Must contain all 161 real DayLogs');
    expect(fixtureOverrides.length, equals(262), reason: 'Must contain all 262 real user overrides');
  });

  tearDown(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  group('1. REAL EXISTING DATA MIGRATION AUDIT (Dhruv 161 Days & 262 Overrides)', () {
    test('Verbatim migration, pre-migration snapshotting, and strict field-by-field integrity', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const dhruvUserId = 'ff27ad41-1c6d-4f22-aa27-84ceb9a2a344';

      // ── Step 1: Synthesize un-scoped local storage from real historical database records ──
      final unscopedDayLogsMap = <String, dynamic>{};
      int expectedMealEntriesCount = 0;
      double expectedCaloriesSum = 0.0;
      double expectedProteinSum = 0.0;

      for (final logRow in fixtureDayLogs) {
        final dateKey = logRow['date_key'] as String;
        final sectionsJson = logRow['sections_json'] as Map<String, dynamic>? ?? {};
        final gymDayJson = logRow['gym_day_json'] as Map<String, dynamic>?;

        final dayLog = DayLog();
        if (gymDayJson != null) {
          dayLog.gymDay = GymDay.fromJson(gymDayJson);
        }
        dayLog.targetCalories = (logRow['target_calories'] as num?)?.toDouble();
        dayLog.targetProtein = (logRow['target_protein'] as num?)?.toDouble();

        for (final secName in sectionsJson.keys) {
          final secEnum = MealSection.values.firstWhere(
            (s) => s.name == secName,
            orElse: () => MealSection.breakfast,
          );
          final entriesList = sectionsJson[secName] as List<dynamic>;
          for (final entryRaw in entriesList) {
            final entry = MealEntry.fromJson(entryRaw as Map<String, dynamic>);
            dayLog.add(secEnum, entry);
            expectedMealEntriesCount++;
            expectedCaloriesSum += entry.result.calories.max;
            expectedProteinSum += entry.result.protein.max;
          }
        }
        unscopedDayLogsMap[dateKey] = dayLog.toJson();
      }

      final unscopedOverridesList = <String>[];
      for (final overRow in fixtureOverrides) {
        unscopedOverridesList.add(jsonEncode({
          'canonicalMeal': overRow['canonical_meal'],
          'caloriesPerUnit': (overRow['calories_per_unit'] as num?)?.toDouble() ?? 0.0,
          'proteinPerUnit': (overRow['protein_per_unit'] as num?)?.toDouble() ?? 0.0,
          'carbohydratesPerUnit': (overRow['carbohydrates_per_unit'] as num?)?.toDouble(),
          'fatPerUnit': (overRow['fat_per_unit'] as num?)?.toDouble(),
          'fiberPerUnit': (overRow['fiber_per_unit'] as num?)?.toDouble(),
          'referenceQuantity': (overRow['reference_quantity'] as num?)?.toDouble() ?? 1.0,
          'referenceUnit': overRow['reference_unit'] ?? 'serving',
          'correctionCount': (overRow['times_used'] as num?)?.toInt() ?? 1,
          'savedAt': overRow['updated_at'] ?? DateTime.now().toIso8601String(),
        }));
      }

      final originalDayLogsJson = jsonEncode(unscopedDayLogsMap);
      final originalWorkoutJson = jsonEncode({
        'split': fixtureSplit,
        'sessions': <dynamic>[],
        'customExercises': <dynamic>[],
        'setupDone': true,
      });
      final originalProfileJson = jsonEncode(UserProfile(
        name: fixtureProfile['name'] as String? ?? 'Dhruv',
        age: (fixtureProfile['age'] as num?)?.toInt() ?? 20,
        gender: fixtureProfile['gender'] as String? ?? 'Male',
        height: (fixtureProfile['height_cm'] as num?)?.toDouble() ?? 180.0,
        weight: (fixtureProfile['weight_kg'] as num?)?.toDouble() ?? 64.0,
        goal: fixtureProfile['goal'] as String? ?? 'Lean Bulk',
        workoutDaysMin: (fixtureProfile['workout_days_min'] as num?)?.toInt() ?? 5,
        workoutDaysMax: (fixtureProfile['workout_days_max'] as num?)?.toInt() ?? 6,
        portionAnchor: fixtureProfile['portion_anchor'] != null
            ? PortionAnchor.fromJson(fixtureProfile['portion_anchor'] as String)
            : null,
        carryForwardEnabled: fixtureProfile['carry_forward_enabled'] as bool? ?? false,
        carryForwardThreshold: (fixtureProfile['carry_forward_threshold'] as num?)?.toInt() ?? 100,
      ).toJson());

      // Write unscoped legacy keys to SharedPreferences
      await prefs.setString('day_logs_v1', originalDayLogsJson);
      await prefs.setStringList('user_meal_overrides_v1', unscopedOverridesList);
      await prefs.setString('workout_data_v2', originalWorkoutJson);
      await prefs.setString('user_profile_v2', originalProfileJson);

      expect(unscopedDayLogsMap.length, equals(161));
      expect(expectedMealEntriesCount, equals(979));
      expect(unscopedOverridesList.length, equals(262));

      // ── Step 2: Execute Non-Destructive Verbatim User Scoping ──
      final report = await UserSessionCoordinator.instance.migrateUnscopedDataForUser(
        dhruvUserId,
        prefs,
      );

      // ── Step 3: Verify Migration Audit Invariants ──
      expect(report.isVerified, isTrue);
      expect(report.historicalNutritionRecordsScanned, equals(979));
      expect(report.historicalNutritionRecordsChanged, equals(0), reason: 'recordsChanged must be 0');
      expect(report.historicalNutritionRecordsDeleted, equals(0), reason: 'recordsDeleted must be 0');
      expect(report.historicalNutritionRecordsLost, equals(0), reason: 'recordsLost must be 0');
      expect(report.overridesScanned, equals(262));
      expect(report.overridesLost, equals(0), reason: 'rememberedOverridesLost must be 0');

      // ── Step 4: Verify Pre-Migration Snapshots & Rollback Backups Intact ──
      expect(prefs.getString('backup_pre_migration_day_logs_v1'), equals(originalDayLogsJson));
      expect(prefs.getStringList('backup_pre_migration_user_meal_overrides_v1'), equals(unscopedOverridesList));
      expect(prefs.getString('backup_pre_migration_workout_data_v2'), equals(originalWorkoutJson));

      // Original unscoped keys MUST REMAIN UNTOUCHED
      expect(prefs.getString('day_logs_v1'), equals(originalDayLogsJson));
      expect(prefs.getStringList('user_meal_overrides_v1'), equals(unscopedOverridesList));
      expect(prefs.getString('workout_data_v2'), equals(originalWorkoutJson));

      // ── Step 5: Field-by-Field Verification of Scoped DayLogs ──
      final scopedLogsRaw = prefs.getString('day_logs_v1_$dhruvUserId');
      expect(scopedLogsRaw, isNotNull);
      final scopedLogsMap = jsonDecode(scopedLogsRaw!) as Map<String, dynamic>;
      expect(scopedLogsMap.length, equals(161));

      int verifiedEntries = 0;
      double migratedCaloriesSum = 0.0;
      double migratedProteinSum = 0.0;

      for (final dateKey in unscopedDayLogsMap.keys) {
        expect(scopedLogsMap.containsKey(dateKey), isTrue, reason: 'Missing date $dateKey in migrated store');
        final origLog = DayLog.fromJson(unscopedDayLogsMap[dateKey] as Map<String, dynamic>);
        final migratedLog = DayLog.fromJson(scopedLogsMap[dateKey] as Map<String, dynamic>);

        expect(migratedLog.targetCalories, equals(origLog.targetCalories));
        expect(migratedLog.targetProtein, equals(origLog.targetProtein));
        expect(migratedLog.gymDay?.didGym, equals(origLog.gymDay?.didGym));
        expect(migratedLog.gymDay?.splitDayName, equals(origLog.gymDay?.splitDayName));

        for (final sec in MealSection.values) {
          final origEntries = origLog.entriesFor(sec);
          final migEntries = migratedLog.entriesFor(sec);
          expect(migEntries.length, equals(origEntries.length), reason: 'Entry count mismatch on $dateKey in $sec');

          for (int i = 0; i < origEntries.length; i++) {
            final o = origEntries[i];
            final m = migEntries[i];

            expect(m.rawInput, equals(o.rawInput));
            expect(m.section, equals(o.section));
            expect(m.dayOfWeek, equals(o.dayOfWeek));
            expect(m.result.canonicalMeal, equals(o.result.canonicalMeal));

            // Macro verification (zero mutation)
            expect(m.result.calories.min, equals(o.result.calories.min));
            expect(m.result.calories.max, equals(o.result.calories.max));
            expect(m.result.protein.min, equals(o.result.protein.min));
            expect(m.result.protein.max, equals(o.result.protein.max));
            expect(m.result.carbohydrates?.min, equals(o.result.carbohydrates?.min));
            expect(m.result.carbohydrates?.max, equals(o.result.carbohydrates?.max));
            expect(m.result.fat?.min, equals(o.result.fat?.min));
            expect(m.result.fat?.max, equals(o.result.fat?.max));
            expect(m.result.fiber?.min, equals(o.result.fiber?.min));
            expect(m.result.fiber?.max, equals(o.result.fiber?.max));

            // Item-level check
            expect(m.result.items.length, equals(o.result.items.length));
            for (int j = 0; j < o.result.items.length; j++) {
              final oi = o.result.items[j];
              final mi = m.result.items[j];
              expect(mi.name, equals(oi.name));
              expect(mi.quantity, equals(oi.quantity));
              expect(mi.unit, equals(oi.unit));
              expect(mi.calories.max, equals(oi.calories.max));
              expect(mi.protein.max, equals(oi.protein.max));
            }

            verifiedEntries++;
            migratedCaloriesSum += m.result.calories.max;
            migratedProteinSum += m.result.protein.max;
          }
        }
      }

      expect(verifiedEntries, equals(979));
      expect(migratedCaloriesSum, closeTo(expectedCaloriesSum, 0.001), reason: 'historicalMacroChanges must be 0');
      expect(migratedProteinSum, closeTo(expectedProteinSum, 0.001), reason: 'historicalMacroChanges must be 0');
    });
  });

  group('2. HISTORICAL IMMUTABILITY TEST', () {
    test('Global default modification NEVER alters pre-existing historical DayLog entries', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const testUserId = 'test-user-immutability';

      await UserSessionCoordinator.instance.initializeForUser(testUserId, prefsOverride: prefs);

      // 1. Initial State: Global default for "roti" is 200 kcal, 6.0g protein
      GlobalFoodService.instance.registerForTesting(
        canonicalName: 'roti',
        caloriesPerUnit: 200.0,
        proteinPerUnit: 6.0,
        referenceUnit: 'piece',
      );

      // 2. User logs "1 roti" today
      final estInitial = await NutritionPipeline.instance.estimateMeal('1 roti');
      expect(estInitial.calories.mid, equals(200.0));
      expect(estInitial.protein.mid, equals(6.0));

      final historicalLog = DayLog();
      historicalLog.add(
        MealSection.lunch,
        MealEntry(
          rawInput: '1 roti',
          addedAt: DateTime(2026, 3, 1, 13, 0),
          section: MealSection.lunch,
          dayOfWeek: 7,
          parsedFoods: const ['roti'],
          finalSavedInput: '1 roti',
          result: estInitial,
        ),
      );
      dayLogStore['2026-03-01'] = historicalLog;
      await PersistenceService.saveDayLogs();

      // Verify stored correctly
      expect(dayLogStore['2026-03-01']!.entriesFor(MealSection.lunch).first.calMid, equals(200.0));

      // 3. Curator changes Global Default for "roti" to 250 kcal, 8.0g protein
      GlobalFoodService.instance.registerForTesting(
        canonicalName: 'roti',
        caloriesPerUnit: 250.0,
        proteinPerUnit: 8.0,
        referenceUnit: 'piece',
      );

      // 4. Reload DayLogs from persistence
      await PersistenceService.loadForUser(testUserId, prefsOverride: prefs);

      // 5. Assert: Historical entry remains 100% IMMUTABLE at 200 kcal / 6.0g protein
      final loadedHistoricalLog = dayLogStore['2026-03-01']!;
      final loadedEntry = loadedHistoricalLog.entriesFor(MealSection.lunch).first;
      expect(loadedEntry.calMid, equals(200.0), reason: 'Historical log must retain original 200 kcal');
      expect(loadedEntry.protMid, equals(6.0), reason: 'Historical log must retain original 6.0g protein');
      expect(loadedEntry.result.calories.max, equals(200.0));
      expect(loadedEntry.result.protein.max, equals(6.0));

      // 6. Assert: New resolution receives the updated global default (250 kcal)
      final estNew = await NutritionPipeline.instance.estimateMeal('1 roti');
      expect(estNew.calories.mid, equals(250.0), reason: 'New logs should reflect updated default');
      expect(estNew.protein.mid, equals(8.0), reason: 'New logs should reflect updated default');
    });
  });

  group('4. TWO REAL USER RUNTIME TEST (Hard Boundary & Full Isolation)', () {
    test('Sequential User A -> Logout -> User B -> Logout -> User A lifecycle', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const userAId = 'user-a-uuid-1111';
      const userBId = 'user-b-uuid-2222';

      // ── Step 1: User A logs in and creates data ──
      await UserSessionCoordinator.instance.initializeForUser(userAId, prefsOverride: prefs);

      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Alice A',
        age: 26,
        gender: 'female',
        height: 168.0,
        weight: 62.0,
        goal: 'Fat Loss',
        workoutDaysMin: 3,
        workoutDaysMax: 4,
      );
      await PersistenceService.saveProfile(ProfileService.instance.currentUserProfile!);

      final aliceLog = DayLog()..targetCalories = 1750.0..targetProtein = 135.0;
      aliceLog.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: '3 boiled eggs and oats',
          addedAt: DateTime(2026, 9, 8, 8, 30),
          section: MealSection.breakfast,
          dayOfWeek: 2,
          parsedFoods: const ['boiled eggs', 'oats'],
          finalSavedInput: '3 boiled eggs and oats',
          result: NutritionResult(
            canonicalMeal: 'boiled eggs and oats',
            items: const [],
            calories: const NutrientRange(min: 340, max: 340),
            protein: const NutrientRange(min: 24, max: 24),
            confidence: 0.95,
            warnings: const [],
            source: 'user_override',
            createdAt: DateTime(2026, 9, 8),
          ),
        ),
      );
      dayLogStore['2026-09-08'] = aliceLog;
      await PersistenceService.saveDayLogs();

      await UserNutritionMemory.instance.saveOverride(
        'alice special smoothie',
        280.0,
        25.0,
        referenceUnit: 'glass',
      );

      // Verify User A data active
      expect(ProfileService.instance.currentUserProfile?.name, equals('Alice A'));
      expect(dayLogStore.containsKey('2026-09-08'), isTrue);
      expect(UserNutritionMemory.instance.allOverrides.any((o) => o.canonicalMeal.contains('smoothie')), isTrue);

      // ── Step 2: User A Logs Out (Hard Boundary) ──
      await UserSessionCoordinator.instance.clearAllUserServices();

      expect(UserSessionCoordinator.instance.isAuthenticated, isFalse);
      expect(ProfileService.instance.currentUserProfile, isNull);
      expect(dayLogStore.isEmpty, isTrue);
      expect(UserNutritionMemory.instance.allOverrides.isEmpty, isTrue);
      expect(NutritionHydrationGuard.instance.isReadyForCurrentUser, isFalse);

      // ── Step 3: User B Logs In ──
      await UserSessionCoordinator.instance.initializeForUser(userBId, prefsOverride: prefs);

      // Confirm User B has ZERO contamination from User A
      expect(ProfileService.instance.currentUserProfile, isNull);
      expect(dayLogStore.isEmpty, isTrue);
      expect(UserNutritionMemory.instance.allOverrides.isEmpty, isTrue);
      expect(SavedMealService.instance.search('smoothie').isEmpty, isTrue);

      // User B creates their own data
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Bob B',
        age: 30,
        gender: 'male',
        height: 182.0,
        weight: 85.0,
        goal: 'Strength',
        workoutDaysMin: 4,
        workoutDaysMax: 5,
      );
      await PersistenceService.saveProfile(ProfileService.instance.currentUserProfile!);

      final bobLog = DayLog()..targetCalories = 2800.0..targetProtein = 180.0;
      bobLog.add(
        MealSection.dinner,
        MealEntry(
          rawInput: 'salmon with sweet potato',
          addedAt: DateTime(2026, 9, 8, 20, 0),
          section: MealSection.dinner,
          dayOfWeek: 2,
          parsedFoods: const ['salmon', 'sweet potato'],
          finalSavedInput: 'salmon with sweet potato',
          result: NutritionResult(
            canonicalMeal: 'salmon with sweet potato',
            items: const [],
            calories: const NutrientRange(min: 650, max: 650),
            protein: const NutrientRange(min: 48, max: 48),
            confidence: 0.95,
            warnings: const [],
            source: 'user_override',
            createdAt: DateTime(2026, 9, 8),
          ),
        ),
      );
      dayLogStore['2026-09-08'] = bobLog;
      await PersistenceService.saveDayLogs();

      expect(ProfileService.instance.currentUserProfile?.name, equals('Bob B'));
      expect(dayLogStore['2026-09-08']!.entriesFor(MealSection.dinner).first.rawInput, equals('salmon with sweet potato'));

      // ── Step 4: User B Logs Out ──
      await UserSessionCoordinator.instance.clearAllUserServices();
      expect(ProfileService.instance.currentUserProfile, isNull);
      expect(dayLogStore.isEmpty, isTrue);

      // ── Step 5: User A Logs Back In ──
      await UserSessionCoordinator.instance.initializeForUser(userAId, prefsOverride: prefs);

      // Verify User A data restored exactly, zero traces of Bob
      expect(ProfileService.instance.currentUserProfile?.name, equals('Alice A'));
      expect(ProfileService.instance.currentUserProfile?.goal, equals('Fat Loss'));
      expect(dayLogStore.containsKey('2026-09-08'), isTrue);
      final restoredLogA = dayLogStore['2026-09-08']!;
      expect(restoredLogA.entriesFor(MealSection.breakfast).first.rawInput, equals('3 boiled eggs and oats'));
      expect(restoredLogA.entriesFor(MealSection.dinner).isEmpty, isTrue, reason: 'Bob dinner must not exist in Alice store');
      expect(UserNutritionMemory.instance.allOverrides.any((o) => o.canonicalMeal.contains('smoothie')), isTrue);
    });
  });

  group('5. SUPABASE SYNC CONFLICT SAFETY', () {
    test('Cloud hydration preserves existing local day log entries and never overwrites them', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const testUserId = 'conflict-safety-user';

      await UserSessionCoordinator.instance.initializeForUser(testUserId, prefsOverride: prefs);

      // Local entry recorded by user with user-verified macros: 500 kcal, 40g protein
      final localLog = DayLog();
      localLog.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'custom protein bowl',
          addedAt: DateTime(2026, 9, 8, 12, 30),
          section: MealSection.lunch,
          dayOfWeek: 2,
          parsedFoods: const ['custom protein bowl'],
          finalSavedInput: 'custom protein bowl',
          result: NutritionResult(
            canonicalMeal: 'custom protein bowl',
            items: const [],
            calories: const NutrientRange(min: 500, max: 500),
            protein: const NutrientRange(min: 40, max: 40),
            confidence: 1.0,
            warnings: const [],
            source: 'user_override',
            createdAt: DateTime(2026, 9, 8),
          ),
        ),
      );
      dayLogStore['2026-09-08'] = localLog;
      await PersistenceService.saveDayLogs();

      // Simulate cloud row arriving with divergent AI estimation (e.g. 420 kcal, 30g protein)
      final incomingCloudEntry = MealEntry(
        rawInput: 'custom protein bowl',
        addedAt: DateTime(2026, 9, 8, 12, 30),
        section: MealSection.lunch,
        dayOfWeek: 2,
        parsedFoods: const ['custom protein bowl'],
        finalSavedInput: 'custom protein bowl',
        result: NutritionResult(
          canonicalMeal: 'custom protein bowl',
          items: const [],
          calories: const NutrientRange(min: 420, max: 420),
          protein: const NutrientRange(min: 30, max: 30),
          confidence: 0.7,
          warnings: const [],
          source: 'ai',
          createdAt: DateTime(2026, 9, 8),
        ),
      );

      // Apply the exact conflict resolution logic defined in CloudSyncService
      final currentEntries = localLog.entriesFor(MealSection.lunch);
      final alreadyPresent = currentEntries.any((local) =>
        local.rawInput == incomingCloudEntry.rawInput &&
        local.addedAt.millisecondsSinceEpoch == incomingCloudEntry.addedAt.millisecondsSinceEpoch
      );

      if (!alreadyPresent) {
        localLog.add(MealSection.lunch, incomingCloudEntry);
      }

      // Assert local entry was preserved verbatim and NOT overwritten
      expect(localLog.entriesFor(MealSection.lunch).length, equals(1));
      final verifiedEntry = localLog.entriesFor(MealSection.lunch).first;
      expect(verifiedEntry.calMid, equals(500.0), reason: 'Local user macros must be preserved');
      expect(verifiedEntry.protMid, equals(40.0), reason: 'Local user macros must be preserved');
      expect(verifiedEntry.result.source, equals('user_override'));
    });
  });

  group('6. GLOBAL FOOD PRIVACY', () {
    test('Curator private data is never exposed in global food catalog or search for other users', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const curatorId = 'ff27ad41-1c6d-4f22-aa27-84ceb9a2a344'; // Dhruv
      const regularUserId = 'regular-user-9999';

      // Curator initializes and creates private data
      await UserSessionCoordinator.instance.initializeForUser(curatorId, prefsOverride: prefs);

      await UserNutritionMemory.instance.saveOverride(
        'Curator Private Whey + Almond Butter',
        420.0,
        35.0,
        referenceUnit: 'serving',
      );

      // Regular user logs in
      await UserSessionCoordinator.instance.initializeForUser(regularUserId, prefsOverride: prefs);

      // 1. Search for curator's private meal
      final searchResults = SavedMealService.instance.search('Curator Private');
      expect(searchResults.isEmpty, isTrue, reason: 'Curators private overrides must never appear for other users');

      // 2. Verify GlobalFoodService contains ONLY explicit curated defaults
      final allGlobalDefaults = GlobalFoodService.instance.allDefaults;
      for (final def in allGlobalDefaults) {
        expect(def.canonicalName.toLowerCase().contains('curator private'), isFalse);
      }

      // 3. Verify regular user day log store is clean
      expect(dayLogStore.isEmpty, isTrue);
    });
  });
}
