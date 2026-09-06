import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import '../services/cloud_sync_service.dart';
import '../services/unit_normalizer.dart';
import '../services/nutrition_hydration_guard.dart';

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

// ─── OverrideSource ───────────────────────────────────────────────────────────

/// The origin of a [UserMealOverride] entry.
/// Used to show source badges in the ingredient editor and Nutrition Intelligence screen.
enum OverrideSource { userCorrected }

// ─── UserMealOverride ─────────────────────────────────────────────────────────

class UserMealOverride {
  final String canonicalMeal;      // normalized food name
  final double caloriesPerUnit;    // kcal per 1 referenceUnit
  final double proteinPerUnit;     // g protein per 1 referenceUnit
  final double? carbohydratesPerUnit; // g carbs per 1 referenceUnit
  final double? fatPerUnit;           // g fat per 1 referenceUnit
  final double? fiberPerUnit;         // g fiber per 1 referenceUnit
  final double referenceQuantity;  // quantity used when this was recorded
  final String referenceUnit;      // canonical unit (g / ml / scoop / …)
  final List<String> originalTokens;

  // ── Source metadata (added v2; all have defaults for backward-compat) ──────
  /// Who created this override.  Always 'user_corrected' for user-edited entries.
  final OverrideSource overrideSource;
  /// When this override was last written.
  final DateTime savedAt;
  /// Number of times the user has explicitly corrected this ingredient.
  final int correctionCount;

  UserMealOverride({
    required this.canonicalMeal,
    required this.caloriesPerUnit,
    required this.proteinPerUnit,
    this.carbohydratesPerUnit,
    this.fatPerUnit,
    this.fiberPerUnit,
    this.referenceQuantity = 1.0,
    this.referenceUnit     = 'serving',
    List<String>? originalTokens,
    this.overrideSource  = OverrideSource.userCorrected,
    DateTime?     savedAt,
    this.correctionCount = 1,
  })  : originalTokens = originalTokens ?? _tokenize(canonicalMeal),
        savedAt        = savedAt ?? DateTime.now();

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'canonicalMeal':     canonicalMeal,
        'caloriesPerUnit':   caloriesPerUnit,
        'proteinPerUnit':    proteinPerUnit,
        if (carbohydratesPerUnit != null) 'carbohydratesPerUnit': carbohydratesPerUnit,
        if (fatPerUnit != null) 'fatPerUnit': fatPerUnit,
        if (fiberPerUnit != null) 'fiberPerUnit': fiberPerUnit,
        'referenceQuantity': referenceQuantity,
        'referenceUnit':     referenceUnit,
        'originalTokens':    originalTokens,
        // Source metadata
        'overrideSource':  overrideSource.name,
        'savedAt':         savedAt.toIso8601String(),
        'correctionCount': correctionCount,
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
    final carbs = (json['carbohydratesPerUnit'] as num?)?.toDouble();
    final fat = (json['fatPerUnit'] as num?)?.toDouble();
    final fiber = (json['fiberPerUnit'] as num?)?.toDouble();

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
    double? finalCarbs = carbs;
    double? finalFat = fat;
    double? finalFiber = fiber;
    if (rawUnit != normUnit) {
      // e.g. stored kcal/kg → kcal/g: divide by 1000
      final mult = UnitNormalizer.normalizeQuantity(1.0, rawUnit); // grams per old unit
      if (mult > 0) {
        finalCal = cal / mult;
        finalPro = pro / mult;
        if (finalCarbs != null) finalCarbs = finalCarbs / mult;
        if (finalFat != null) finalFat = finalFat / mult;
        if (finalFiber != null) finalFiber = finalFiber / mult;
      }
    }

    // Normalize meal name on read as well
    final rawMeal = json['canonicalMeal'] as String? ?? '';
    final normMeal = FoodNameNormalizer.normalize(rawMeal);

    // Parse source metadata with safe defaults for old entries
    final sourceStr = json['overrideSource'] as String? ?? 'userCorrected';
    final source = OverrideSource.values.firstWhere(
      (e) => e.name == sourceStr,
      orElse: () => OverrideSource.userCorrected,
    );
    final savedAtRaw = json['savedAt'] as String?;
    final savedAt = savedAtRaw != null
        ? DateTime.tryParse(savedAtRaw) ?? DateTime.now()
        : DateTime.now();
    final correctionCount = (json['correctionCount'] as int?) ?? 1;

    return UserMealOverride(
      canonicalMeal:     normMeal,
      caloriesPerUnit:   finalCal,
      proteinPerUnit:    finalPro,
      carbohydratesPerUnit: finalCarbs,
      fatPerUnit:        finalFat,
      fiberPerUnit:      finalFiber,
      referenceQuantity: (json['referenceQuantity'] as num?)?.toDouble() ?? 1.0,
      referenceUnit:     normUnit,
      originalTokens:    List<String>.from(json['originalTokens'] ?? []),
      overrideSource:    source,
      savedAt:           savedAt,
      correctionCount:   correctionCount,
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
  String? _ownerUserId;

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
    _ownerUserId = prefs.getString('cached_owner_user_id_v1');
    _ready = true;
    debugPrint('[UserNutritionMemory] loaded ${_overrides.length} overrides from local storage (owner: $_ownerUserId)');
  }

