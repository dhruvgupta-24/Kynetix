import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import '../services/cloud_sync_service.dart';

class UserMealOverride {
  final String canonicalMeal;
  final double calories;
  final double protein;
  final List<String> originalTokens;

  UserMealOverride({
    required this.canonicalMeal,
    required this.calories,
    required this.protein,
    List<String>? originalTokens,
  }) : originalTokens = originalTokens ?? _tokenize(canonicalMeal);

  Map<String, dynamic> toJson() => {
        'canonicalMeal': canonicalMeal,
        'calories': calories,
        'protein': protein,
        'originalTokens': originalTokens,
      };

  factory UserMealOverride.fromJson(Map<String, dynamic> json) => UserMealOverride(
        canonicalMeal: json['canonicalMeal'] as String,
        calories: (json['calories'] as num).toDouble(),
        protein: (json['protein'] as num).toDouble(),
        originalTokens: List<String>.from(json['originalTokens'] ?? []),
      );

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

  Future<void> saveOverride(String mealName, double cal, double pro) async {
    final override = UserMealOverride(
        canonicalMeal: mealName, calories: cal, protein: pro);
    // Remove old exact match
    _overrides.removeWhere(
        (o) => o.canonicalMeal.toLowerCase() == mealName.toLowerCase());
    _overrides.add(override);
    await _persist();
    
    CloudSyncService.instance.syncMemoryBackground(override);
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

      // directional overlap
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

    // Confidence threshold needs to be high to prevent overly generous fuzzy matches
    // e.g. input="paneer wrap" and override="paneer makhani wrap" -> f1=0.8. We require > 0.82.
    if (bestMatch != null && bestScore >= 0.82) {
      debugPrint('[UserNutritionMemory] match: "${bestMatch.canonicalMeal}" score: $bestScore');
      return NutritionResult(
        canonicalMeal: bestMatch.canonicalMeal,
        items: [],
        calories: NutrientRange(min: bestMatch.calories, max: bestMatch.calories),
        protein: NutrientRange(min: bestMatch.protein, max: bestMatch.protein),
        confidence: 0.99,
        warnings: [],
        source: 'user_override',
        createdAt: DateTime.now(),
      );
    }

    if (bestMatch != null) {
      debugPrint('[UserNutritionMemory] match rejected: "${bestMatch.canonicalMeal}" score: $bestScore');
    }

    return null;
  }
}
