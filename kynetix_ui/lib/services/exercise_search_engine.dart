import '../models/exercise_definition.dart';
import 'exercise_query_normalizer.dart';
import 'exercise_display_enhancer.dart';
import 'user_exercise_preferences_service.dart';

/// Explanation reason for why an exercise matched a search query.
enum MatchReasonType {
  exactMatch,
  phraseMatch,
  aliasMatch,
  synonymMatch,
  tokenMatch,
  typoCorrection,
  categoryMatch,
  equipmentMatch,
}

class MatchReason {
  final MatchReasonType type;
  final String label;

  const MatchReason(this.type, this.label);

  static const exact = MatchReason(MatchReasonType.exactMatch, 'Exact match');
  static const phrase = MatchReason(MatchReasonType.phraseMatch, 'Direct phrase');
  static const bestMatch = MatchReason(MatchReasonType.exactMatch, 'Best match');

  static MatchReason alias(String aliasText) =>
      MatchReason(MatchReasonType.aliasMatch, 'Alias: $aliasText');

  static MatchReason synonym(String synText) =>
      MatchReason(MatchReasonType.synonymMatch, 'Shorthand: $synText');

  static MatchReason typo(String corrected) =>
      MatchReason(MatchReasonType.typoCorrection, 'Matches $corrected');

  static const general = MatchReason(MatchReasonType.tokenMatch, 'Search match');
}

/// Scored search result holding metadata, relevance score, and match rationale.
class ExerciseSearchResult {
  final ExerciseDefinition definition;
  final int score;
  final MatchReason matchReason;
  final bool isBestMatch;

  const ExerciseSearchResult({
    required this.definition,
    required this.score,
    required this.matchReason,
    this.isBestMatch = false,
  });
}

/// Internal precomputed index for high-speed, relevance-ranked exercise search.
class ExerciseSearchIndex {
  final List<ExerciseDefinition> allDefinitions;
  
  // Normalized lookup maps
  final Map<String, List<ExerciseDefinition>> _exactNameMap = {};
  final Map<String, List<ExerciseDefinition>> _exactAliasMap = {};
  final Map<String, Set<String>> _defAliasesMap = {};
  final Map<String, Set<String>> _defTokensMap = {};

  ExerciseSearchIndex(this.allDefinitions) {
    _buildIndex();
  }

  void _buildIndex() {
    for (final def in allDefinitions) {
      final normName = ExerciseQueryNormalizer.normalize(def.name);
      final normDisplay = ExerciseQueryNormalizer.normalize(def.displayName);
      final normCanonical = ExerciseQueryNormalizer.normalize(def.canonicalName);

      // Names
      for (final n in {normName, normDisplay, normCanonical}) {
        if (n.isNotEmpty) {
          _exactNameMap.putIfAbsent(n, () => []).add(def);
        }
      }

      // Enhanced Aliases
      final enhancedAliases = ExerciseDisplayEnhancer.buildEnhancedAliases(def);
      final aliasSet = <String>{};
      for (final a in enhancedAliases) {
        final normA = ExerciseQueryNormalizer.normalize(a);
        if (normA.isNotEmpty) {
          aliasSet.add(normA);
          _exactAliasMap.putIfAbsent(normA, () => []).add(def);
        }
      }
      _defAliasesMap[def.id] = aliasSet;

      // Search Tokens
      final tokenSet = <String>{};
      tokenSet.addAll(ExerciseQueryNormalizer.extractTokens(def.name));
      tokenSet.addAll(ExerciseQueryNormalizer.extractTokens(def.displayName));
      tokenSet.addAll(ExerciseQueryNormalizer.extractTokens(def.equipment));
      tokenSet.addAll(ExerciseQueryNormalizer.extractTokens(def.targetMuscle));
      tokenSet.addAll(ExerciseQueryNormalizer.extractTokens(def.category));
      for (final a in aliasSet) {
        tokenSet.addAll(ExerciseQueryNormalizer.extractTokens(a));
      }
      _defTokensMap[def.id] = tokenSet;
    }
  }

  Set<String> getAliasesFor(String exerciseId) =>
      _defAliasesMap[exerciseId] ?? const {};

  Set<String> getTokensFor(String exerciseId) =>
      _defTokensMap[exerciseId] ?? const {};
}

