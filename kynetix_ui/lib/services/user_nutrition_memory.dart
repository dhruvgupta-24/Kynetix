import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import '../services/cloud_sync_service.dart';

class UserMealOverride {
  final String canonicalMeal;
  /// Per-unit-1 calories. e.g. if 150 g tofu = 80 kcal, this stores 80/150.
  final double caloriesPerUnit;
  /// Per-unit-1 protein.
  final double proteinPerUnit;
  /// The quantity at which this value was originally recorded (for scaling hints
  /// and proportional fallback when the input quantity differs greatly).
  final double referenceQuantity;
  /// The unit used when this was recorded (e.g. "g", "ml", "scoop").
  final String referenceUnit;
  final List<String> originalTokens;

  UserMealOverride({
    required this.canonicalMeal,
    required this.caloriesPerUnit,
    required this.proteinPerUnit,
    this.referenceQuantity = 1.0,
    this.referenceUnit = 'serving',
    List<String>? originalTokens,
  }) : originalTokens = originalTokens ?? _tokenize(canonicalMeal);

  Map<String, dynamic> toJson() => {
        'canonicalMeal':     canonicalMeal,
        'caloriesPerUnit':   caloriesPerUnit,
        'proteinPerUnit':    proteinPerUnit,
        'referenceQuantity': referenceQuantity,
        'referenceUnit':     referenceUnit,
        'originalTokens':    originalTokens,
        // Legacy field aliases so old stored data can still be read
        'calories': caloriesPerUnit,
        'protein':  proteinPerUnit,
      };

  factory UserMealOverride.fromJson(Map<String, dynamic> json) {
    // Support both new 'caloriesPerUnit' and old 'calories' key (migration).
    final cal = (json['caloriesPerUnit'] as num?)?.toDouble()
        ?? (json['calories'] as num?)?.toDouble()
        ?? 0.0;
    final pro = (json['proteinPerUnit'] as num?)?.toDouble()
        ?? (json['protein'] as num?)?.toDouble()
        ?? 0.0;
    return UserMealOverride(
      canonicalMeal:     json['canonicalMeal'] as String,
      caloriesPerUnit:   cal,
      proteinPerUnit:    pro,
      referenceQuantity: (json['referenceQuantity'] as num?)?.toDouble() ?? 1.0,
      referenceUnit:     json['referenceUnit'] as String? ?? 'serving',
      originalTokens:    List<String>.from(json['originalTokens'] ?? []),
    );
  }

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

class UserNutritionMemory {
  UserNutritionMemory._();
  static final UserNutritionMemory instance = UserNutritionMemory._();

  static const _kOverrides = 'user_meal_overrides_v1';
  final List<UserMealOverride> _overrides = [];
  bool _ready = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kOverrides) ?? [];
    _overrides.clear();
    for (final s in list) {
      try {
        _overrides.add(UserMealOverride.fromJson(
            jsonDecode(s) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[UserNutritionMemory] failed parsing override: $e');
      }
    }
    _ready = true;
  }

  /// Save a per-unit-1 recurring memory entry.
  ///
  /// [caloriesPerUnit] and [proteinPerUnit] must ALREADY be divided by
  /// [referenceQuantity] at the call site. This class stores raw per-unit
  /// values so [_itemFromMemory] can scale them correctly by parsed.quantity.
  Future<void> saveOverride(
    String mealName,
    double caloriesPerUnit,
    double proteinPerUnit, {
    double referenceQuantity = 1.0,
    String referenceUnit = 'serving',
  }) async {
    final override = UserMealOverride(
      canonicalMeal:     mealName,
      caloriesPerUnit:   caloriesPerUnit,
      proteinPerUnit:    proteinPerUnit,
      referenceQuantity: referenceQuantity,
      referenceUnit:     referenceUnit,
    );
    _overrides.removeWhere(
        (o) => o.canonicalMeal.toLowerCase() == mealName.toLowerCase());
    _overrides.add(override);
    await _persist();

    // Sync the legacy-compatible shape to Supabase
    final legacyOverride = _toLegacyShape(override);
    CloudSyncService.instance.syncMemoryBackground(legacyOverride);
  }

  Future<void> deleteOverride(String mealName) async {
    _overrides.removeWhere(
        (o) => o.canonicalMeal.toLowerCase() == mealName.toLowerCase());
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _overrides.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_kOverrides, list);
  }

  /// Returns a [NutritionResult] whose calories/protein are per-unit-1.
  /// The pipeline's [_itemFromMemory] scales these by parsed.quantity.
  NutritionResult? lookup(String input) {
    if (!_ready || _overrides.isEmpty) return null;

    final inputTokens = UserMealOverride._tokenize(input);
    if (inputTokens.isEmpty) return null;

    UserMealOverride? bestMatch;
    double bestScore = 0.0;

    for (final override in _overrides) {
      if (override.originalTokens.isEmpty) continue;

      int matchCount = 0;
      for (final t in override.originalTokens) {
        if (inputTokens.contains(t)) matchCount++;
      }

      final recall = matchCount / override.originalTokens.length;
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

    // 0.98 threshold prevents greedy hijacking (e.g. "mango shake" vs "mango").
    if (bestMatch != null && bestScore >= 0.98) {
      debugPrint(
          '[UserNutritionMemory] match: "${bestMatch.canonicalMeal}" '
          'score: $bestScore | perUnit cal=${bestMatch.caloriesPerUnit.toStringAsFixed(2)} '
          'refQty=${bestMatch.referenceQuantity} ${bestMatch.referenceUnit}');
      // Return per-unit-1 values. The pipeline scales by parsed.quantity.
      return NutritionResult(
        canonicalMeal: bestMatch.canonicalMeal,
        items: [],
        calories: NutrientRange(min: bestMatch.caloriesPerUnit, max: bestMatch.caloriesPerUnit),
        protein: NutrientRange(min: bestMatch.proteinPerUnit,   max: bestMatch.proteinPerUnit),
        confidence: 0.99,
        warnings: [],
        source: 'user_override',
        createdAt: DateTime.now(),
      );
    }

    if (bestMatch != null) {
      debugPrint('[UserNutritionMemory] match rejected: '
          '"${bestMatch.canonicalMeal}" score: $bestScore');
    }

    return null;
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Converts to the legacy [UserMealOverride]-compatible shape that
  /// [CloudSyncService.syncMemoryBackground] expects.
  static dynamic _toLegacyShape(UserMealOverride o) {
    // CloudSyncService accepts any object with a .toJson() and .canonicalMeal.
    // UserMealOverride.toJson() already writes legacy 'calories'/'protein' keys
    // so Supabase stays compatible.
    return o;
  }
}
