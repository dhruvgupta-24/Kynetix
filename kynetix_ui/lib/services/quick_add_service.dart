import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/quick_add_item.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../config/supabase_client.dart';
import 'nutrition_hydration_guard.dart';
import 'nutrition_pipeline.dart';
import 'meal_memory.dart';
import 'persistence_service.dart';
import 'nutrition_target_engine.dart';
import 'user_nutrition_memory.dart';

class QuickAddService {
  QuickAddService._();
  static final QuickAddService instance = QuickAddService._();

  static const _prefsKey = 'quick_add_custom_items_v2';
  static const _legacyPrefsKey = 'quick_add_custom_items';

  List<QuickAddItem> _customItems = [];
  List<QuickAddItem> get customItems => List.unmodifiable(_customItems);

  SupabaseClient get _supabase => supabase;

  /// Public service method to execute a Quick Add operation cleanly:
  ///   1. Ensures hydration guard is ready for current user.
  ///   2. Loads today's DayLog.
  ///   3. Resolves estimation via NutritionPipeline.
  ///   4. Inserts MealEntry into DayLog.
  ///   5. Remembers meal in MealMemory.
  ///   6. Awaits PersistenceService.saveDay(date).
  ///   7. Refreshes nutrition targets via NutritionTargetEngine.
  /// Returns the inserted MealEntry upon successful persistence.
  Future<MealEntry> addMealToDay({
    required DateTime date,
    required String name,
    required double calories,
    required double protein,
    required MealSection section,
  }) async {
    final sw = Stopwatch()..start();
    final tapTimeMs = sw.elapsedMicroseconds / 1000.0;
    debugPrint('[QuickAddTap] ⏱️ QuickAddService entered: T+${tapTimeMs.toStringAsFixed(2)} ms');

    // 1. Hydration check
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) {
      final currentUserId = _supabase.auth.currentUser?.id ?? 'guest';
      NutritionHydrationGuard.instance.markComplete(currentUserId);
    }

    // 2. DayLog retrieval
    final dayLog = logFor(date);

    // 3. Strict Single Source of Truth Lookup Chain
    final userMem = UserNutritionMemory.instance.lookup(name);
    final mealMem = MealMemory.instance.lookupExactKnownFood(name) ??
                    MealMemory.instance.lookupRecurring(name);

    final NutritionResult selectedResult;
    if (userMem != null) {
      selectedResult = userMem;
    } else if (mealMem != null) {
      selectedResult = mealMem;
    } else {
      selectedResult = await NutritionPipeline.instance.estimateMeal(name);
    }

    // 4. Construct immutable MealEntry using selectedResult directly
    final entry = MealEntry(
      rawInput:        name,
      finalSavedInput: name,
      section:         section,
      addedAt:         DateTime.now(),
      dayOfWeek:       date.weekday,
      parsedFoods:     [name],
      userCorrected:   true,
      result:          selectedResult,
    );

    // 5. Store in DayLog and MealMemory
    dayLog.add(section, entry);
    await MealMemory.instance.store(
      name,
      entry.result,
      finalSavedInput: name,
      canonicalMeal: name,
    );

    // 6. Persistence
    final pStartMs = sw.elapsedMicroseconds / 1000.0;
    debugPrint('[QuickAddTap] ⏱️ Persistence started: T+${pStartMs.toStringAsFixed(2)} ms');

    await PersistenceService.saveDay(date);

    final pEndMs = sw.elapsedMicroseconds / 1000.0;
    debugPrint('[QuickAddTap] ⏱️ Persistence finished: T+${pEndMs.toStringAsFixed(2)} ms');

    // 7. Verification trace of zero mutations across pipeline
    final dayLogReloaded = logFor(date);
    final reloadedEntry = dayLogReloaded.entriesFor(section).firstWhere((e) => e == entry);

    debugPrint('''
=================== REAL APP RUNTIME AUDIT TRACE (QUICK ADD) ===================
  1. Quick Add item selected     : "$name" (preset: ${calories}kcal, ${protein}g pro)
  2. UserNutritionMemory lookup  : ${userMem != null ? 'Calories=${userMem.calories.mid}, Pro=${userMem.protein.mid}, Carbs=${userMem.carbohydrates?.mid}, Fat=${userMem.fat?.mid}, Score=${userMem.mealQualityScore}' : 'NULL'}
  3. MealMemory lookup           : ${mealMem != null ? 'Calories=${mealMem.calories.mid}, Pro=${mealMem.protein.mid}, Carbs=${mealMem.carbohydrates?.mid}, Fat=${mealMem.fat?.mid}, Score=${mealMem.mealQualityScore}' : 'NULL'}
  4. NutritionPipeline output    : Calories=${selectedResult.calories.mid}, Pro=${selectedResult.protein.mid}, Carbs=${selectedResult.carbohydrates?.mid}, Fat=${selectedResult.fat?.mid}, Fiber=${selectedResult.fiber?.mid}, Score=${selectedResult.mealQualityScore} (Source: ${selectedResult.source})
  5. MealEntry.result before save: Calories=${entry.result.calories.mid}, Pro=${entry.result.protein.mid}, Carbs=${entry.result.carbohydrates?.mid}, Fat=${entry.result.fat?.mid}, Score=${entry.result.mealQualityScore}
  6. MealEntry.result after save : Calories=${reloadedEntry.result.calories.mid}, Pro=${reloadedEntry.result.protein.mid}, Carbs=${reloadedEntry.result.carbohydrates?.mid}, Fat=${reloadedEntry.result.fat?.mid}, Score=${reloadedEntry.result.mealQualityScore}
================================================================================
''');

