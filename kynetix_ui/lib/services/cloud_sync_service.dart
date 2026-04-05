import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/day_log.dart';
import '../models/workout_session.dart';
import '../services/workout_service.dart';
import '../services/user_nutrition_memory.dart';
import '../services/persistence_service.dart';

class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  final _supabase = Supabase.instance.client;

  /// Hydrate local state from Supabase
  Future<void> hydrateFromCloud() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    debugPrint('[CloudSyncService] Starting cloud hydration for user: $userId');

    try {
      // 1. Hydrate Day Logs
      final dayLogsResp = await _supabase.from('day_logs').select();
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

      // 2. Hydrate Workouts
      final workoutsResp = await _supabase.from('workout_sessions').select();
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
        // Force a save to local
        // Ideally WorkoutService exposes a method to save blindly, or we just rely on its own state.
      }

      // 3. Hydrate Nutrition Memory
      final memoryResp = await _supabase.from('user_nutrition_memory').select();
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
          cloudOverrides.add(UserMealOverride(
            canonicalMeal:     row['canonical_meal'] as String,
            caloriesPerUnit:   calPerUnit,
            proteinPerUnit:    proPerUnit,
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
}
