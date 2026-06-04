import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/day_log.dart';
import '../models/workout_session.dart';
import '../models/workout_split.dart';
import '../services/workout_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/eating_pattern_service.dart';
import '../services/persistence_service.dart';
import '../services/quick_add_service.dart';

class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Hydrate local state from Supabase
  Future<void> hydrateFromCloud() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    debugPrint('[CloudSyncService] Starting cloud hydration for user: $userId');

    try {
      // Hydrate all components concurrently
      final results = await Future.wait([
        _supabase.from('day_logs').select(),
        _supabase.from('workout_sessions').select(),
        _supabase.from('user_nutrition_memory').select(),
        _supabase.from('user_eating_patterns').select().order('recorded_at', ascending: true),
        _supabase.from('user_meal_contexts').select().order('recorded_at', ascending: true),
        _supabase.from('workout_splits').select().maybeSingle(),
      ]);

      final dayLogsResp = results[0] as List<dynamic>;
      final workoutsResp = results[1] as List<dynamic>;
      final memoryResp = results[2] as List<dynamic>;
      final patternsResp = results[3] as List<dynamic>;
      final contextsResp = results[4] as List<dynamic>;
      final splitResp = results[5] as Map<String, dynamic>?;

      // 1. Process Day Logs
      for (final row in dayLogsResp) {
        final dateKey = row['date_key'] as String;
        final gymDayJson = row['gym_day_json'];
        final sectionsJson = row['sections_json'];

        final log = DayLog();
        if (gymDayJson != null) {
          log.gymDay = GymDay.fromJson(gymDayJson as Map<String, dynamic>);
        }
        if (sectionsJson != null) {
          final sectionsMap = sectionsJson as Map<String, dynamic>;
          for (final sectionName in sectionsMap.keys) {
            final sectionEnum = MealSection.values.firstWhere((e) => e.name == sectionName, orElse: () => MealSection.breakfast);
            final entries = sectionsMap[sectionName] as List<dynamic>;
            for (final entryJson in entries) {
              log.add(sectionEnum, MealEntry.fromJson(entryJson as Map<String, dynamic>));
            }
          }
        }
        dayLogStore[dateKey] = log;
      }
      // Re-save locally
      await PersistenceService.saveDayLogs();

      // 2. Process Workouts
      // Only merge if not already present
      bool updatedWorkouts = false;
      for (final row in workoutsResp) {
        final id = row['id'] as String;
        // Avoid overwriting local history if it exists, or just accept cloud as truth
        final exists = WorkoutService.instance.sessions.any((s) => s.id == id);
        if (!exists) {
          final session = WorkoutSession(
            id: row['id'],
            date: DateTime.parse(row['date'] as String),
            splitDayName: row['split_day_name'] as String,
            splitDayWeekday: row['split_day_weekday'] as int?,
            wasManuallySelected: row['was_manually_selected'] as bool? ?? false,
            notes: row['notes'] as String?,
            durationMinutes: row['duration_minutes'] as int?,
            entries: (row['entries_json'] as List<dynamic>?)?.map((e) => ExerciseEntry.fromJson(e)).toList() ?? [],
          );
          WorkoutService.instance.sessions.add(session);
          updatedWorkouts = true;
        }
      }
      if (updatedWorkouts) {
        // WorkoutService internally manages state, but we'll sort them.
        WorkoutService.instance.sessions.sort((a, b) => b.date.compareTo(a.date));
      }

      // 3. Process Nutrition Memory
      final cloudOverrides = <UserMealOverride>[];
      for (final row in memoryResp) {
        try {
          // Support both legacy (calories) and new (caloriesPerUnit) columns.
          // Supabase rows written by older clients only have 'calories'/'protein';
          // newer rows have 'calories_per_unit'/'protein_per_unit' etc.
          final calPerUnit = (row['calories_per_unit'] as num?)?.toDouble()
              ?? (row['calories'] as num?)?.toDouble()
              ?? 0.0;
          final proPerUnit = (row['protein_per_unit'] as num?)?.toDouble()
              ?? (row['protein'] as num?)?.toDouble()
              ?? 0.0;
          final carbPerUnit = (row['carbohydrates_per_unit'] as num?)?.toDouble();
          final fatPerUnit = (row['fat_per_unit'] as num?)?.toDouble();
          final fiberPerUnit = (row['fiber_per_unit'] as num?)?.toDouble();
          cloudOverrides.add(UserMealOverride(
            canonicalMeal:     row['canonical_meal'] as String,
            caloriesPerUnit:   calPerUnit,
            proteinPerUnit:    proPerUnit,
            carbohydratesPerUnit: carbPerUnit,
            fatPerUnit:        fatPerUnit,
            fiberPerUnit:      fiberPerUnit,
            referenceQuantity: (row['reference_quantity'] as num?)?.toDouble() ?? 1.0,
            referenceUnit:     row['reference_unit'] as String? ?? 'serving',
          ));
        } catch (e) {
          debugPrint('[CloudSyncService] Failed to parse memory row: $e');
        }
      }
      if (cloudOverrides.isNotEmpty) {
        await UserNutritionMemory.instance.mergeFromCloud(cloudOverrides);
      }

      // 4. Process Eating Patterns (correction records)
      if (patternsResp.isNotEmpty) {
        EatingPatternService.instance.mergeFromCloud(
          patternsResp.cast<Map<String, dynamic>>(),
        );
        await EatingPatternService.instance.save();
      }

      // 5. Process Meal Contexts
      if (contextsResp.isNotEmpty) {
        EatingPatternService.instance.mergeContextsFromCloud(
          contextsResp.cast<Map<String, dynamic>>(),
        );
        await EatingPatternService.instance.save();
      }

      // 6. Sync Quick Adds from Cloud
      await QuickAddService.instance.syncWithCloud();

      // 7. Process Workout Split & Custom Exercises
      if (splitResp != null) {
        final splitJson = splitResp['split_json'];
        final customExercisesJson = splitResp['custom_exercises_json'] as List<dynamic>?;
        final cloudUpdatedAtStr = splitResp['updated_at'] as String?;
        final cloudUpdatedAt = cloudUpdatedAtStr != null 
            ? DateTime.tryParse(cloudUpdatedAtStr) 
            : null;
        
        final localUpdatedAt = WorkoutService.instance.splitUpdatedAt;
        
        List<Exercise> customExercises = [];
        if (customExercisesJson != null) {
          try {
            customExercises = customExercisesJson
                .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (e) {
            debugPrint('[CloudSyncService] Error parsing custom exercises from cloud: $e');
          }
        }

        final isLocalNewer = WorkoutService.instance.isSetupDone && 
            cloudUpdatedAt != null && 
            localUpdatedAt.isAfter(cloudUpdatedAt);

        if (isLocalNewer) {
          debugPrint('[CloudSyncService] Local workout split is newer than cloud. Backing up split to cloud...');
          await syncWorkoutSplitBackground(
            WorkoutService.instance.split,
            WorkoutService.instance.customExercises,
          );
        } else if (splitJson != null) {
          try {
            final cloudSplit = WorkoutSplit.fromJson(splitJson as Map<String, dynamic>);
            await WorkoutService.instance.loadSplitAndCustomExercisesFromCloud(
              cloudSplit,
              customExercises,
              cloudUpdatedAt: cloudUpdatedAt,
            );
            debugPrint('[CloudSyncService] 🔄 Hydrated workout split and custom exercises from cloud');
          } catch (e) {
            debugPrint('[CloudSyncService] Error parsing cloud workout split: $e');
          }
        }
      } else if (WorkoutService.instance.isSetupDone) {
        debugPrint('[CloudSyncService] Cloud split empty but local setup done. Backing up split to cloud...');
        await syncWorkoutSplitBackground(
          WorkoutService.instance.split,
          WorkoutService.instance.customExercises,
        );
      }

      debugPrint('[CloudSyncService] Hydration completed.');
    } catch (e) {
      debugPrint('[CloudSyncService] Error during hydration: $e');
    }
  }

  /// Fire-and-forget sync for day logs
  Future<void> syncDayLogsBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final futures = <Future>[];
      for (final entry in dayLogStore.entries) {
        final dateKey = entry.key;
        final log = entry.value;

        futures.add(
          _supabase.from('day_logs').upsert({
            'user_id': userId,
            'date_key': dateKey,
            'gym_day_json': log.gymDay?.toJson(),
            'sections_json': {
              for (final s in MealSection.values)
                s.name: log.entriesFor(s).map((e) => e.toJson()).toList(),
            },
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id, date_key').catchError((e) {
            debugPrint('[CloudSyncService] Failed to sync day log $dateKey: $e');
            return {};
          })
        );
      }
      await Future.wait(futures);
    } catch (e) {
      debugPrint('[CloudSyncService] Background day log sync failed: $e');
    }
  }

  /// Fire-and-forget sync for a single completed workout
  Future<void> syncWorkoutBackground(WorkoutSession session) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('workout_sessions').upsert({
        'id': session.id,
        'user_id': userId,
        'date': session.date.toIso8601String(),
        'split_day_name': session.splitDayName,
        'split_day_weekday': session.splitDayWeekday,
        'was_manually_selected': session.wasManuallySelected,
        'entries_json': session.entries.map((e) => e.toJson()).toList(),
        'notes': session.notes,
        'duration_minutes': session.durationMinutes,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('[CloudSyncService] Background workout sync failed: $e');
    }
  }

  /// Fire-and-forget sync for the workout split and custom exercises
  Future<void> syncWorkoutSplitBackground(WorkoutSplit split, List<Exercise> customExercises) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('workout_splits').upsert({
        'user_id': userId,
        'split_json': split.toJson(),
        'custom_exercises_json': customExercises.map((e) => e.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
      debugPrint('[CloudSyncService] 🔄 Workout split and custom exercises synced successfully.');
    } catch (e) {
      debugPrint('[CloudSyncService] Background workout split sync failed: $e');
    }
  }

  /// Fire-and-forget sync for a nutrition memory override.
  /// Writes both new-schema columns (calories_per_unit etc.) and legacy
  /// aliases (calories, protein) so the Supabase row is readable by any
  /// client version.
  Future<void> syncMemoryBackground(UserMealOverride memory) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('user_nutrition_memory').upsert({
        'user_id':           userId,
        'canonical_meal':    memory.canonicalMeal,
        // New schema columns
        'calories_per_unit': memory.caloriesPerUnit,
        'protein_per_unit':  memory.proteinPerUnit,
        if (memory.carbohydratesPerUnit != null) 'carbohydrates_per_unit': memory.carbohydratesPerUnit,
        if (memory.fatPerUnit != null) 'fat_per_unit': memory.fatPerUnit,
        if (memory.fiberPerUnit != null) 'fiber_per_unit': memory.fiberPerUnit,
        'reference_quantity':memory.referenceQuantity,
        'reference_unit':    memory.referenceUnit,
        // Legacy aliases for backward compat with existing rows/clients
        'calories':          memory.caloriesPerUnit,
        'protein':           memory.proteinPerUnit,
        'updated_at':        DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, canonical_meal');
    } catch (e) {
      debugPrint('[CloudSyncService] Background memory sync failed: $e');
    }
  }

  /// Fire-and-forget sync for new eating pattern correction records.
  /// Uploads all locally stored records to the cloud (upsert by content).
  Future<void> syncEatingPatternsBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final records = EatingPatternService.instance.exportForCloudSync();
      if (records.isEmpty) return;

      // Insert in batches of 50 to avoid request size limits
      const batchSize = 50;
      for (int i = 0; i < records.length; i += batchSize) {
        final batch = records.sublist(i, (i + batchSize).clamp(0, records.length));
        final rows = batch.map((r) => {
          'user_id': userId,
          ...r,
        }).toList();
        // Use insert (not upsert) — duplicate check is done client-side during merge
        await _supabase.from('user_eating_patterns').upsert(
          rows,
          onConflict: 'user_id,recorded_at,target_role',
          ignoreDuplicates: true,
        );
      }
      debugPrint('[CloudSyncService] 🔄 Eating patterns synced (${records.length} records)');
    } catch (e) {
      debugPrint('[CloudSyncService] Eating pattern sync failed: $e');
    }
  }

  /// Fire-and-forget sync for new meal context records.
  Future<void> syncMealContextsBackground() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final contexts = EatingPatternService.instance.exportContextsForCloudSync();
      if (contexts.isEmpty) return;

      const batchSize = 50;
      for (int i = 0; i < contexts.length; i += batchSize) {
        final batch = contexts.sublist(i, (i + batchSize).clamp(0, contexts.length));
        final rows = batch.map((r) => {
          'user_id': userId,
          ...r,
        }).toList();
        await _supabase.from('user_meal_contexts').upsert(
          rows,
          onConflict: 'user_id,recorded_at',
          ignoreDuplicates: true,
        );
      }
      debugPrint('[CloudSyncService] 🔄 Meal contexts synced (${contexts.length} records)');
    } catch (e) {
      debugPrint('[CloudSyncService] Meal context sync failed: $e');
    }
  }
}
