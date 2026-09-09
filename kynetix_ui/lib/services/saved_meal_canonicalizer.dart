import 'saved_meal_service.dart';

/// Conservative canonicalization layer for saved meals.
/// Collapses obvious quantity-scaled duplicates (e.g. "0.8 beyond snack...", "beyond snack...")
/// while strictly preserving distinct meals, exact saved macros, and original records.
class SavedMealCanonicalizer {
  static final RegExp _leadingNumberRegex = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*[xX]?\s+(.+)$');
  static final RegExp _punctRegex = RegExp(r'[^\w\s]');

  /// Normalizes a string by lowercasing, removing punctuation, and collapsing whitespace.
  static String normalize(String s) {
    return s.toLowerCase().replaceAll(_punctRegex, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Conservatively extracts a leading multiplier and base food name.
  /// E.g. "0.8 beyond snack desi masala chips" -> multiplier: 0.8, base: "beyond snack desi masala chips"
  /// "beyond snack desi masala chips" -> multiplier: 1.0, base: "beyond snack desi masala chips"
  static ({double multiplier, String baseName, bool hasPrefix}) extractPrefix(String raw) {
    final trimmed = raw.trim();
    final match = _leadingNumberRegex.firstMatch(trimmed);
    if (match != null) {
      final multStr = match.group(1);
      final rest = match.group(2)?.trim() ?? '';
      final mult = double.tryParse(multStr ?? '');
      // Only treat as multiplier if rest is a valid non-empty string and multiplier is positive reasonable range
      if (mult != null && mult > 0.0 && mult <= 20.0 && rest.length >= 2) {
        return (multiplier: mult, baseName: rest, hasPrefix: true);
      }
    }
    return (multiplier: 1.0, baseName: trimmed, hasPrefix: false);
  }

  /// Collapses quantity-scaled variants conservatively.
  /// If equivalence is ambiguous, keeps both entries.
  static List<SavedMealMatch> collapseConservativeDuplicates(List<SavedMealMatch> matches) {
    if (matches.length <= 1) return matches;

    final List<SavedMealMatch> result = [];
    final List<_MatchIdentity> identities = matches.map((m) {
      final prefixInfo = extractPrefix(m.title);
      final rawPrefixInfo = extractPrefix(m.rawInput);
      // Prefer prefix from title, fallback to rawInput
      final chosen = prefixInfo.hasPrefix ? prefixInfo : rawPrefixInfo;
      final normBase = normalize(chosen.baseName);
      return _MatchIdentity(
        match: m,
        baseName: chosen.baseName,
        normalizedBase: normBase,
        multiplier: chosen.multiplier,
        hasPrefix: chosen.hasPrefix,
      );
    }).toList();

    // Group candidates with the same normalized base name
    final Map<String, List<_MatchIdentity>> groups = {};
    for (final id in identities) {
      if (id.normalizedBase.isEmpty) {
        result.add(id.match);
        continue;
      }
      groups.putIfAbsent(id.normalizedBase, () => []).add(id);
    }

    for (final group in groups.values) {
      if (group.length == 1) {
        result.add(group.first.match);
        continue;
      }

      // We have multiple entries with the same normalized base name!
      // Check for strong identity evidence to safely merge.
      final List<_MatchIdentity> unmerged = [];
      _MatchIdentity? canonicalPrimary;

      for (final candidate in group) {
        if (canonicalPrimary == null) {
          canonicalPrimary = candidate;
          continue;
        }

        final areEquivalent = _verifyEquivalence(canonicalPrimary, candidate);
        if (areEquivalent) {
          // Strong evidence of quantity scaling: merge into canonical primary.
          // Prefer the unprefixed / 1.0x / higher-used entry as the primary representation.
          if (!candidate.hasPrefix && canonicalPrimary.hasPrefix) {
            canonicalPrimary = candidate;
          } else if (candidate.match.timesUsed > canonicalPrimary.match.timesUsed && (!candidate.hasPrefix || canonicalPrimary.hasPrefix)) {
            canonicalPrimary = candidate;
          }
        } else {
          // Equivalence ambiguous or macros diverge significantly -> keep separate!
          unmerged.add(candidate);
        }
      }

      if (canonicalPrimary != null) {
        result.add(canonicalPrimary.match);
      }
      for (final u in unmerged) {
        result.add(u.match);
      }
    }

    return result;
  }

  /// Verifies strong identity evidence before collapsing two candidates.
  static bool _verifyEquivalence(_MatchIdentity a, _MatchIdentity b) {
    // 1. Bases must be identical
    if (a.normalizedBase != b.normalizedBase) return false;

    // 2. Check ingredient composition identity if available
    final itemsA = a.match.ingredientNames.map(normalize).toList();
    final itemsB = b.match.ingredientNames.map(normalize).toList();
    if (itemsA.isNotEmpty && itemsB.isNotEmpty) {
      final setA = itemsA.toSet();
      final setB = itemsB.toSet();
      if (setA.difference(setB).isEmpty && setB.difference(setA).isEmpty) {
        return true;
      }
    }

    // 3. Check macro proportionality against multipliers
    final calA = a.match.calories;
    final calB = b.match.calories;
    if (calA > 0 && calB > 0) {
      final multRatio = a.multiplier / b.multiplier;
      final calRatio = calA / calB;
      // If calorie ratio matches multiplier ratio within ±25%, strong identity evidence
      if ((calRatio - multRatio).abs() / multRatio < 0.25) {
        return true;
      }
      // Calorie ratio contradicts scalar multiplier -> do NOT merge
      return false;
    }

    // Ambiguous -> do NOT merge
    return false;
  }
}

class _MatchIdentity {
  final SavedMealMatch match;
  final String baseName;
  final String normalizedBase;
  final double multiplier;
  final bool hasPrefix;

  const _MatchIdentity({
    required this.match,
    required this.baseName,
    required this.normalizedBase,
    required this.multiplier,
    required this.hasPrefix,
  });
}
