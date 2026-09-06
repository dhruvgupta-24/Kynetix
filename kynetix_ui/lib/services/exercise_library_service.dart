import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/exercise_definition.dart';
import '../models/workout_split.dart';

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
      _allDefinitions = parsed
          .map((item) => ExerciseDefinition.fromJson(item as Map<String, dynamic>))
          .toList();

      _byId.clear();
      for (final def in _allDefinitions) {
        _byId[def.id] = def;
      }
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('ExerciseLibraryService asset load fallback: $e');
      _loadFallbackSync();
      _initialized = true;
      notifyListeners();
    }
  }

  /// Synchronous fallback when running in headless unit tests or before async initialization.
  void _loadFallbackSync() {
    if (_allDefinitions.isNotEmpty) return;
    _allDefinitions = deduplicatedLibrary
        .map((ex) => ExerciseDefinition.fromExercise(ex))
        .toList();
    _byId.clear();
    for (final def in _allDefinitions) {
      _byId[def.id] = def;
    }
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
      _customDefinitions.add(ExerciseDefinition.fromExercise(ex));
    }
    notifyListeners();
  }

  /// Intelligent Multi-Token Search with Dynamic Filtering & Relevance Ranking.
  ///
  /// Matches all tokens across name, aliases, equipment, and anatomical tags.
  List<ExerciseDefinition> search({
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

    final cleanQuery = query.trim().toLowerCase();
    final tokens = cleanQuery.isEmpty
        ? <String>[]
        : cleanQuery.split(RegExp(r'[\s,\-_]+')).where((t) => t.isNotEmpty).toList();

    final selectedCat = (category == null || category == 'ALL') ? null : category.toLowerCase();
    final selectedEq = (equipmentGroup == null || equipmentGroup == 'ALL') ? null : equipmentGroup.toLowerCase();

    final all = [..._customDefinitions, ..._allDefinitions];
    final scoredList = <_ScoredExercise>[];

    for (final ex in all) {
      if (excludeIds != null && excludeIds.contains(ex.id)) continue;

      // Category filter
      if (selectedCat != null && ex.category.toLowerCase() != selectedCat) {
        continue;
      }

      // Equipment filter
      if (selectedEq != null && ex.equipmentGroup.toLowerCase() != selectedEq) {
        continue;
      }

      // If no query, score based on split/recent status + default order
      if (tokens.isEmpty) {
        int baseScore = 100;
        if (splitExerciseIds != null && splitExerciseIds.contains(ex.id)) {
          baseScore += 50;
        }
        if (recentExerciseIds != null && recentExerciseIds.contains(ex.id)) {
          baseScore += 30;
        }
        scoredList.add(_ScoredExercise(ex, baseScore));
        continue;
      }

      // Evaluate multi-token match
      final score = _calculateRelevanceScore(
        ex: ex,
        query: cleanQuery,
        tokens: tokens,
        isSplit: splitExerciseIds?.contains(ex.id) ?? false,
        isRecent: recentExerciseIds?.contains(ex.id) ?? false,
      );

      if (score > 0) {
        scoredList.add(_ScoredExercise(ex, score));
      }
    }

    scoredList.sort((a, b) {
      if (b.score != a.score) {
        return b.score.compareTo(a.score);
      }
      return a.definition.name.compareTo(b.definition.name);
    });

    return scoredList.take(limit).map((s) => s.definition).toList();
  }

  /// Calculates relevance score for multi-token fuzzy matching.
  int _calculateRelevanceScore({
    required ExerciseDefinition ex,
    required String query,
    required List<String> tokens,
    required bool isSplit,
    required bool isRecent,
  }) {
    final nameLower = ex.name.toLowerCase();
    final idLower = ex.id.toLowerCase();
    final catLower = ex.category.toLowerCase();
    final targetLower = ex.targetMuscle.toLowerCase();
    final eqLower = ex.equipment.toLowerCase();
    final eqGLower = ex.equipmentGroup.toLowerCase();
    final aliasesLower = ex.aliases.map((a) => a.toLowerCase()).toList();

    // 1. Exact Name/ID match
    if (nameLower == query || idLower == query) {
      return 1000 + (isSplit ? 50 : 0) + (isRecent ? 30 : 0);
    }

    // 2. Exact start of name match
    if (nameLower.startsWith(query)) {
      return 600 + (isSplit ? 50 : 0) + (isRecent ? 30 : 0);
    }

    // 3. Multi-token check: every token MUST match somewhere
    int matchedTokens = 0;
    int tokenScore = 0;

    for (final token in tokens) {
      bool tokenMatched = false;

      // Name match (highest weight)
      if (nameLower.contains(token)) {
        tokenMatched = true;
        if (nameLower.startsWith(token) || nameLower.contains(' $token')) {
          tokenScore += 120; // Word boundary match
        } else {
          tokenScore += 80;
        }
      }

      // Alias match
      if (!tokenMatched) {
        for (final alias in aliasesLower) {
          if (alias.contains(token)) {
            tokenMatched = true;
            tokenScore += 70;
            break;
          }
        }
      }

      // Target muscle / Category match
      if (!tokenMatched) {
        if (targetLower.contains(token) || catLower.contains(token)) {
          tokenMatched = true;
          tokenScore += 50;
        }
      }

      // Equipment match
      if (!tokenMatched) {
        if (eqLower.contains(token) || eqGLower.contains(token)) {
          tokenMatched = true;
          tokenScore += 40;
        }
      }

      if (tokenMatched) {
        matchedTokens++;
      }
    }

    // All tokens must match for a valid hit
    if (matchedTokens < tokens.length) {
      return 0;
    }

    int totalScore = tokenScore;
    if (isSplit) totalScore += 40;
    if (isRecent) totalScore += 25;

    return totalScore;
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

class _ScoredExercise {
  final ExerciseDefinition definition;
  final int score;
  const _ScoredExercise(this.definition, this.score);
}