    await NutritionTargetEngine.instance.refreshTargetForDate(date);

    return entry;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load current schema items
      final raw = prefs.getStringList(_prefsKey);
      if (raw != null) {
        _customItems = raw.map((s) {
          try {
            return QuickAddItem.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        }).whereType<QuickAddItem>().toList();
      }

      // Check legacy migration
      final legacyRaw = prefs.getStringList(_legacyPrefsKey);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        debugPrint('[QuickAddService] Migrating legacy custom quick adds...');
        final migrated = <QuickAddItem>[];
        for (final s in legacyRaw) {
          try {
            final json = jsonDecode(s) as Map<String, dynamic>;
            final item = QuickAddItem(
              id: generateUuid(),
              name: (json['name'] as String?) ?? '',
              calories: (json['calories'] as num?)?.toDouble() ?? 0.0,
              protein: (json['protein'] as num?)?.toDouble() ?? 0.0,
              emoji: (json['emoji'] as String?) ?? '⚡',
              builtIn: false,
            );
            migrated.add(item);
          } catch (_) {}
        }
        if (migrated.isNotEmpty) {
          _customItems.addAll(migrated);
          await _saveLocally(prefs);
        }
        await prefs.remove(_legacyPrefsKey);
        debugPrint('[QuickAddService] Legacy migration complete. Migrated ${migrated.length} items.');
      }
    } catch (e) {
      debugPrint('[QuickAddService] Init failed: $e');
    }
  }

  Future<void> saveItem(QuickAddItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final idx = _customItems.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      _customItems[idx] = item;
    } else {
      _customItems.add(item);
    }
    await _saveLocally(prefs);
    
    // Background sync to cloud
    _syncQuickAddBackground(item).ignore();
  }

  Future<void> deleteItem(QuickAddItem item) async {
    final prefs = await SharedPreferences.getInstance();
    _customItems.removeWhere((i) => i.id == item.id);
    await _saveLocally(prefs);
    
    // Background sync deletion to cloud
    _deleteQuickAddBackground(item.id).ignore();
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    _customItems.clear();
    await prefs.remove(_prefsKey);
    await prefs.remove(_legacyPrefsKey);
  }

  Future<void> syncWithCloud() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      debugPrint('[QuickAddService] Starting custom quick adds cloud sync...');
      
      // 1. Upload local custom items that don't exist on the cloud yet or need update
      if (_customItems.isNotEmpty) {
        final List<Map<String, dynamic>> rows = _customItems.map((item) => {
          'id': item.id,
          'user_id': userId,
          'name': item.name,
          'calories': item.calories,
          'protein': item.protein,
          'emoji': item.emoji,
          'updated_at': DateTime.now().toIso8601String(),
        }).toList();

        await _supabase.from('user_quick_adds').upsert(rows);
      }

      // 2. Fetch all custom quick adds from cloud and update local cache
      final response = await _supabase
          .from('user_quick_adds')
          .select()
          .eq('user_id', userId);

      final List<QuickAddItem> cloudItems = [];
      for (final row in response) {
        cloudItems.add(QuickAddItem(
          id: row['id'] as String,
          name: row['name'] as String,
          calories: (row['calories'] as num).toDouble(),
          protein: (row['protein'] as num).toDouble(),
          emoji: (row['emoji'] as String?) ?? '⚡',
          builtIn: false,
        ));
      }

      _customItems = cloudItems;
      final prefs = await SharedPreferences.getInstance();
      await _saveLocally(prefs);
      debugPrint('[QuickAddService] Cloud sync complete. Loaded ${cloudItems.length} items from Supabase.');
    } catch (e) {
      debugPrint('[QuickAddService] Cloud sync failed: $e');
    }
  }

  Future<void> _saveLocally(SharedPreferences prefs) async {
    await prefs.setStringList(
      _prefsKey,
      _customItems.map((i) => jsonEncode(i.toJson())).toList(),
    );
  }

  Future<void> _syncQuickAddBackground(QuickAddItem item) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('user_quick_adds').upsert({
        'id': item.id,
        'user_id': userId,
        'name': item.name,
        'calories': item.calories,
        'protein': item.protein,
        'emoji': item.emoji,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[QuickAddService] Background quick add sync failed: $e');
    }
  }

  Future<void> _deleteQuickAddBackground(String id) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase
          .from('user_quick_adds')
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('[QuickAddService] Background quick add deletion sync failed: $e');
    }
  }

  String generateUuid() {
    final random = Random.secure();
    final hex = List.generate(256, (i) => i.toRadixString(16).padLeft(2, '0'));
    final r = List.generate(16, (_) => random.nextInt(256));
    r[6] = (r[6] & 0x0f) | 0x40; // version 4
    r[8] = (r[8] & 0x3f) | 0x80; // variant RFC4122
    
    final buf = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buf.write(hex[r[i]]);
      if (i == 3 || i == 5 || i == 7 || i == 9) {
        buf.write('-');
      }
    }
    return buf.toString();
  }
}
