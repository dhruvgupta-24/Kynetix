import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import '../services/cloud_sync_service.dart';
import '../services/unit_normalizer.dart';

// ─── UserMealOverride ─────────────────────────────────────────────────────────
//
// Represents one persisted user correction for a specific atomic food item.
//
// INVARIANTS (enforced on construction and on fromJson):
//   - canonicalMeal is FoodNameNormalizer-normalized (lowercase, no stop words)
//   - referenceUnit is UnitNormalizer-normalized (always 'g', 'ml', or a
//     canonical count unit like 'scoop')
//   - caloriesPerUnit and proteinPerUnit are expressed in terms of referenceUnit
//     e.g. caloriesPerUnit == 2.0 with referenceUnit == 'g' means 2 kcal/gram
//   - originalTokens are tokenized from the normalized canonicalMeal

class UserMealOverride {
  final String canonicalMeal;      // normalized food name
  final double caloriesPerUnit;    // kcal per 1 referenceUnit
  final double proteinPerUnit;     // g protein per 1 referenceUnit
  final double referenceQuantity;  // quantity used when this was recorded
  final String referenceUnit;      // canonical unit (g / ml / scoop / …)
  final List<String> originalTokens;

  UserMealOverride({
    required this.canonicalMeal,
    required this.caloriesPerUnit,
    required this.proteinPerUnit,
    this.referenceQuantity = 1.0,
    this.referenceUnit     = 'serving',
    List<String>? originalTokens,
  }) : originalTokens = originalTokens ?? _tokenize(canonicalMeal);

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'canonicalMeal':     canonicalMeal,
        'caloriesPerUnit':   caloriesPerUnit,
        'proteinPerUnit':    proteinPerUnit,
        'referenceQuantity': referenceQuantity,
        'referenceUnit':     referenceUnit,
        'originalTokens':    originalTokens,
        // Legacy keys kept for backward compat with old SharedPreferences data
        // and existing Supabase rows.  New writes always have 'caloriesPerUnit'.
        'calories': caloriesPerUnit,
        'protein':  proteinPerUnit,
      };

  factory UserMealOverride.fromJson(Map<String, dynamic> json) {
    // Handle both new ('caloriesPerUnit') and old ('calories') key names
    final cal = (json['caloriesPerUnit'] as num?)?.toDouble()
        ?? (json['calories'] as num?)?.toDouble()
        ?? 0.0;
    final pro = (json['proteinPerUnit'] as num?)?.toDouble()
        ?? (json['protein'] as num?)?.toDouble()
        ?? 0.0;

    // Normalize the unit on read so old entries (that may have stored 'kg')
    // are transparently upgraded to 'g'.
    final rawUnit = json['referenceUnit'] as String? ?? 'serving';
    final normUnit = UnitNormalizer.normalizeUnit(rawUnit);

    // If the unit changed (e.g. 'kg' → 'g'), the caloriesPerUnit was stored
    // in the old unit basis and must be rescaled.  Old entries that stored
    // 'calories' (not 'caloriesPerUnit') were total-meal values at qty=1 and
    // don't need additional rescaling — they were already per-unit-1 at whatever
    // unit was used.  The only rescaling needed is when the unit itself changes
    // its multiplier (kg→g: 1 kg unit → 1000 g units, so kcal/unit ÷ 1000).
    double finalCal = cal;
    double finalPro = pro;
    if (rawUnit != normUnit) {
      // e.g. stored kcal/kg → kcal/g: divide by 1000
      final mult = UnitNormalizer.normalizeQuantity(1.0, rawUnit); // grams per old unit
      if (mult > 0) {
        finalCal = cal / mult;
        finalPro = pro / mult;
      }
    }

    // Normalize meal name on read as well
    final rawMeal = json['canonicalMeal'] as String? ?? '';
    final normMeal = FoodNameNormalizer.normalize(rawMeal);

    return UserMealOverride(
      canonicalMeal:     normMeal,
      caloriesPerUnit:   finalCal,
      proteinPerUnit:    finalPro,
      referenceQuantity: (json['referenceQuantity'] as num?)?.toDouble() ?? 1.0,
      referenceUnit:     normUnit,
      originalTokens:    List<String>.from(json['originalTokens'] ?? []),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<String> _tokenize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((t) =>
            t.isNotEmpty &&
            t != 'and' &&
            t != 'with' &&
            t != 'the' &&
            t != 'a' &&
            t != 'of')
        .toList();
  }
}

// ─── UserNutritionMemory ──────────────────────────────────────────────────────

class UserNutritionMemory {
  UserNutritionMemory._();
  static final UserNutritionMemory instance = UserNutritionMemory._();

  static const _kOverrides = 'user_meal_overrides_v1';
  static const String defaultServingUnit = 'serving';

  final List<UserMealOverride> _overrides = [];
  bool _ready = false;

  // ── Startup ────────────────────────────────────────────────────────────────

