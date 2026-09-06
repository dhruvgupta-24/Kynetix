import 'dart:math';

/// Search query normalization pipeline and gym acronym / synonym dictionary.
class ExerciseQueryNormalizer {
  ExerciseQueryNormalizer._();

  /// Known gym acronyms and shorthand expansions.
  static const Map<String, List<String>> _synonymExpansions = {
    'db': ['dumbbell', 'db'],
    'dumbbell': ['db', 'dumbbell'],
    'bb': ['barbell', 'bb'],
    'barbell': ['bb', 'barbell'],
    'ohp': ['overhead press', 'shoulder press', 'military press', 'ohp'],
    'rdl': ['romanian deadlift', 'rdl'],
    'sldl': ['stiff leg deadlift', 'stiff legged deadlift', 'sldl'],
    'tbar': ['t-bar', 't bar', 'tbar', 'landmine row', 't-bar row'],
    't bar': ['t-bar', 't bar', 'tbar', 't-bar row', 'landmine row'],
    't-bar': ['t-bar', 't bar', 'tbar', 't-bar row', 'landmine row'],
    'lat pull': ['lat pulldown', 'lat pull down', 'pulldown'],
    'pulldown': ['pull down', 'pulldown', 'lat pulldown'],
    'pullup': ['pull up', 'pull-up', 'chin up', 'chinup'],
    'chinup': ['chin up', 'chin-up', 'pull up', 'pullup'],
    'pushup': ['push up', 'push-up'],
    'dip': ['dips', 'chest dip', 'tricep dip'],
    'bicep': ['biceps', 'bicep'],
    'biceps': ['bicep', 'biceps'],
    'tricep': ['triceps', 'tricep'],
    'triceps': ['tricep', 'triceps'],
    'quad': ['quads', 'quadriceps', 'quad'],
    'quads': ['quad', 'quadriceps', 'quads'],
    'hamstring': ['hamstrings', 'hams', 'hamstring'],
    'hamstrings': ['hamstring', 'hams', 'hamstrings'],
    'abs': ['abdominal', 'abdominals', 'core', 'abs'],
    'core': ['abs', 'abdominal', 'core'],
    'calf': ['calves', 'calf'],
    'calves': ['calf', 'calves'],
    'pec': ['pectoral', 'pectorals', 'chest', 'pec'],
    'pecs': ['pectoral', 'pectorals', 'chest', 'pecs'],
    'delt': ['deltoid', 'deltoids', 'shoulders', 'delt'],
    'delts': ['deltoid', 'deltoids', 'shoulders', 'delts'],
    'skull crusher': ['skullcrusher', 'skull crusher', 'lying triceps extension', 'triceps extension'],
    'skullcrusher': ['skullcrusher', 'skull crusher', 'lying triceps extension', 'triceps extension'],
    'face pull': ['facepull', 'face pull'],
    'cable row': ['seated cable row', 'cable row'],
    'seated row': ['seated cable row', 'cable seated row', 'machine seated row', 'seated row'],
    'pec deck': ['pec dec', 'pec deck', 'butterfly machine', 'chest fly machine', 'lever seated fly'],
    'pec dec': ['pec deck', 'pec dec', 'butterfly machine', 'chest fly machine', 'lever seated fly'],
    'incline bench': ['incline barbell bench', 'incline dumbbell bench', 'incline db bench', 'incline bench press', 'incline bench'],
    'cgbp': ['close grip bench press', 'close grip barbell bench press', 'cgbp'],
    'ez bar': ['ez bar', 'ez barbell', 'ez-bar'],
    'hip thrust': ['hip thrust', 'barbell hip thrust', 'glute bridge'],
    'shrug': ['shrug', 'shrugs', 'barbell shrug', 'dumbbell shrug'],
    'fly': ['fly', 'flyes', 'chest fly', 'dumbbell fly', 'cable fly'],
    'single arm': ['one arm', 'single arm', 'single-arm', '1-arm'],
    'one arm': ['single arm', 'one arm', 'single-arm', '1-arm'],
    'single leg': ['one leg', 'single leg', 'single-leg', '1-leg'],
    'one leg': ['single leg', 'one leg', 'single-leg', '1-leg'],
  };