  /// Internal ownership synchronization method called only by PersistenceService.
  void setOwnerId(String userId) {
    _ownerUserId = userId;
    debugPrint('[UserNutritionMemory] 🔒 cached owner ID synchronized to: $userId');
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
    double? carbohydratesPerUnit,
    double? fatPerUnit,
    double? fiberPerUnit,
    double referenceQuantity = 1.0,
    String referenceUnit     = defaultServingUnit,
  }) async {
    // Compute correctionCount: increment if entry already exists
    final existingNorm = FoodNameNormalizer.normalize(rawMealName);
    final existing = _overrides.where((o) => o.canonicalMeal == existingNorm).firstOrNull;
    final newCorrectionCount = (existing?.correctionCount ?? 0) + 1;
    // Normalize inputs on the way in
    final normName = FoodNameNormalizer.normalize(rawMealName);
    final normUnit = UnitNormalizer.normalizeUnit(referenceUnit);
    final normQty  = UnitNormalizer.normalizeQuantity(referenceQuantity, referenceUnit);

    // Rescale caloriesPerUnit to the normalized unit basis.
    // Example: caller saves 2 kcal per 'kg' → normalizer maps 'kg'→'g'
    // so it's really 0.002 kcal/g.  The multiplier is (1 g / 1000 g per kg).
    double finalCal = caloriesPerUnit;
    double finalPro = proteinPerUnit;
    double? finalCarbs = carbohydratesPerUnit ?? existing?.carbohydratesPerUnit;
    double? finalFat   = fatPerUnit ?? existing?.fatPerUnit;
    double? finalFiber = fiberPerUnit ?? existing?.fiberPerUnit;
    if (referenceUnit.trim().toLowerCase() != normUnit) {
      final mult = UnitNormalizer.normalizeQuantity(1.0, referenceUnit);
      if (mult > 0) {
        finalCal = caloriesPerUnit / mult;
        finalPro = proteinPerUnit  / mult;
        if (finalCarbs != null) finalCarbs = finalCarbs / mult;
        if (finalFat != null) finalFat = finalFat / mult;
        if (finalFiber != null) finalFiber = finalFiber / mult;
      }
    }

    final override = UserMealOverride(
      canonicalMeal:     normName,
      caloriesPerUnit:   finalCal,
      proteinPerUnit:    finalPro,
      carbohydratesPerUnit: finalCarbs,
      fatPerUnit:        finalFat,
      fiberPerUnit:      finalFiber,
      referenceQuantity: normQty,
      referenceUnit:     normUnit,
      overrideSource:    OverrideSource.userCorrected,
      savedAt:           DateTime.now(),
      correctionCount:   newCorrectionCount,
    );

    // Replace existing entry for the same food name
    _overrides.removeWhere(
        (o) => o.canonicalMeal == normName);
    _overrides.add(override);
    _ready = true;
    _ownerUserId = NutritionHydrationGuard.instance.currentUserId;

    await _persist();
    try {
      CloudSyncService.instance.syncMemoryBackground(override).catchError((_) {}).ignore();
    } catch (_) {}

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
  /// Uses a bidirectional "newer wins" resolution strategy based on savedAt.
  Future<void> mergeFromCloud(List<UserMealOverride> cloudOverrides) async {
    final toSyncBack = <UserMealOverride>[];

    // 1. Process cloud entries against local entries
    for (final remote in cloudOverrides) {
      final existingIndex = _overrides.indexWhere((o) => o.canonicalMeal == remote.canonicalMeal);
      if (existingIndex != -1) {
        final local = _overrides[existingIndex];
        if (local.savedAt.isAfter(remote.savedAt)) {
          // Local is newer! Keep local, queue upload of local to cloud
          toSyncBack.add(local);
        } else {
          // Cloud is newer (or equal). Overwrite local with remote.
          _overrides[existingIndex] = remote;
        }
      } else {
        // Not present locally. Add remote.
        _overrides.add(remote);
      }
    }

    // 2. Scan for local overrides that are completely missing from cloud (e.g. offline edits)
    final cloudMeals = cloudOverrides.map((o) => o.canonicalMeal).toSet();
    for (final local in _overrides) {
      if (!cloudMeals.contains(local.canonicalMeal)) {
        toSyncBack.add(local);
      }
    }

    _ownerUserId = NutritionHydrationGuard.instance.currentUserId;
    await _persist();
    debugPrint('[UserNutritionMemory] merged ${cloudOverrides.length} cloud overrides');

    // 3. Sync newer local entries back to cloud asynchronously
    for (final local in toSyncBack) {
      debugPrint('[UserNutritionMemory] Syncing newer local override for "${local.canonicalMeal}" back to cloud');
      CloudSyncService.instance.syncMemoryBackground(local);
    }
  }

  // ── Lookup ─────────────────────────────────────────────────────────────────

  /// Lookup with source metadata.  Returns the [NutritionResult] AND the
  /// [OverrideSource] that produced it.  Used by the ingredient editor to show
  /// the correct source badge (🤖 AI Estimate vs ✏️ User Corrected).
  ///
  /// Returns (null, OverrideSource.userCorrected) when no match is found —
  /// caller should treat null NutritionResult as "no stored override".
  (NutritionResult?, OverrideSource) lookupWithSource(String rawInput) {
    final result = lookup(rawInput);
    if (result == null) return (null, OverrideSource.userCorrected);
    final normInput = FoodNameNormalizer.normalize(rawInput);
    final match = _overrides.firstWhere(
      (o) => o.canonicalMeal == normInput,
      orElse: () => _overrides.firstWhere(
        (o) => o.originalTokens.isNotEmpty &&
            o.originalTokens.every(
                (t) => UserMealOverride._tokenize(normInput).contains(t)),
        orElse: () => _overrides.first,
      ),
    );
    return (result, match.overrideSource);
  }

  /// All stored overrides — exposed for the Nutrition Intelligence screen.
  List<UserMealOverride> get allOverrides => List.unmodifiable(_overrides);

  /// Look up a memory match for [rawInput] (food name only, no quantity/unit).
  ///
  /// FAIL CLOSED: returns null unless NutritionHydrationGuard is ready for
  /// the currently authenticated user. This prevents User A's personal
  /// nutrition corrections from being served to User B during account switches.
  ///
  /// Returns a [NutritionResult] whose calories/protein are expressed as
  /// PER-UNIT-1 values in the stored canonical unit.
  ///
  /// Returns null when:
  ///   - hydration guard is not ready for the current user
  ///   - not ready
  ///   - no match with F1 ≥ 0.98
  NutritionResult? lookup(String rawInput) {
    // FAIL CLOSED: user-specific correction store
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) {
      debugPrint('[UserNutritionMemory] 🔒 guard not ready — skipping override lookup for "$rawInput"');
      return null;
    }

    // DEFENSE-IN-DEPTH: cache-level ownership verification
    final currentUserId = NutritionHydrationGuard.instance.currentUserId;
    if (_ownerUserId == null || _ownerUserId != currentUserId) {
      debugPrint('[UserNutritionMemory] ⛔ OWNERSHIP MISMATCH at cache layer: '
          'cache owned by $_ownerUserId, current user is $currentUserId');
      return null;
    }

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
      final score = NutritionResult.calculateLocalQualityScore(
        bestMatch.caloriesPerUnit,
        bestMatch.proteinPerUnit,
        bestMatch.canonicalMeal,
        carbs: bestMatch.carbohydratesPerUnit,
        fat: bestMatch.fatPerUnit,
        fiber: bestMatch.fiberPerUnit,
      );

      final cal = NutrientRange(min: bestMatch.caloriesPerUnit, max: bestMatch.caloriesPerUnit);
      final pro = NutrientRange(min: bestMatch.proteinPerUnit, max: bestMatch.proteinPerUnit);
      final carbs = bestMatch.carbohydratesPerUnit != null
          ? NutrientRange(min: bestMatch.carbohydratesPerUnit!, max: bestMatch.carbohydratesPerUnit!)
          : null;
      final fat = bestMatch.fatPerUnit != null
          ? NutrientRange(min: bestMatch.fatPerUnit!, max: bestMatch.fatPerUnit!)
          : null;
      final fiber = bestMatch.fiberPerUnit != null
          ? NutrientRange(min: bestMatch.fiberPerUnit!, max: bestMatch.fiberPerUnit!)
          : null;

      return NutritionResult(
        canonicalMeal: bestMatch.canonicalMeal,
        items: [
          NutritionItem(
            name: bestMatch.canonicalMeal,
            quantity: bestMatch.referenceQuantity,
            unit: bestMatch.referenceUnit,
            estimated: false,
            mode: EstimationMode.packagedKnown,
            calories: cal,
            protein: pro,
            carbohydrates: carbs,
            fat: fat,
            fiber: fiber,
            eatingPatternScalarApplied: true,
          ),
        ],
        calories:      cal,
        protein:       pro,
        carbohydrates: carbs,
        fat:           fat,
        fiber:         fiber,
        confidence:    0.99,
        warnings:      const [],
        source:        'user_override',
        createdAt:     DateTime.now(),
        mealQualityScore: score,
        mealQualityExplanation: NutritionResult.getLocalQualityExplanation(score, bestMatch.canonicalMeal),
        mealQualityPositive: NutritionResult.getLocalQualityPositive(score, bestMatch.canonicalMeal),
        mealQualityImprovement: NutritionResult.getLocalQualityImprovement(score, bestMatch.canonicalMeal),
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

  /// Wipe overrides both in-memory and in local SharedPreferences.
  Future<void> clearAll() async {
    _overrides.clear();
    _ready = false; // force re-init on next login so init() re-reads clean prefs
    _ownerUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOverrides);
    debugPrint('[UserNutritionMemory] 🗑️  clearAll() complete — overrides wiped');
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list  = _overrides.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_kOverrides, list);
  }
}
