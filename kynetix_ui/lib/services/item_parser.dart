import 'package:flutter/foundation.dart';
import 'parser_lexicon.dart';
import 'mock_estimation_service.dart' show getDatabaseWords;
import 'user_nutrition_memory.dart';
import 'meal_memory.dart';
import 'personal_nutrition_memory.dart';

class SpellingSuggestion {
  final String original;
  final String suggested;
  final double confidence;

  const SpellingSuggestion({
    required this.original,
    required this.suggested,
    required this.confidence,
  });
}


class ParsedFoodItem {
  final String rawChunk;
  final String normalizedName;
  final double quantity;
  final String unit;

  const ParsedFoodItem({
    required this.rawChunk,
    required this.normalizedName,
    required this.quantity,
    required this.unit,
  });

  @override
  String toString() => 'ParsedFoodItem($normalizedName, qty: $quantity, unit: $unit)';
}

class ItemParser {
  /// Splits raw input deterministically and extracts quantity per chunk.
  static List<ParsedFoodItem> parse(String rawInput) {
    String text = rawInput.toLowerCase().trim();
    if (text.isEmpty) return [];

    if (kDebugMode) {
      debugPrint('[ItemParser] Input: "$rawInput"');
    }

    // 1. Explicit Delimiter Split
    // Replace all explicit delimiters with a unique separator '|'
    for (final delimiter in ParserLexicon.delimiters) {
      text = text.replaceAll(delimiter, '|');
    }

    // 2. Implicit Pairing Split
    // Replace implicit pairs (e.g., 'dal chawal') with 'dal | chawal'
    // To ensure whole word matching, we can match and replace.
    ParserLexicon.implicitPairs.forEach((pairString, parts) {
      if (text.contains(pairString)) {
        text = text.replaceAll(pairString, parts.join('|'));
      }
    });

    // We now split by '|'
    final rawChunks = text.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (kDebugMode) {
      debugPrint('[ItemParser] Raw Chunks: $rawChunks');
    }

    // 3. Extract quantity per chunk
    final parsedItems = <ParsedFoodItem>[];
    for (final chunk in rawChunks) {
      final parsed = _extractQuantityAndName(chunk);
      final correctedName = correctSpelling(parsed.normalizedName);
      parsedItems.add(ParsedFoodItem(
        rawChunk: parsed.rawChunk,
        normalizedName: correctedName,
        quantity: parsed.quantity,
        unit: parsed.unit,
      ));
    }

    return parsedItems;
  }

  static ParsedFoodItem _extractQuantityAndName(String chunk) {
    double qty = 1.0;
    String unit = 'serving';
    String name = chunk;

    // Handle fractional words first (half, quarter, etc.)
    bool handledFractions = false;
    for (final entry in ParserLexicon.fractions.entries) {
      if (chunk.startsWith('${entry.key} ')) {
        qty = entry.value;
        name = chunk.substring(entry.key.length).trim();
        handledFractions = true;
        break;
      }
    }

    // Handle numerical prefixes if fractions didn't match.
    // e.g., "1.5 cup rice", "1 scoop whey"
    if (!handledFractions) {
      final numberMatch = RegExp(r'^([0-9]*\.?[0-9]+)\s*[xX]?\s+(.*)').firstMatch(chunk);
      if (numberMatch != null) {
        final parsedNum = double.tryParse(numberMatch.group(1) ?? '');
        if (parsedNum != null) {
          qty = parsedNum;
          name = numberMatch.group(2)?.trim() ?? '';
        }
      }
    }

    // Now, if 'name' starts or ends with a known unit, extract it.
    bool unitFound = false;
    
    // Sort units by length descending so "tablespoon" matches before "tbsp" or "spoon"
    final sortedUnits = ParserLexicon.commonUnits.toList()..sort((a, b) => b.length.compareTo(a.length));
    
    for (final u in sortedUnits) {
      // Unit at start: "scoop whey"
      if (name.startsWith('$u ')) {
        unit = u;
        name = name.substring(u.length).trim();
        unitFound = true;
        break;
      }
      // Unit at the end: "dominos pizza slice"
      if (name.endsWith(' $u')) {
        unit = u;
        name = name.substring(0, name.length - u.length - 1).trim();
        unitFound = true;
        break;
      }
    }

    // Handle things like "150g tofu"
    if (!handledFractions && qty == 1.0 && !unitFound) {
      final tightNumberUnitMatch = RegExp(r'^([0-9]*\.?[0-9]+)([a-zA-Z]+)\s*(.*)').firstMatch(chunk);
      if (tightNumberUnitMatch != null) {
        final parsedNum = double.tryParse(tightNumberUnitMatch.group(1) ?? '');
        final matchedUnit = tightNumberUnitMatch.group(2) ?? '';
        final rest = tightNumberUnitMatch.group(3) ?? '';
        
        if (parsedNum != null && ParserLexicon.commonUnits.contains(matchedUnit)) {
          qty = parsedNum;
          unit = matchedUnit;
          name = rest.isEmpty ? matchedUnit : rest;
          unitFound = true;
        }
      }
    }
    
    // Clean up generic leading/trailing hyphens etc just in case
    name = name.replaceAll(RegExp(r'^-+|-+$'), '').trim();
    if (name.isEmpty) {
      name = chunk; // Fallback
    }

    return ParsedFoodItem(
      rawChunk: chunk,
      normalizedName: name,
      quantity: qty,
      unit: unit,
    );
  }