  /// Load from SharedPreferences.  Called in PersistenceService.load() before
  /// cloud hydration, so memory is immediately available even offline.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = prefs.getStringList(_kOverrides) ?? [];
    _overrides.clear();
    for (final s in list) {
      try {
        _overrides.add(
            UserMealOverride.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[UserNutritionMemory] parse error: $e');
      }
    }
    _ready = true;
    debugPrint('[UserNutritionMemory] loaded ${_overrides.length} overrides from local storage');
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Save a per-unit-1 override for [rawMealName].
  ///
  /// CALLER RESPONSIBILITY: [caloriesPerUnit] and [proteinPerUnit] must ALREADY
  /// be divided by [referenceQuantity] at the call site.  This method normalizes
  /// the unit and name, then persists locally and syncs to cloud.
  Future<void> saveOverride(
    String rawMealName,
    double caloriesPerUnit,
    double proteinPerUnit, {
    double referenceQuantity = 1.0,
    String referenceUnit     = defaultServingUnit,
  }) async {
    // Normalize inputs on the way in
    final normName = FoodNameNormalizer.normalize(rawMealName);
    final normUnit = UnitNormalizer.normalizeUnit(referenceUnit);
    final normQty  = UnitNormalizer.normalizeQuantity(referenceQuantity, referenceUnit);

    // Rescale caloriesPerUnit to the normalized unit basis.
    // Example: caller saves 2 kcal per 'kg' → normalizer maps 'kg'→'g'
    // so it's really 0.002 kcal/g.  The multiplier is (1 g / 1000 g per kg).
    double finalCal = caloriesPerUnit;
    double finalPro = proteinPerUnit;
    if (referenceUnit.trim().toLowerCase() != normUnit) {
      final mult = UnitNormalizer.normalizeQuantity(1.0, referenceUnit);
      if (mult > 0) {
        finalCal = caloriesPerUnit / mult;
        finalPro = proteinPerUnit  / mult;
      }
    }

    final override = UserMealOverride(
      canonicalMeal:     normName,
      caloriesPerUnit:   finalCal,
      proteinPerUnit:    finalPro,
      referenceQuantity: normQty,
      referenceUnit:     normUnit,
    );

    // Replace existing entry for the same food name
    _overrides.removeWhere(
        (o) => o.canonicalMeal == normName);
    _overrides.add(override);

    await _persist();
    CloudSyncService.instance.syncMemoryBackground(override);

    debugPrint('[UserNutritionMemory] saved: "$normName" '
        '${finalCal.toStringAsFixed(3)} kcal/$normUnit '
        '| ref qty=$normQty $normUnit');
  }

  Future<void> deleteOverride(String rawMealName) async {
    final normName = FoodNameNormalizer.normalize(rawMealName);
    _overrides.removeWhere((o) => o.canonicalMeal == normName);
    await _persist();
  }

  /// Merge overrides hydrated from cloud into local memory.
  /// Called by CloudSyncService after a successful hydration.
  /// Cloud values WIN over local for the same food name (cloud is authoritative).
  Future<void> mergeFromCloud(List<UserMealOverride> cloudOverrides) async {
    for (final remote in cloudOverrides) {
      _overrides.removeWhere((o) => o.canonicalMeal == remote.canonicalMeal);
      _overrides.add(remote);
    }
    await _persist();
    debugPrint('[UserNutritionMemory] merged ${cloudOverrides.length} cloud overrides');
  }

  // ── Lookup ─────────────────────────────────────────────────────────────────

  /// Look up a memory match for [rawInput] (food name only, no quantity/unit).
  ///
  /// Returns a [NutritionResult] whose calories/protein are expressed as
  /// PER-UNIT-1 values in the stored canonical unit.
  ///
  /// The pipeline's [_itemFromMemory] scales the result by parsed.quantity
  /// (already in the same canonical unit after normalization).
  ///
  /// Returns null when:
  ///   - not ready
  ///   - no match with F1 ≥ 0.98
  NutritionResult? lookup(String rawInput) {
    if (!_ready || _overrides.isEmpty) return null;

    final normInput   = FoodNameNormalizer.normalize(rawInput);
    final inputTokens = UserMealOverride._tokenize(normInput);
    if (inputTokens.isEmpty) return null;

    UserMealOverride? bestMatch;
    double bestScore = 0.0;

    for (final override in _overrides) {
      if (override.originalTokens.isEmpty) continue;

      int matchCount = 0;
      for (final t in override.originalTokens) {
        if (inputTokens.contains(t)) matchCount++;
      }

      final recall    = matchCount / override.originalTokens.length;
      final precision = matchCount / inputTokens.length;
      double f1 = 0;
      if (precision + recall > 0) {
        f1 = 2 * (precision * recall) / (precision + recall);
      }

      if (f1 > bestScore) {
        bestScore = f1;
        bestMatch = override;
      }
    }

    // Strict threshold = 0.98 to prevent greedy matching.
    // "milkshake" (2 tokens: 'milkshake') vs "milk" (1 token: 'milk'):
    //   matchCount = 0 because 'milkshake' ≠ 'milk' → F1 = 0 → correctly rejected.
    if (bestMatch != null && bestScore >= 0.98) {
      debugPrint('[UserNutritionMemory] ✅ MATCH '
          '"${bestMatch.canonicalMeal}" f1=$bestScore '
          '| ${bestMatch.caloriesPerUnit.toStringAsFixed(3)} kcal/${bestMatch.referenceUnit}');
      return NutritionResult(
        canonicalMeal: bestMatch.canonicalMeal,
        items:         [],
        calories:      NutrientRange(
            min: bestMatch.caloriesPerUnit, max: bestMatch.caloriesPerUnit),
        protein:       NutrientRange(
            min: bestMatch.proteinPerUnit, max: bestMatch.proteinPerUnit),
        confidence:    0.99,
        warnings:      [],
        source:        'user_override',
        createdAt:     DateTime.now(),
      );
    }

    if (bestMatch != null) {
      debugPrint('[UserNutritionMemory] ❌ rejected '
          '"${bestMatch.canonicalMeal}" f1=$bestScore');
    }
    return null;
  }

  /// Returns the canonical unit stored for [rawFoodName], or null if unknown.
  /// Used by the pipeline to validate unit category compatibility before scaling.
  String? storedUnit(String rawFoodName) {
    final normName = FoodNameNormalizer.normalize(rawFoodName);
    for (final o in _overrides) {
      if (o.canonicalMeal == normName) return o.referenceUnit;
    }
    return null;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = _overrides.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_kOverrides, list);
  }
}
