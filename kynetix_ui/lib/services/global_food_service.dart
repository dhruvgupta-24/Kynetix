import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;

class GlobalFoodItem {
  final String id;
  final String canonicalName;
  final List<String> aliases;
  final double caloriesMid;
  final double proteinMid;
  final double? carbsMid;
  final double? fatMid;
  final double? fiberMid;
  final double referenceQuantity;
  final String referenceUnit;
  final double qualityScore;
  final String source;
  final String? curatedBy;

  const GlobalFoodItem({
    required this.id,
    required this.canonicalName,
    required this.aliases,
    required this.caloriesMid,
    required this.proteinMid,
    this.carbsMid,
    this.fatMid,
    this.fiberMid,
    required this.referenceQuantity,
    required this.referenceUnit,
    this.qualityScore = 0.85,
    this.source = 'kynetix_curated',
    this.curatedBy,
  });

  factory GlobalFoodItem.fromJson(Map<String, dynamic> json) {
    return GlobalFoodItem(
      id: json['id'] as String? ?? '',
      canonicalName: json['canonical_name'] as String? ?? '',
      aliases: (json['aliases'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      caloriesMid: (json['calories_mid'] as num?)?.toDouble() ?? 0.0,
      proteinMid: (json['protein_mid'] as num?)?.toDouble() ?? 0.0,
      carbsMid: (json['carbs_mid'] as num?)?.toDouble(),
      fatMid: (json['fat_mid'] as num?)?.toDouble(),
      fiberMid: (json['fiber_mid'] as num?)?.toDouble(),
      referenceQuantity: (json['reference_quantity'] as num?)?.toDouble() ?? 1.0,
      referenceUnit: json['reference_unit'] as String? ?? 'serving',
      qualityScore: (json['quality_score'] as num?)?.toDouble() ?? 0.85,
      source: json['source'] as String? ?? 'kynetix_curated',
      curatedBy: json['curated_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonical_name': canonicalName,
    'aliases': aliases,
    'calories_mid': caloriesMid,
    'protein_mid': proteinMid,
    'carbs_mid': carbsMid,
    'fat_mid': fatMid,
    'fiber_mid': fiberMid,
    'reference_quantity': referenceQuantity,
    'reference_unit': referenceUnit,
    'quality_score': qualityScore,
    'source': source,
    'curated_by': curatedBy,
  };

  NutritionResult toNutritionResult({double quantity = 1.0}) {
    final scale = referenceQuantity > 0 ? (quantity / referenceQuantity) : quantity;
    final c = caloriesMid * scale;
    final p = proteinMid * scale;
    final carb = carbsMid != null ? carbsMid! * scale : null;
    final fat = fatMid != null ? fatMid! * scale : null;
    final fib = fiberMid != null ? fiberMid! * scale : null;

    final item = NutritionItem(
      name: canonicalName,
      quantity: quantity,
      unit: referenceUnit,
      estimated: false,
      mode: EstimationMode.directQuantity,
      calories: NutrientRange(min: c, max: c),
      protein: NutrientRange(min: p, max: p),
      carbohydrates: carb != null ? NutrientRange(min: carb, max: carb) : null,
      fat: fat != null ? NutrientRange(min: fat, max: fat) : null,
      fiber: fib != null ? NutrientRange(min: fib, max: fib) : null,
    );

    return NutritionResult(
      canonicalMeal: canonicalName,
      items: [item],
      calories: NutrientRange(min: c, max: c),
      protein: NutrientRange(min: p, max: p),
      carbohydrates: carb != null ? NutrientRange(min: carb, max: carb) : null,
      fat: fat != null ? NutrientRange(min: fat, max: fat) : null,
      fiber: fib != null ? NutrientRange(min: fib, max: fib) : null,
      mealQualityScore: (qualityScore <= 1.0 ? (qualityScore * 100).round() : qualityScore.round()),
      confidence: 0.95,
      warnings: const [],
      source: 'global_default',
      createdAt: DateTime.now(),
    );
  }
}

/// Global Kynetix Food Defaults Service.
/// Serves canonical global defaults across ALL users.
/// Completely read-only for standard users; writable only by curators with database RLS enforcement.
class GlobalFoodService {
  GlobalFoodService._();
  static final GlobalFoodService instance = GlobalFoodService._();

  static const _kGlobalCache = 'global_food_defaults_cache_v1';
  final Map<String, GlobalFoodItem> _itemsByCanonical = {};
  final Map<String, String> _aliasMap = {};
  bool _initialized = false;

  bool get isInitialized => _initialized;
  List<GlobalFoodItem> get allDefaults => List.unmodifiable(_itemsByCanonical.values);

  /// Normalize food query string (lowercase, trimmed, collapsed spaces)
  String normalize(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Initialize and load cached global defaults, then optionally fetch fresh from Supabase.
  Future<void> init({bool fetchRemote = true}) async {
    if (_initialized) return;
    _initialized = true;

    // 1. Seed compiled-in canonical defaults first
    _seedCompiledDefaults();

    // 2. Load from local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_kGlobalCache);
      if (cachedJson != null) {
        final list = jsonDecode(cachedJson) as List<dynamic>;
        for (final item in list) {
          final food = GlobalFoodItem.fromJson(item as Map<String, dynamic>);
          _register(food);
        }
      }
    } catch (e) {
      debugPrint('[GlobalFoodService] Failed to load local cache: $e');
    }

    // 3. Fetch from remote if Supabase is initialized
    if (fetchRemote) {
      refreshFromRemote().ignore();
    }
  }

  void _seedCompiledDefaults() {
    // Initial canonical default: roti
    _register(const GlobalFoodItem(
      id: 'default_roti',
      canonicalName: 'roti',
      aliases: ['chapati', 'phulka', 'roties', 'chapatis'],
      caloriesMid: 200.0,
      proteinMid: 6.0,
      carbsMid: 35.0,
      fatMid: 4.0,
      fiberMid: 2.0,
      referenceQuantity: 1.0,
      referenceUnit: 'piece',
      qualityScore: 0.90,
      source: 'kynetix_curated',
    ));
  }

  void _register(GlobalFoodItem item) {
    final norm = normalize(item.canonicalName);
    _itemsByCanonical[norm] = item;
    for (final alias in item.aliases) {
      _aliasMap[normalize(alias)] = norm;
    }
  }

  @visibleForTesting
  void registerForTesting({
    required String canonicalName,
    required double caloriesPerUnit,
    required double proteinPerUnit,
    String referenceUnit = 'piece',
    double referenceQuantity = 1.0,
  }) {
    _register(GlobalFoodItem(
      id: 'test_$canonicalName',
      canonicalName: canonicalName,
      aliases: const [],
      caloriesMid: caloriesPerUnit,
      proteinMid: proteinPerUnit,
      referenceQuantity: referenceQuantity,
      referenceUnit: referenceUnit,
    ));
  }

  /// Get item definition if present
  GlobalFoodItem? getItem(String rawInput) {
    final norm = normalize(rawInput);
    final direct = _itemsByCanonical[norm];
    if (direct != null) return direct;
    final targetCanonical = _aliasMap[norm];
    if (targetCanonical != null) return _itemsByCanonical[targetCanonical];
    return null;
  }

  /// Exact or alias lookup against global defaults
  NutritionResult? lookup(String rawInput, {double quantity = 1.0}) {
    final item = getItem(rawInput);
    if (item != null) {
      return item.toNutritionResult(quantity: quantity);
    }
    return null;
  }

  /// Fetch fresh defaults from Supabase public.global_food_defaults
  Future<void> refreshFromRemote() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('global_food_defaults')
          .select()
          .order('canonical_name');

      final list = (response as List<dynamic>)
          .map((row) => GlobalFoodItem.fromJson(row as Map<String, dynamic>))
          .toList();

      for (final item in list) {
        _register(item);
      }

      // Persist to local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kGlobalCache,
        jsonEncode(_itemsByCanonical.values.map((e) => e.toJson()).toList()),
      );
      debugPrint('[GlobalFoodService] ✅ Refreshed ${_itemsByCanonical.length} global food defaults');
    } catch (e) {
      debugPrint('[GlobalFoodService] Remote refresh skipped/failed: $e');
    }
  }
}
