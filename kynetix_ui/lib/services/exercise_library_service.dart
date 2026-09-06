import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/exercise_definition.dart';
import '../models/workout_split.dart';
import 'exercise_search_engine.dart';
import 'exercise_display_enhancer.dart';

/// Singleton service managing the comprehensive 1,300+ exercise library,
/// fast multi-token fuzzy search, dynamic categorical & equipment filters,
/// and custom exercise indexing.
class ExerciseLibraryService extends ChangeNotifier {
  ExerciseLibraryService._();
  static final ExerciseLibraryService instance = ExerciseLibraryService._();

  static const String _kAssetPath = 'assets/data/exercises_library.json';

  bool _initialized = false;
  bool get isInitialized => _initialized;

  List<ExerciseDefinition> _allDefinitions = [];
  final Map<String, ExerciseDefinition> _byId = {};
  final List<ExerciseDefinition> _customDefinitions = [];

  List<ExerciseDefinition> get allDefinitions {
    if (!_initialized && _allDefinitions.isEmpty) {
      _loadFallbackSync();
    }
    return List.unmodifiable([..._customDefinitions, ..._allDefinitions]);
  }

  /// Initialize and load the 1,300+ exercise database into memory.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final jsonString = await rootBundle.loadString(_kAssetPath);
      final List<dynamic> parsed = jsonDecode(jsonString) as List<dynamic>;
      _allDefinitions = parsed.map((item) {
        final def = ExerciseDefinition.fromJson(item as Map<String, dynamic>);
        final displayName = ExerciseDisplayEnhancer.deriveDisplayName(def.canonicalName, def.equipment);
        final enhancedAliases = ExerciseDisplayEnhancer.buildEnhancedAliases(def);
        return ExerciseDefinition(
          id: def.id,
          name: def.canonicalName,
          canonicalName: def.canonicalName,
          displayName: displayName,
          category: def.category,
          bodyPart: def.bodyPart,
          equipment: def.equipment,
          equipmentGroup: def.equipmentGroup,
          targetMuscle: def.targetMuscle,
          muscleGroup: def.muscleGroup,
          secondaryMuscles: def.secondaryMuscles,
          instructions: def.instructions,
          aliases: enhancedAliases,
          exerciseType: def.exerciseType,
          imageRef: def.imageRef,
          gifRef: def.gifRef,
          notes: def.notes,
          defaultTargetSets: def.defaultTargetSets,
          defaultRepMin: def.defaultRepMin,
          defaultRepMax: def.defaultRepMax,
        );
      }).toList();