/// Relevance-Ranked Search Engine for Kynetix Exercise Discovery.
class ExerciseSearchEngine {
  ExerciseSearchEngine._();
  static final ExerciseSearchEngine instance = ExerciseSearchEngine._();

  ExerciseSearchIndex? _index;

  /// Rebuilds the search index with all active catalog definitions.
  void setDefinitions(List<ExerciseDefinition> definitions) {
    _index = ExerciseSearchIndex(definitions);
  }

  /// Executes relevance-ranked search across the exercise catalog.
  List<ExerciseSearchResult> search({
    required List<ExerciseDefinition> allDefinitions,
    required String query,
    String? category,
    String? equipmentGroup,
    Set<String>? excludeIds,
    Set<String>? splitExerciseIds,
    Set<String>? recentExerciseIds,
    int limit = 100,
  }) {
    if (_index == null || _index!.allDefinitions.length != allDefinitions.length) {
      _index = ExerciseSearchIndex(allDefinitions);
    }
    final index = _index!;

    final cleanQuery = ExerciseQueryNormalizer.normalize(query);
    final rawTokens = ExerciseQueryNormalizer.extractTokens(query);

    final selectedCat = (category == null || category == 'ALL') ? null : category.toLowerCase();
    final selectedEq = (equipmentGroup == null || equipmentGroup == 'ALL') ? null : equipmentGroup.toLowerCase();

    // 1. If query is empty: return recent, split, favorites, and popular exercises
    if (cleanQuery.isEmpty) {
      return _buildEmptyQueryResults(
        allDefinitions: allDefinitions,
        selectedCategory: selectedCat,
        selectedEquipment: selectedEq,
        excludeIds: excludeIds,
        splitExerciseIds: splitExerciseIds,
        recentExerciseIds: recentExerciseIds,
        limit: limit,
      );
    }

    // Generate search variations (e.g. "t-bar" -> "t bar", "tbar", "db" -> "dumbbell")
    final queryVariations = ExerciseQueryNormalizer.generateVariations(query);
    final queryTokens = rawTokens;

    final scoredResults = <ExerciseSearchResult>[];

    for (final ex in allDefinitions) {
      if (excludeIds != null && excludeIds.contains(ex.id)) continue;

      // Filter constraints
      if (selectedCat != null && ex.category.toLowerCase() != selectedCat) {
        continue;
      }
      if (selectedEq != null && ex.equipmentGroup.toLowerCase() != selectedEq) {
        continue;
      }

      final aliases = index.getAliasesFor(ex.id);
      final tokens = index.getTokensFor(ex.id);

      final isSplit = splitExerciseIds?.contains(ex.id) ?? false;
      final isRecent = recentExerciseIds?.contains(ex.id) ?? false;
      final personalBoost = UserExercisePreferencesService.instance.getPersonalBoost(ex.id);

      final scoreTuple = _scoreExercise(
        ex: ex,
        cleanQuery: cleanQuery,
        queryVariations: queryVariations,
        queryTokens: queryTokens,
        aliases: aliases,
        tokens: tokens,
        isSplit: isSplit,
        isRecent: isRecent,
        personalBoost: personalBoost,
      );

      final score = scoreTuple.score;
      final reason = scoreTuple.reason;

      if (score > 0) {
        scoredResults.add(
          ExerciseSearchResult(
            definition: ex,
            score: score,
            matchReason: reason,
            isBestMatch: score >= 4000,
          ),
        );
      }
    }

    // Typo / Levenshtein fallback if no strong results found (< 3 matches)
    if (scoredResults.length < 3 && cleanQuery.length >= 4) {
      final typoMatches = _findTypoFallbackMatches(
        allDefinitions: allDefinitions,
        cleanQuery: cleanQuery,
        selectedCategory: selectedCat,
        selectedEquipment: selectedEq,
        excludeIds: excludeIds,
        existingIds: scoredResults.map((r) => r.definition.id).toSet(),
      );
      scoredResults.addAll(typoMatches);
    }

    // Sort by Score DESC, then alphabetically by DisplayName
    scoredResults.sort((a, b) {
      if (b.score != a.score) {
        return b.score.compareTo(a.score);
      }
      return a.definition.displayName.compareTo(b.definition.displayName);
    });

    return scoredResults.take(limit).toList();
  }

