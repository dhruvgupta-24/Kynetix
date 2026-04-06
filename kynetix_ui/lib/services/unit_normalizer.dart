// ─── UnitNormalizer ───────────────────────────────────────────────────────────
//
// Converts raw quantity+unit pairs into canonical base units before any
// memory storage or lookup operation.
//
// Base unit rules:
//   weight → grams   (g)
//   volume → millilitres (ml)
//   count/serving → unchanged (the unit itself is canonical)
//
// All calorie-per-unit values in UserNutritionMemory are stored in terms
// of these canonical units. This guarantees that:
//   150 g tofu  == 0.15 kg tofu  (both normalize to 150 g internally)
//   500 ml milk == 0.5 l milk    (both normalize to 500 ml internally)

class UnitNormalizer {
  UnitNormalizer._();

  // ── Unit category maps ─────────────────────────────────────────────────────

  static const _weightUnits = {
    'g', 'gram', 'grams',
    'kg', 'kilo', 'kilos', 'kilogram', 'kilograms',
  };

  static const _volumeUnits = {
    'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres',
    'l', 'liter', 'liters', 'litre', 'litres',
  };

  // Multiplier to convert the GIVEN unit into its base unit.
  static const _toGrams = {
    'g': 1.0, 'gram': 1.0, 'grams': 1.0,
    'kg': 1000.0, 'kilo': 1000.0, 'kilos': 1000.0,
    'kilogram': 1000.0, 'kilograms': 1000.0,
  };

  static const _toMl = {
    'ml': 1.0, 'milliliter': 1.0, 'milliliters': 1.0,
    'millilitre': 1.0, 'millilitres': 1.0,
    'l': 1000.0, 'liter': 1000.0, 'liters': 1000.0,
    'litre': 1000.0, 'litres': 1000.0,
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Normalizes a raw unit string to its canonical lowercase alias.
  /// Returns the unit unchanged if it is already canonical or unrecognized.
  static String normalizeUnit(String rawUnit) {
    final u = rawUnit.trim().toLowerCase();
    if (_toGrams.containsKey(u)) return 'g';
    if (_toMl.containsKey(u)) return 'ml';
    return u; // count units, scoops, etc. are already canonical
  }

  /// Converts [quantity] expressed in [rawUnit] to the base unit quantity.
  /// e.g. normalizeQuantity(0.15, 'kg') → 150.0
  ///      normalizeQuantity(1.0,  'l') → 1000.0
  ///      normalizeQuantity(2.0,  'scoop') → 2.0 (unchanged)
  static double normalizeQuantity(double quantity, String rawUnit) {
    final u = rawUnit.trim().toLowerCase();
    final gMult = _toGrams[u];
    if (gMult != null) return quantity * gMult;
    final mlMult = _toMl[u];
    if (mlMult != null) return quantity * mlMult;
    return quantity; // non-metric unit — pass through unchanged
  }

  /// Whether two units are in the same measurement category and can be
  /// compared / scaled against memories stored for either.
  /// Used to BLOCK cross-category matches (g vs ml).
  static bool sameCategory(String unitA, String unitB) {
    final a = unitA.trim().toLowerCase();
    final b = unitB.trim().toLowerCase();
    if (_weightUnits.contains(a) && _weightUnits.contains(b)) return true;
    if (_volumeUnits.contains(a) && _volumeUnits.contains(b)) return true;
    // Both non-metric (scoop, serving, piece…) — treat as compatible
    if (!_weightUnits.contains(a) && !_volumeUnits.contains(a) &&
        !_weightUnits.contains(b) && !_volumeUnits.contains(b)) {
      return true;
    }
    return false;
  }

  /// Whether [unit] belongs to a metric measurement category (weight or volume).
  static bool isMetric(String unit) {
    final u = unit.trim().toLowerCase();
    return _weightUnits.contains(u) || _volumeUnits.contains(u);
  }
}

// ─── FoodNameNormalizer ───────────────────────────────────────────────────────
//
// Strips cosmetic adjectives and stop-words from food names so that:
//   "fresh tofu" → "tofu"
//   "boiled eggs" → "eggs"
//   "full cream milk" → "milk" (partial — cream is kept to preserve meaning)
//
// IMPORTANT: stripping is intentionally conservative to avoid destroying
// semantically-meaningful modifiers (e.g. "brown rice" ≠ "white rice").

class FoodNameNormalizer {
  FoodNameNormalizer._();

  /// Stop words removed from food names before memory storage/lookup.
  static const _stopWords = {
    'fresh', 'boiled', 'cooked', 'raw', 'plain', 'simple',
    'homemade', 'home', 'made', 'a', 'an', 'the', 'of',
  };

  /// Normalize a food name for consistent memory keying and lookup.
  /// Returns lower-cased, trimmed, stop-word-stripped string.
  static String normalize(String rawName) {
    final tokens = rawName
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_stopWords.contains(t))
        .toList();
    return tokens.join(' ');
  }
}