      _byId.clear();
      for (final def in _allDefinitions) {
        _byId[def.id] = def;
      }
      _initialized = true;
      ExerciseSearchEngine.instance.setDefinitions(allDefinitions);
      notifyListeners();
    } catch (e) {
      debugPrint('ExerciseLibraryService asset load fallback: $e');
      _loadFallbackSync();
      _initialized = true;
      ExerciseSearchEngine.instance.setDefinitions(allDefinitions);
      notifyListeners();
    }
  }

  /// Synchronous fallback when running in headless unit tests or before async initialization.
  void _loadFallbackSync() {
    if (_allDefinitions.isNotEmpty) return;
    _allDefinitions = deduplicatedLibrary.map((ex) {
      final def = ExerciseDefinition.fromExercise(ex);
      final displayName = ExerciseDisplayEnhancer.deriveDisplayName(def.canonicalName, def.equipment);
      final enhancedAliases = ExerciseDisplayEnhancer.buildEnhancedAliases(def);
      return ExerciseDefinition(
        id: def.id,
        name: def.canonicalName,
        canonicalName: def.canonicalName,
        displayName: displayName,
        category: def.category,
        bodyPart: def.bodyPart,
        equipment: def.equipment,
        equipmentGroup: def.equipmentGroup,
        targetMuscle: def.targetMuscle,
        muscleGroup: def.muscleGroup,
        secondaryMuscles: def.secondaryMuscles,
        instructions: def.instructions,
        aliases: enhancedAliases,
        exerciseType: def.exerciseType,
        notes: def.notes,
      );
    }).toList();

    _byId.clear();
    for (final def in _allDefinitions) {
      _byId[def.id] = def;
    }
    ExerciseSearchEngine.instance.setDefinitions(allDefinitions);
  }

  /// Retrieve definition by ID, checking custom definitions first, then built-ins.
  ExerciseDefinition? getById(String id) {
    if (!_initialized && _allDefinitions.isEmpty) {
      _loadFallbackSync();
    }
    for (final c in _customDefinitions) {
      if (c.id == id) return c;
    }
    return _byId[id];
  }

  /// Register user-created custom exercises so they are instantly searchable.
  void registerCustomExercises(List<Exercise> customs) {
    _customDefinitions.clear();
    for (final ex in customs) {
      final def = ExerciseDefinition.fromExercise(ex);
      final displayName = ExerciseDisplayEnhancer.deriveDisplayName(def.canonicalName, def.equipment);
      final enhancedAliases = ExerciseDisplayEnhancer.buildEnhancedAliases(def);
      _customDefinitions.add(
        ExerciseDefinition(
          id: def.id,
          name: def.canonicalName,
          canonicalName: def.canonicalName,
          displayName: displayName,
          category: def.category,
          bodyPart: def.bodyPart,
          equipment: def.equipment,
          equipmentGroup: def.equipmentGroup,
          targetMuscle: def.targetMuscle,
          muscleGroup: def.muscleGroup,
          secondaryMuscles: def.secondaryMuscles,
          instructions: def.instructions,
          aliases: enhancedAliases,
          exerciseType: def.exerciseType,
          notes: def.notes,
        ),
      );
    }
    ExerciseSearchEngine.instance.setDefinitions(allDefinitions);
    notifyListeners();
  }

  /// Detailed relevance-ranked search returning scored results with match reasons.
  List<ExerciseSearchResult> searchDetailed({
    String query = '',
    String? category,
    String? equipmentGroup,
    Set<String>? excludeIds,
    Set<String>? splitExerciseIds,
    Set<String>? recentExerciseIds,
    int limit = 100,
  }) {
    if (!_initialized && _allDefinitions.isEmpty) {
      _loadFallbackSync();
    }
    return ExerciseSearchEngine.instance.search(
      allDefinitions: allDefinitions,
      query: query,
      category: category,
      equipmentGroup: equipmentGroup,
      excludeIds: excludeIds,
      splitExerciseIds: splitExerciseIds,
      recentExerciseIds: recentExerciseIds,
      limit: limit,
    );
  }

  /// Relevance-Ranked Multi-Token Search with Dynamic Filtering.
  List<ExerciseDefinition> search({
    String query = '',
    String? category,
    String? equipmentGroup,
    Set<String>? excludeIds,
    Set<String>? splitExerciseIds,
    Set<String>? recentExerciseIds,
    int limit = 100,
  }) {
    final results = searchDetailed(
      query: query,
      category: category,
      equipmentGroup: equipmentGroup,
      excludeIds: excludeIds,
      splitExerciseIds: splitExerciseIds,
      recentExerciseIds: recentExerciseIds,
      limit: limit,
    );
    return results.map((r) => r.definition).toList();
  }

  /// Dynamic Category Counts based on current equipment filter and query
  Map<String, int> getCategoryCounts({
    String query = '',
    String? equipmentGroup,
    Set<String>? excludeIds,
  }) {
    final all = [..._customDefinitions, ..._allDefinitions];
    final counts = <String, int>{'ALL': 0};
    final selectedEq = (equipmentGroup == null || equipmentGroup == 'ALL') ? null : equipmentGroup.toLowerCase();

    for (final ex in all) {
      if (excludeIds != null && excludeIds.contains(ex.id)) continue;
      if (selectedEq != null && ex.equipmentGroup.toLowerCase() != selectedEq) continue;

      if (query.isNotEmpty) {
        final matches = search(
          query: query,
          category: ex.category,
          equipmentGroup: equipmentGroup,
          excludeIds: excludeIds,
          limit: 1,
        );
        if (matches.isEmpty) continue;
      }

      counts['ALL'] = (counts['ALL'] ?? 0) + 1;
      counts[ex.category] = (counts[ex.category] ?? 0) + 1;
    }

    return counts;
  }

  /// Dynamic Equipment Counts based on current category filter and query
  Map<String, int> getEquipmentCounts({
    String query = '',
    String? category,
    Set<String>? excludeIds,
  }) {
    final all = [..._customDefinitions, ..._allDefinitions];
    final counts = <String, int>{'ALL': 0};
    final selectedCat = (category == null || category == 'ALL') ? null : category.toLowerCase();

    for (final ex in all) {
      if (excludeIds != null && excludeIds.contains(ex.id)) continue;
      if (selectedCat != null && ex.category.toLowerCase() != selectedCat) continue;

      if (query.isNotEmpty) {
        final matches = search(
          query: query,
          category: category,
          equipmentGroup: ex.equipmentGroup,
          excludeIds: excludeIds,
          limit: 1,
        );
        if (matches.isEmpty) continue;
      }

      counts['ALL'] = (counts['ALL'] ?? 0) + 1;
      counts[ex.equipmentGroup] = (counts[ex.equipmentGroup] ?? 0) + 1;
    }

    return counts;
  }
}