  static Set<String> getAllFoodWords() {
    final Set<String> words = {};
    
    // 1. Database words
    try {
      words.addAll(getDatabaseWords().map((w) => w.toLowerCase()));
    } catch (_) {}

    // 2. User overrides
    try {
      for (final over in UserNutritionMemory.instance.allOverrides) {
        for (final word in over.canonicalMeal.split(RegExp(r'[^a-zA-Z0-9]'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
    } catch (_) {}

    // 3. Personal templates
    try {
      for (final key in PersonalNutritionMemory.instance.allTemplateKeys) {
        for (final word in key.split(RegExp(r'[^a-zA-Z0-9]'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
      for (final over in PersonalNutritionMemory.instance.allUserOverrides) {
        final label = over['label'] as String? ?? '';
        for (final word in label.split(RegExp(r'[^a-zA-Z0-9]'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
    } catch (_) {}

    // 4. MealMemory known foods
    try {
      for (final key in MealMemory.instance.allKnownFoods.keys) {
        for (final word in key.split(RegExp(r'[^a-zA-Z0-9]'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
    } catch (_) {}

    // 5. MealMemory recurring entries
    try {
      for (final entry in MealMemory.instance.allEntries) {
        for (final word in entry.normalizedInput.split(RegExp(r'[^a-zA-Z0-9]'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
        for (final word in entry.rawInput.split(RegExp(r'[^a-zA-Z0-9]'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
    } catch (_) {}

    // 6. ParserLexicon protected phrases & implicit pairs
    try {
      for (final phrase in ParserLexicon.protectedPhrases) {
        for (final word in phrase.split(RegExp(r'\s+'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
      for (final key in ParserLexicon.implicitPairs.keys) {
        for (final word in key.split(RegExp(r'\s+'))) {
          if (word.isNotEmpty) words.add(word.toLowerCase());
        }
      }
      for (final list in ParserLexicon.implicitPairs.values) {
        for (final item in list) {
          for (final word in item.split(RegExp(r'\s+'))) {
            if (word.isNotEmpty) words.add(word.toLowerCase());
          }
        }
      }
    } catch (_) {}

    // Add common default foods, Indian foods, and protected brands just in case database hasn't loaded or to ensure coverage
    words.addAll(const {
      'sprouts', 'sprout', 'banana', 'paneer', 'oats', 'whey', 'protein', 'rice', 'milk', 'bread', 'chips',
      'egg', 'tofu', 'peanut', 'butter', 'dal', 'roti', 'sabzi', 'chicken', 'salad', 'veg', 'shake', 'breast',
      'chaat', 'paratha', 'aloo', 'makhni', 'makhani', 'chana', 'rajma', 'biryani', 'samosa', 'naan', 'tandoori',
      'tikka', 'kebab', 'dosa', 'idli', 'sambar', 'upma', 'poha', 'khichdi', 'raita', 'lassi', 'fish', 'mutton',
      'curry', 'myprotein', 'optimum', 'nutrition', 'troovy', 'goatlife', 'amul'
    });

    return words;
  }

  static bool _isProtectedWord(String word) {
    final w = word.toLowerCase().trim();
    if (w.isEmpty) return false;

    // 1. Protected brands
    const protectedBrands = {
      'myprotein',
      'optimum',
      'nutrition',
      'troovy',
      'goatlife',
      'amul',
    };
    if (protectedBrands.contains(w)) return true;

    // 2. User-created foods (UserNutritionMemory)
    try {
      for (final over in UserNutritionMemory.instance.allOverrides) {
        for (final part in over.canonicalMeal.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return true;
        }
      }
    } catch (_) {}

    // 3. User overrides (PersonalNutritionMemory)
    try {
      for (final over in PersonalNutritionMemory.instance.allUserOverrides) {
        final label = (over['label'] as String? ?? '').toLowerCase();
        for (final part in label.split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return true;
        }
      }
    } catch (_) {}

    return false;
  }

  static int _getWordPriority(String word) {
    final w = word.toLowerCase().trim();
    if (w.isEmpty) return 5;

    // 1. User foods
    try {
      for (final over in UserNutritionMemory.instance.allOverrides) {
        for (final part in over.canonicalMeal.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 1;
        }
      }
    } catch (_) {}

    try {
      for (final over in PersonalNutritionMemory.instance.allUserOverrides) {
        final label = (over['label'] as String? ?? '').toLowerCase();
        for (final part in label.split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 1;
        }
      }
    } catch (_) {}

    // 2. Saved foods
    try {
      for (final key in MealMemory.instance.allKnownFoods.keys) {
        for (final part in key.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 2;
        }
      }
      for (final entry in MealMemory.instance.allEntries) {
        for (final part in entry.normalizedInput.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 2;
        }
        for (final part in entry.rawInput.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 2;
        }
      }
    } catch (_) {}

    // 3. Personal templates
    try {
      for (final key in PersonalNutritionMemory.instance.allTemplateKeys) {
        for (final part in key.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 3;
        }
      }
    } catch (_) {}

    // 4. Database foods
    try {
      for (final dbWord in getDatabaseWords()) {
        for (final part in dbWord.toLowerCase().split(RegExp(r'[^a-z0-9]'))) {
          if (part == w) return 4;
        }
      }
    } catch (_) {}

    return 5;
  }

  static const Map<String, String> _knownCorrections = {
    // Single-word corrections
    'xhaat': 'chaat',
    'xaat': 'chaat',
    'chat': 'chaat',
    'pnner': 'paneer',
    'panner': 'paneer',
    'chiken': 'chicken',
    'chkien': 'chicken',
    'pratha': 'paratha',
    'biryni': 'biryani',
    'rajmah': 'rajma',
    'makhni': 'makhani',
    'makahani': 'makhani',
    // Multi-word corrections
    'aloo pratha': 'aloo paratha',
  };

  static const Set<String> _coreFoodWords = {
    'chaat', 'paneer', 'paratha', 'chicken', 'biryani', 'rajma', 'banana', 'sprouts',
    'sprout', 'oats', 'whey', 'protein', 'rice', 'milk', 'bread', 'chips', 'egg',
    'tofu', 'peanut', 'butter', 'dal', 'roti', 'sabzi', 'salad', 'veg', 'shake', 'breast',
    'samosa', 'makhani', 'chana', 'aloo', 'naan', 'tandoori', 'tikka', 'kebab', 'dosa',
    'idli', 'sambar', 'upma', 'poha', 'khichdi', 'raita', 'lassi', 'fish', 'mutton',
    'curry', 'eggplant', 'bhindi', 'gobi', 'palak', 'methi', 'chole'
  };

  static bool _isCoreFood(String word) {
    final w = word.toLowerCase().trim();
    if (_coreFoodWords.contains(w)) return true;

    // Check MealMemory known foods
    try {
      if (MealMemory.instance.allKnownFoods.containsKey(w)) return true;
    } catch (_) {}

    // Check UserNutritionMemory overrides
    try {
      for (final over in UserNutritionMemory.instance.allOverrides) {
        if (over.canonicalMeal.toLowerCase().split(RegExp(r'[^a-z0-9]')).contains(w)) {
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  static SpellingSuggestion? getSpellingSuggestion(String text) {
    final cleanText = text.trim().toLowerCase();
    if (cleanText.isEmpty) return null;

    // Layer 1/2: Full-string match on known corrections (e.g. 'aloo pratha' -> 'aloo paratha')
    final knownFull = _knownCorrections[cleanText];
    if (knownFull != null) {
      return SpellingSuggestion(
        original: text,
        suggested: knownFull,
        confidence: 0.98,
      );
    }

    final words = cleanText.split(RegExp(r'\s+'));
    final suggestedWords = <String>[];
    bool hasCorrection = false;
    double minConfidence = 1.0;

    final dictionary = getAllFoodWords();

    final Set<String> ignoreWords = {
      ...ParserLexicon.commonUnits,
      'and', 'with', 'plus', 'or', '&', '+', 'of', 'for', 'in', 'at', 'on', 'a', 'an', 'the',
      'half', 'quarter', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'
    };

    for (final word in words) {
      if (word.isEmpty || RegExp(r'^\d+$').hasMatch(word) || ignoreWords.contains(word)) {
        suggestedWords.add(word);
        continue;
      }

      // Layer 1: Exact Match check FIRST
      if (dictionary.contains(word)) {
        suggestedWords.add(word);
        continue;
      }

      // Plural checks (only run after exact match check fails, so e.g. "sprouts" is preserved)
      if (word.endsWith('s') && dictionary.contains(word.substring(0, word.length - 1))) {
        suggestedWords.add(word.substring(0, word.length - 1));
        hasCorrection = true;
        minConfidence = minConfidence < 0.98 ? minConfidence : 0.98;
        continue;
      }
      if (word.endsWith('es') && dictionary.contains(word.substring(0, word.length - 2))) {
        suggestedWords.add(word.substring(0, word.length - 2));
        hasCorrection = true;
        minConfidence = minConfidence < 0.98 ? minConfidence : 0.98;
        continue;
      }

      // If the word matches a protected brand or user custom food, keep it as is
      if (_isProtectedWord(word)) {
        suggestedWords.add(word);
        continue;
      }

      // Layer 2: Known Food Correction Layer (Word-by-word)
      final knownWord = _knownCorrections[word];
      if (knownWord != null) {
        suggestedWords.add(knownWord);
        hasCorrection = true;
        minConfidence = minConfidence < 0.98 ? minConfidence : 0.98;
        continue;
      }

      // Find the closest word in the dictionary
      String bestMatch = word;
      double bestSimilarity = -1.0;
      int bestPriority = 99;

      for (final dictWord in dictionary) {
        final dist = _levenshtein(word, dictWord);
        final maxLen = word.length > dictWord.length ? word.length : dictWord.length;
        if (maxLen == 0) continue;

        final double similarity;
        if (maxLen <= 4 && dist == 1) {
          similarity = 0.85; // Boost short word 1-char typos to medium confidence (80% - 95%)
        } else {
          similarity = 1.0 - (dist / maxLen);
        }

        // Layer 3/4: Food-Specific Fuzzy Matching (relaxed threshold) vs Generic Fallback (strict 0.80)
        final isCore = _isCoreFood(dictWord);
        final threshold = isCore ? 0.60 : 0.80;
        final bool isMatch = similarity >= threshold;

        if (isMatch) {
          final priority = _getWordPriority(dictWord);
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestMatch = dictWord;
            bestPriority = priority;
          } else if (similarity == bestSimilarity) {
            // Tie breakers:
            // 1. Core food wins
            final bestIsCore = _isCoreFood(bestMatch);
            if (isCore && !bestIsCore) {
              bestMatch = dictWord;
              bestPriority = priority;
            } else if (isCore == bestIsCore) {
              // 2. Priority wins
              if (priority < bestPriority) {
                bestMatch = dictWord;
                bestPriority = priority;
              }
            }
          }
        }
      }

      // Brand and custom food protection for the SUGGESTED target word:
      // If the suggested word is a protected brand/custom food, we must require >0.95 confidence.
      if (bestSimilarity > 0 && _isProtectedWord(bestMatch)) {
        if (bestSimilarity <= 0.95) {
          // Reject correction, keep original
          bestMatch = word;
          bestSimilarity = -1.0;
        }
      }

      if (bestMatch != word && bestSimilarity >= 0.60) {
        hasCorrection = true;
        suggestedWords.add(bestMatch);
        if (bestSimilarity < minConfidence) {
          minConfidence = bestSimilarity;
        }
      } else {
        suggestedWords.add(word);
      }
    }

    if (hasCorrection) {
      final suggestedText = suggestedWords.join(' ');
      // 8. Debug logging for spelling suggestions during development:
      if (kDebugMode) {
        debugPrint('Input: "$text" Suggestion: "$suggestedText" Confidence: ${minConfidence.toStringAsFixed(2)}');
      }
      return SpellingSuggestion(
        original: text,
        suggested: suggestedText,
        confidence: minConfidence,
      );
    }
    return null;
  }

  static String correctSpelling(String text) {
    final suggestion = getSpellingSuggestion(text);
    if (suggestion != null) {
      // Only auto-correct if confidence is High (> 0.95)
      if (suggestion.confidence > 0.95) {
        return suggestion.suggested;
      }
    }
    return text;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final int sLen = s.length;
    final int tLen = t.length;

    final List<List<int>> d = List.generate(
      sLen + 1,
      (_) => List<int>.filled(tLen + 1, 0),
    );

    for (int i = 0; i <= sLen; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= tLen; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= sLen; i++) {
      for (int j = 1; j <= tLen; j++) {
        final int cost = (s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1)) ? 0 : 1;

        int minVal = d[i - 1][j] + 1; // deletion
        if (d[i][j - 1] + 1 < minVal) minVal = d[i][j - 1] + 1; // insertion
        if (d[i - 1][j - 1] + cost < minVal) minVal = d[i - 1][j - 1] + cost; // substitution

        if (i > 1 && j > 1 &&
            s.codeUnitAt(i - 1) == t.codeUnitAt(j - 2) &&
            s.codeUnitAt(i - 2) == t.codeUnitAt(j - 1)) {
          if (d[i - 2][j - 2] + cost < minVal) {
            minVal = d[i - 2][j - 2] + cost; // transposition
          }
        }
        d[i][j] = minVal;
      }
    }
    return d[sLen][tLen];
  }

  static int _min3(int a, int b, int c) {
    int min = a;
    if (b < min) min = b;
    if (c < min) min = c;
    return min;
  }
}