  /// Normalizes a raw string: converts to lower case, removes special characters,
  /// normalizes whitespace, and resolves common compound forms.
  static String normalize(String input) {
    if (input.isEmpty) return '';
    var clean = input.toLowerCase();
    
    // Normalize unicode quotes and dashes
    clean = clean.replaceAll(RegExp(r'[\u2018\u2019\u201C\u201D\u0060\u00B4]'), '');
    clean = clean.replaceAll(RegExp(r'[\u2013\u2014\u2015\u2212]'), '-');
    
    // Replace punctuation with spaces except retain single hyphens inside words temporarily
    clean = clean.replaceAll(RegExp(r'[^a-z0-9\-\s]'), ' ');
    
    // Replace multiple spaces/hyphens with single space
    clean = clean.replaceAll(RegExp(r'[\s\-_]+'), ' ').trim();
    return clean;
  }

  /// Extracts clean token list from a string.
  static List<String> extractTokens(String input) {
    final norm = normalize(input);
    if (norm.isEmpty) return const [];
    return norm.split(' ').where((t) => t.isNotEmpty).toList();
  }

  /// Generates a set of normalized variations of a query for exhaustive matching.
  /// E.g. "t-bar" -> {"t-bar", "t bar", "tbar", "t-bar row"}
  /// E.g. "db bench" -> {"db bench", "dumbbell bench", "db bench press", "dumbbell bench press"}
  static Set<String> generateVariations(String rawQuery) {
    final clean = normalize(rawQuery);
    if (clean.isEmpty) return const {};

    final variations = <String>{clean};

    // 1. Without spaces/hyphens (e.g. "t bar" -> "tbar", "pull up" -> "pullup")
    final collapsed = clean.replaceAll(' ', '');
    if (collapsed.isNotEmpty) variations.add(collapsed);

    // 2. Direct dictionary lookup for full phrase
    if (_synonymExpansions.containsKey(clean)) {
      variations.addAll(_synonymExpansions[clean]!.map(normalize));
    }
    if (_synonymExpansions.containsKey(collapsed)) {
      variations.addAll(_synonymExpansions[collapsed]!.map(normalize));
    }

    // 3. Token-level synonym expansions
    final tokens = extractTokens(clean);
    if (tokens.length > 1) {
      // Look for compound acronyms (e.g. "db" -> "dumbbell", "bb" -> "barbell")
      List<List<String>> tokenOptions = [];
      for (final t in tokens) {
        if (_synonymExpansions.containsKey(t)) {
          tokenOptions.add(_synonymExpansions[t]!.map(normalize).toList());
        } else {
          tokenOptions.add([t]);
        }
      }

      // Generate cartesian product if limited options
      var combinations = <String>[''];
      for (final options in tokenOptions) {
        final next = <String>[];
        for (final prefix in combinations) {
          for (final opt in options.take(3)) {
            next.add(prefix.isEmpty ? opt : '$prefix $opt');
          }
        }
        combinations = next;
      }
      variations.addAll(combinations.map(normalize));
    }

    return variations;
  }

  /// Computes Damerau-Levenshtein distance (including adjacent transpositions) for typo tolerance.
  static int levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final d = List.generate(s1.length + 1, (_) => List<int>.filled(s2.length + 1, 0));

    for (int i = 0; i <= s1.length; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1;
        d[i][j] = min(
          d[i - 1][j] + 1, // deletion
          min(
            d[i][j - 1] + 1, // insertion
            d[i - 1][j - 1] + cost, // substitution
          ),
        );
        // Transposition of adjacent characters
        if (i > 1 && j > 1 && s1[i - 1] == s2[j - 2] && s1[i - 2] == s2[j - 1]) {
          d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1);
        }
      }
    }
    return d[s1.length][s2.length];
  }

  /// Calculates normalized similarity (0.0 to 1.0) using Damerau-Levenshtein distance.
  static double similarity(String s1, String s2) {
    final maxLen = max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    final dist = levenshteinDistance(s1, s2);
    return (maxLen - dist) / maxLen;
  }
}
