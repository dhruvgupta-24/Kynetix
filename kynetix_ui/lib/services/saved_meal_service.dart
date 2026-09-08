import '../models/nutrition_result.dart';
import '../models/day_log.dart';
import 'meal_memory.dart';

/// Represents a matched saved meal ready for 1-tap reuse.
class SavedMealMatch {
  final String title;
  final String rawInput;
  final double calories;
  final double protein;
  final double carbohydrates;
  final double fat;
  final double fiber;
  final List<String> ingredientNames;
  final int timesUsed;
  final NutritionResult result;
  final String emoji;
  final double matchScore;

  const SavedMealMatch({
    required this.title,
    required this.rawInput,
    required this.calories,
    required this.protein,
    required this.carbohydrates,
    required this.fat,
    required this.fiber,
    required this.ingredientNames,
    required this.timesUsed,
    required this.result,
    required this.emoji,
    required this.matchScore,
  });
}

/// Instant, local, offline fuzzy/token matching service for saved meals.
/// Zero network calls, runs synchronously in <5ms.
class SavedMealService {
  SavedMealService._();
  static final SavedMealService instance = SavedMealService._();

  static final RegExp _punctRegex = RegExp(r'[^\w\s]');

  /// Normalizes a string for matching by lowercasing, removing punctuation,
  /// and collapsing whitespace.
  static String normalize(String s) {
    return s.toLowerCase().replaceAll(_punctRegex, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Splits normalized string into tokens, dropping 1-letter non-numeric tokens.
  static List<String> tokenize(String s) {
    final norm = normalize(s);
    if (norm.isEmpty) return const [];
    return norm.split(' ').where((t) => t.isNotEmpty && (t.length > 1 || RegExp(r'\d').hasMatch(t))).toList();
  }

  /// Searches all saved meals, memory items, and logged meals for [query].
  /// Ranked by relevance score and usage frequency.
  List<SavedMealMatch> search(String query, {int limit = 5}) {
    final cleanQuery = normalize(query);
    if (cleanQuery.isEmpty || cleanQuery.length < 2) return const [];

    final queryTokens = tokenize(query);
    if (queryTokens.isEmpty) return const [];

    final Map<String, SavedMealMatch> candidateMap = {};

    // 1. Gather all sources from MealMemory.instance.allEntries
    try {
      final memoryEntries = MealMemory.instance.allEntries;
      for (final entry in memoryEntries) {
        final title = entry.result.canonicalMeal.isNotEmpty ? entry.result.canonicalMeal : entry.rawInput;
        final key = normalize(title);
        if (key.isEmpty) continue;

        final cal = entry.result.calories.mid;
        final pro = entry.result.protein.mid;
        final carb = entry.result.carbohydrates?.mid ?? 0.0;
        final fat = entry.result.fat?.mid ?? 0.0;
        final fib = entry.result.fiber?.mid ?? 0.0;
        final items = entry.result.items.map((i) => i.name).toList();

        final score = _calculateScore(cleanQuery, queryTokens, title, entry.rawInput, items, entry.timesUsed);
        if (score > 25.0) {
          final existing = candidateMap[key];
          if (existing == null || existing.matchScore < score) {
            candidateMap[key] = SavedMealMatch(
              title: title,
              rawInput: entry.rawInput.isNotEmpty ? entry.rawInput : title,
              calories: cal,
              protein: pro,
              carbohydrates: carb,
              fat: fat,
              fiber: fib,
              ingredientNames: items,
              timesUsed: entry.timesUsed,
              result: entry.result,
              emoji: _detectEmoji(title),
              matchScore: score,
            );
          }
        }
      }
    } catch (_) {}

    // 2. Gather from unique MealEntry objects logged in dayLogStore
    try {
      for (final dayLog in dayLogStore.values) {
        for (final entry in dayLog.allEntries) {
          final title = entry.finalSavedInput.isNotEmpty ? entry.finalSavedInput : entry.rawInput;
          final key = normalize(title);
          if (key.isEmpty) continue;

          final cal = entry.calMid;
          final pro = entry.protMid;
          final carb = entry.result.carbohydrates?.mid ?? 0.0;
          final fat = entry.result.fat?.mid ?? 0.0;
          final fib = entry.result.fiber?.mid ?? 0.0;
          final items = entry.result.items.map((i) => i.name).toList();

          final score = _calculateScore(cleanQuery, queryTokens, title, entry.rawInput, items, 1);
          if (score > 25.0) {
            final existing = candidateMap[key];
            if (existing == null || existing.matchScore < score) {
              candidateMap[key] = SavedMealMatch(
                title: title,
                rawInput: entry.rawInput.isNotEmpty ? entry.rawInput : title,
                calories: cal,
                protein: pro,
                carbohydrates: carb,
                fat: fat,
                fiber: fib,
                ingredientNames: items,
                timesUsed: (existing?.timesUsed ?? 0) + 1,
                result: entry.result,
                emoji: _detectEmoji(title),
                matchScore: score,
              );
            }
          }
        }
      }
    } catch (_) {}

    // 3. Gather from MealMemory.instance.allKnownFoods defaults
    try {
      final knownFoods = MealMemory.instance.allKnownFoods;
      for (final entry in knownFoods.entries) {
        final title = entry.value.canonicalMeal.isNotEmpty ? entry.value.canonicalMeal : entry.key;
        final key = normalize(title);
        if (key.isEmpty) continue;

        final cal = entry.value.calories.mid;
        final pro = entry.value.protein.mid;
        final carb = entry.value.carbohydrates?.mid ?? 0.0;
        final fat = entry.value.fat?.mid ?? 0.0;
        final fib = entry.value.fiber?.mid ?? 0.0;
        final items = entry.value.items.map((i) => i.name).toList();

        final score = _calculateScore(cleanQuery, queryTokens, title, entry.key, items, 1);
        if (score > 25.0) {
          final existing = candidateMap[key];
          if (existing == null || existing.matchScore < score) {
            candidateMap[key] = SavedMealMatch(
              title: title,
              rawInput: entry.key,
              calories: cal,
              protein: pro,
              carbohydrates: carb,
              fat: fat,
              fiber: fib,
              ingredientNames: items,
              timesUsed: 1,
              result: entry.value,
              emoji: _detectEmoji(title),
              matchScore: score,
            );
          }
        }
      }
    } catch (_) {}

    final results = candidateMap.values.toList();
    results.sort((a, b) {
      final scoreCmp = b.matchScore.compareTo(a.matchScore);
      if (scoreCmp != 0) return scoreCmp;
      return b.timesUsed.compareTo(a.timesUsed);
    });

    return results.take(limit).toList();
  }

  static double _calculateScore(
    String cleanQuery,
    List<String> queryTokens,
    String rawTitle,
    String rawInput,
    List<String> ingredients,
    int timesUsed,
  ) {
    final titleNorm = normalize(rawTitle);
    final inputNorm = normalize(rawInput);
    final allTextNorm = '$titleNorm $inputNorm ${ingredients.map(normalize).join(" ")}';
    final targetTokens = tokenize(allTextNorm);

    // Exact full-string match
    if (titleNorm == cleanQuery || inputNorm == cleanQuery) {
      return 1000.0 + (timesUsed * 2.0);
    }

    // Substring contains
    if (titleNorm.contains(cleanQuery) || inputNorm.contains(cleanQuery)) {
      return 500.0 + (cleanQuery.length * 5.0) + (timesUsed * 2.0);
    }

    // Token analysis
    int matchedCount = 0;
    for (final qToken in queryTokens) {
      bool matched = false;
      for (final tToken in targetTokens) {
        if (tToken == qToken) {
          matched = true;
          break;
        } else if (tToken.startsWith(qToken) || qToken.startsWith(tToken)) {
          matched = true;
          break;
        }
      }
      if (matched) matchedCount++;
    }

    if (matchedCount == 0) return 0.0;

    final tokenRatio = matchedCount / queryTokens.length;

    // All tokens present in target
    if (tokenRatio >= 1.0) {
      return 250.0 + (matchedCount * 25.0) + (timesUsed * 2.0);
    }

    // Partial token overlap (e.g. 1 out of 2 words matched)
    if (tokenRatio >= 0.5) {
      return (tokenRatio * 100.0) + (timesUsed * 1.5);
    }

    return (tokenRatio * 50.0);
  }

  static String _detectEmoji(String name) {
    final lc = name.toLowerCase();
    if (lc.contains('coffee') || lc.contains('shake') || lc.contains('smoothie') || lc.contains('whey')) {
      return '🥤';
    }
    if (lc.contains('egg') || lc.contains('omelette') || lc.contains('bhurji')) {
      return '🍳';
    }
    if (lc.contains('chicken') || lc.contains('meat') || lc.contains('mutton') || lc.contains('fish')) {
      return '🍗';
    }
    if (lc.contains('paneer') || lc.contains('tofu')) {
      return '🧀';
    }
    if (lc.contains('rice') || lc.contains('biryani') || lc.contains('pulao')) {
      return '🍚';
    }
    if (lc.contains('roti') || lc.contains('chapati') || lc.contains('bread') || lc.contains('paratha')) {
      return '🫓';
    }
    if (lc.contains('salad') || lc.contains('vegetable') || lc.contains('sabzi')) {
      return '🥗';
    }
    if (lc.contains('banana') || lc.contains('apple') || lc.contains('fruit') || lc.contains('berry')) {
      return '🍎';
    }
    if (lc.contains('oat') || lc.contains('cereal') || lc.contains('granola')) {
      return '🥣';
    }
    if (lc.contains('peanut') || lc.contains('almond') || lc.contains('nut')) {
      return '🥜';
    }
    return '🍽️';
  }
}