  /// Evaluates an exercise against query variations with strict hierarchical scoring.
  ({int score, MatchReason reason}) _scoreExercise({
    required ExerciseDefinition ex,
    required String cleanQuery,
    required Set<String> queryVariations,
    required List<String> queryTokens,
    required Set<String> aliases,
    required Set<String> tokens,
    required bool isSplit,
    required bool isRecent,
    required int personalBoost,
  }) {
    final normName = ExerciseQueryNormalizer.normalize(ex.name);
    final normDisplay = ExerciseQueryNormalizer.normalize(ex.displayName);
    final normId = ExerciseQueryNormalizer.normalize(ex.id);
    final normTarget = ExerciseQueryNormalizer.normalize(ex.targetMuscle);
    final normEq = ExerciseQueryNormalizer.normalize(ex.equipment);

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 1: Exact Name Match (+10,000 pts)
    // ─────────────────────────────────────────────────────────────────────────
    if (normDisplay == cleanQuery || normName == cleanQuery || normId == cleanQuery) {
      return (
        score: 10000 + personalBoost + (isSplit ? 50 : 0) + (isRecent ? 30 : 0),
        reason: MatchReason.exact,
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 2: Exact Alias Match (+8,500 pts)
    // E.g. Query "ohp" matching alias "ohp", or "t bar" matching alias "t bar"
    // ─────────────────────────────────────────────────────────────────────────
    for (final v in queryVariations) {
      if (aliases.contains(v) || normDisplay == v || normName == v) {
        return (
          score: 8500 + personalBoost + (isSplit ? 50 : 0) + (isRecent ? 30 : 0),
          reason: MatchReason.alias(v.toUpperCase()),
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 3: Name Starts With Query (+6,000 pts)
    // E.g. "t-bar" -> "T-Bar Row"
    // ─────────────────────────────────────────────────────────────────────────
    for (final v in queryVariations) {
      if (normDisplay.startsWith(v) || normName.startsWith(v)) {
        return (
          score: 6000 + personalBoost + (isSplit ? 40 : 0),
          reason: MatchReason.phrase,
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 4: Name Contains Full Contiguous Phrase (+4,500 pts)
    // E.g. "incline db" -> "Incline DB Press"
    // ─────────────────────────────────────────────────────────────────────────
    for (final v in queryVariations) {
      if (normDisplay.contains(v) || normName.contains(v)) {
        return (
          score: 4500 + personalBoost + (isSplit ? 30 : 0),
          reason: MatchReason.phrase,
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 5: Alias Starts With Query or Contiguous Phrase (+3,800 pts)
    // ─────────────────────────────────────────────────────────────────────────
    for (final alias in aliases) {
      for (final v in queryVariations) {
        if (alias.startsWith(v) || alias.contains(v)) {
          return (
            score: 3800 + personalBoost,
            reason: MatchReason.alias(alias),
          );
        }
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 6: All Query Tokens Present in Name / DisplayName (+2,500 pts)
    // E.g. "db incline press" matching "Incline DB Press"
    // ─────────────────────────────────────────────────────────────────────────
    final nameTokens = ExerciseQueryNormalizer.extractTokens('$normDisplay $normName');
    bool allTokensInName = true;
    for (final t in queryTokens) {
      // Check if t or any synonym of t is in name
      final syns = ExerciseQueryNormalizer.generateVariations(t);
      bool tokenHit = false;
      for (final s in syns) {
        if (nameTokens.contains(s) || nameTokens.any((nt) => nt.startsWith(s))) {
          tokenHit = true;
          break;
        }
      }
      if (!tokenHit) {
        allTokensInName = false;
        break;
      }
    }

    if (allTokensInName && queryTokens.isNotEmpty) {
      return (
        score: 2500 + personalBoost + (isSplit ? 40 : 0),
        reason: MatchReason.phrase,
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 7: All Query Tokens in Enhanced Aliases (+2,000 pts)
    // ─────────────────────────────────────────────────────────────────────────
    bool allTokensInAliases = true;
    for (final t in queryTokens) {
      final syns = ExerciseQueryNormalizer.generateVariations(t);
      bool tokenHit = false;
      for (final s in syns) {
        if (tokens.contains(s) || aliases.any((a) => a.contains(s))) {
          tokenHit = true;
          break;
        }
      }
      if (!tokenHit) {
        allTokensInAliases = false;
        break;
      }
    }

    if (allTokensInAliases && queryTokens.isNotEmpty) {
      return (
        score: 2000 + personalBoost,
        reason: MatchReason.general,
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SIGNAL 8: Strong Synonym / Equipment + Movement Match (+1,500 pts)
    // ─────────────────────────────────────────────────────────────────────────
    int matchedCount = 0;
    int partialScore = 0;

    for (final t in queryTokens) {
      // Single character token should only match exact word or prefix >= 2
      if (t.length == 1) {
        if (nameTokens.contains(t)) {
          matchedCount++;
          partialScore += 200;
        }
        continue;
      }

      if (tokens.contains(t) || normTarget.contains(t) || normEq.contains(t)) {
        matchedCount++;
        partialScore += 300;
      }
    }

    if (matchedCount == queryTokens.length && queryTokens.isNotEmpty) {
      return (
        score: 1500 + partialScore + personalBoost,
        reason: MatchReason.general,
      );
    }

    if (matchedCount > 0 && queryTokens.length > 1 && matchedCount >= queryTokens.length - 1) {
      return (
        score: 600 + partialScore + personalBoost,
        reason: MatchReason.general,
      );
    }

    return (score: 0, reason: MatchReason.general);
  }

  /// Typo tolerance fallback using Levenshtein distance.
  List<ExerciseSearchResult> _findTypoFallbackMatches({
    required List<ExerciseDefinition> allDefinitions,
    required String cleanQuery,
    required String? selectedCategory,
    required String? selectedEquipment,
    required Set<String>? excludeIds,
    required Set<String> existingIds,
  }) {
    final typoResults = <ExerciseSearchResult>[];

    for (final ex in allDefinitions) {
      if (excludeIds != null && excludeIds.contains(ex.id)) continue;
      if (existingIds.contains(ex.id)) continue;

      if (selectedCategory != null && ex.category.toLowerCase() != selectedCategory) {
        continue;
      }
      if (selectedEquipment != null && ex.equipmentGroup.toLowerCase() != selectedEquipment) {
        continue;
      }

      final normDisplay = ExerciseQueryNormalizer.normalize(ex.displayName);
      final sim = ExerciseQueryNormalizer.similarity(cleanQuery, normDisplay);

      if (sim >= 0.72) {
        final score = (sim * 1000).toInt();
        typoResults.add(
          ExerciseSearchResult(
            definition: ex,
            score: score,
            matchReason: MatchReason.typo(ex.displayName),
          ),
        );
      }
    }

    return typoResults;
  }

  /// Constructs smart curated list for empty query state.
  List<ExerciseSearchResult> _buildEmptyQueryResults({
    required List<ExerciseDefinition> allDefinitions,
    required String? selectedCategory,
    required String? selectedEquipment,
    required Set<String>? excludeIds,
    required Set<String>? splitExerciseIds,
    required Set<String>? recentExerciseIds,
    required int limit,
  }) {
    final results = <ExerciseSearchResult>[];

    for (final ex in allDefinitions) {
      if (excludeIds != null && excludeIds.contains(ex.id)) continue;
      if (selectedCategory != null && ex.category.toLowerCase() != selectedCategory) continue;
      if (selectedEquipment != null && ex.equipmentGroup.toLowerCase() != selectedEquipment) continue;

      final isSplit = splitExerciseIds?.contains(ex.id) ?? false;
      final isRecent = recentExerciseIds?.contains(ex.id) ?? false;
      final isFav = UserExercisePreferencesService.instance.isFavorite(ex.id);
      final personalBoost = UserExercisePreferencesService.instance.getPersonalBoost(ex.id);

      int score = 100 + personalBoost;
      if (isFav) score += 400;
      if (isRecent) score += 250;
      if (isSplit) score += 150;

      results.add(
        ExerciseSearchResult(
          definition: ex,
          score: score,
          matchReason: isFav
              ? const MatchReason(MatchReasonType.exactMatch, 'Favorite')
              : (isRecent
                  ? const MatchReason(MatchReasonType.exactMatch, 'Recent')
                  : MatchReason.general),
        ),
      );
    }

    results.sort((a, b) {
      if (b.score != a.score) return b.score.compareTo(a.score);
      return a.definition.displayName.compareTo(b.definition.displayName);
    });

    return results.take(limit).toList();
  }
}
