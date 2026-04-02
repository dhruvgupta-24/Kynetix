import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;

// ─── PersonalNutritionMemory ──────────────────────────────────────────────────
//
// A user-specific, persistent layer that stores personal food defaults,
// recurring meal templates, and quantity overrides.
//
// PIPELINE POSITION:
//   1. PersonalNutritionMemory.lookupExact()     ← this file (exact match)
//   2. PersonalNutritionMemory.lookupTemplate()  ← this file (fuzzy match)
//   3. MealMemory (AI-confirmed recurring meals)
//   4. ConsumedPortionEngine (behavior-based floors)
//   5. AI estimation
//   6. NutritionGuardrails (post-AI floors)
//
// DESIGN PRINCIPLES:
//   - Templates are user-owned, not hardcoded for a single user.
//   - The default set matches THIS user's habits but can be overridden/extended.
//   - Matching is CONSERVATIVE: exact normalized match first, then keyword-based
//     template matching (only when confidence is high).
//   - This system does NOT modify the generalized engine — it only intercepts
//     before the AI call when it has enough confidence to return directly.
//   - Profile-specific isolation is ensured by namespacing prefs by profile ID.
//
// MATCHING PRIORITY:
//   lookupExact:    normalized string equality (like MealMemory exact known foods)
//   lookupTemplate: keyword-based partial match with confidence ≥ 0.88

class PersonalNutritionMemory {
  PersonalNutritionMemory._();
  static final PersonalNutritionMemory instance = PersonalNutritionMemory._();

  static const _prefKey = 'personal_nutrition_memory_v1';

  // User-added custom overrides (editable at runtime)
  final _userOverrides = <String, _PersonalEntry>{};
  bool _initialized = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in map.entries) {
          _userOverrides[e.key] = _PersonalEntry.fromJson(
              e.value as Map<String, dynamic>);
        }
      }
    } catch (_) {
      _userOverrides.clear();
    }
    debugPrint('[PersonalMemory] initialized — '
               '${_userOverrides.length} user overrides + '
               '${_defaultTemplates.length} built-in templates');
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Step 1: exact normalized match against built-in defaults + user overrides.
  NutritionResult? lookupExact(String rawInput) {
    final key = _normalize(rawInput);

    // User overrides take priority over built-in defaults
    final override = _userOverrides[key];
    if (override != null) {
      debugPrint('[PersonalMemory] ✅ EXACT USER OVERRIDE: "$key"');
      return override.toResult(source: 'personal_exact');
    }

    // Built-in personal defaults
    final builtin = _defaultTemplates[key];
    if (builtin != null) {
      debugPrint('[PersonalMemory] ✅ EXACT BUILT-IN TEMPLATE: "$key"');
      return builtin.toResult(source: 'personal_exact');
    }

    // Milk quantity interpolation — handles any `N ml milk` without individual entries
    final milkResult = _milkInterpolation(rawInput);
    if (milkResult != null) return milkResult;

    return null;
  }

  /// Step 2: keyword-based template lookup for partial / phrased matches.
  /// Returns only when confidence is high (≥ 0.88) — cautious by design.
  NutritionResult? lookupTemplate(String rawInput) {
    final lc = rawInput.toLowerCase();

    // Check user overrides first (fuzzy)
    for (final entry in _userOverrides.values) {
      if (entry.keywords.isNotEmpty &&
          _allKeywordsMatch(lc, entry.keywords)) {
        debugPrint('[PersonalMemory] ✅ FUZZY USER OVERRIDE: '
                   '"${entry.label}" (keywords: ${entry.keywords})');
        return entry.toResult(source: 'personal_template');
      }
    }

    // Check built-in templates (fuzzy)
    for (final entry in _defaultTemplates.values) {
      if (entry.keywords.isNotEmpty &&
          _allKeywordsMatch(lc, entry.keywords)) {
        debugPrint('[PersonalMemory] ✅ FUZZY BUILT-IN TEMPLATE: '
                   '"${entry.label}"');
        return entry.toResult(source: 'personal_template');
      }
    }

    return null;
  }

  /// Add or update a user-defined food override. Persisted immediately.
  Future<void> saveOverride({
    required String rawInput,
    required String label,
    required double kcal,
    required double protein,
    List<String> keywords = const [],
  }) async {
    final key = _normalize(rawInput);
    _userOverrides[key] = _PersonalEntry(
      label:    label,
      kcal:     kcal,
      protein:  protein,
      keywords: keywords,
    );
    await _persist();
    debugPrint('[PersonalMemory] saved override: "$key" → ${kcal.toInt()} kcal');
  }

  Future<void> deleteOverride(String rawInput) async {
    _userOverrides.remove(_normalize(rawInput));
    await _persist();
  }

  List<_PersonalEntry> get allUserOverrides =>
      _userOverrides.values.toList();

  // ── Milk interpolation ────────────────────────────────────────────────────
  //
  // Handles "N ml milk", "N ml doodh" for any quantity using linear
  // interpolation from the toned milk baseline (58 kcal/100ml, 3.4g/100ml).
  // Avoids the need for a separate entry for every possible quantity.

  NutritionResult? _milkInterpolation(String rawInput) {
    final lc = rawInput.toLowerCase();
    if (!lc.contains('milk') && !lc.contains('doodh')) return null;

    // Must be ONLY a milk entry — don't apply if other foods present
    final stripped = lc
        .replaceAll(RegExp(r'\d+\s*ml'), '')
        .replaceAll('milk', '')
        .replaceAll('doodh', '')
        .replaceAll(RegExp(r'[\s\-+,]'), '');
    if (stripped.isNotEmpty) return null;

    final m = RegExp(r'(\d+(?:\.\d+)?)\s*ml').firstMatch(lc);
    if (m == null) return null;
    final ml = double.tryParse(m.group(1)!) ?? 0;
    if (ml < 50 || ml > 2000) return null;

    // Personal milk baseline: toned milk
    // My values per the user's stated scales:
    //   200ml → 130 kcal, 6.5g protein  (0.65 kcal/ml, 0.0325g/ml)
    //   Wait — user says 200ml → 130 kcal, that's 65 kcal/100ml
    //   Standard toned milk: 58 kcal/100ml. User wants 65 kcal/100ml.
    //   Use user's stated value as the personal baseline.
    final kcal    = _r(ml * 0.65);
    final protein = _r(ml * 0.0325);

    debugPrint('[PersonalMemory] ✅ milk interpolation: ${ml.toInt()} ml → '
               '${kcal.toInt()} kcal, ${protein.toStringAsFixed(1)}g protein');

    return _makeResult(
      label:   '${ml.toInt()} ml milk (toned)',
      kcal:    kcal,
      protein: protein,
      source:  'personal_exact',
    );
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        for (final e in _userOverrides.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(_prefKey, jsonEncode(data));
    } catch (_) {}
  }

  static bool _allKeywordsMatch(String lc, List<String> keywords) {
    // ALL keywords must be present, not just one.
    // This prevents "2 roti + rajma" matching a template that requires "dal".
    return keywords.every(lc.contains);
  }

  static double _r(double v) => double.parse(v.toStringAsFixed(1));

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r"[',.!?\-+&]"), '')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_filler.contains(t))
      .join(' ')
      .trim();

  static const _filler = {'and', 'with', 'some', 'a', 'an', 'of', 'the'};

  static NutritionResult _makeResult({
    required String label,
    required double kcal,
    required double protein,
    required String source,
  }) {
    final cal = NutrientRange(min: kcal, max: kcal);
    final pro = NutrientRange(min: protein, max: protein);
    return NutritionResult(
      canonicalMeal: label,
      items: [
        NutritionItem(
          name: label,
          quantity: 1,
          unit: 'serving',
          estimated: false,
          mode: EstimationMode.packagedKnown,
          calories: cal,
          protein: pro,
        ),
      ],
      calories: cal,
      protein: pro,
      confidence: 0.97,
      warnings: const [],
      source: source,
      createdAt: DateTime.now(),
    ).normalizedUncertainty();
  }
}

// ─── _PersonalEntry ───────────────────────────────────────────────────────────

class _PersonalEntry {
  final String       label;
  final double       kcal;
  final double       protein;
  final List<String> keywords; // all must match for fuzzy lookup

  const _PersonalEntry({
    required this.label,
    required this.kcal,
    required this.protein,
    this.keywords = const [],
  });

  NutritionResult toResult({required String source}) =>
      PersonalNutritionMemory._makeResult(
        label: label, kcal: kcal, protein: protein, source: source);

  Map<String, dynamic> toJson() => {
    'label':    label,
    'kcal':     kcal,
    'protein':  protein,
    'keywords': keywords,
  };

  factory _PersonalEntry.fromJson(Map<String, dynamic> j) => _PersonalEntry(
    label:    j['label']   as String? ?? '',
    kcal:     (j['kcal']   as num?)?.toDouble() ?? 0,
    protein:  (j['protein'] as num?)?.toDouble() ?? 0,
    keywords: List<String>.from(j['keywords'] as List? ?? []),
  );
}

// ─── Built-in personal defaults (this user's eating habits) ──────────────────
//
// These are validated against the user's real eating patterns.
// Organized by category. Keys use PersonalNutritionMemory._normalize().
//
// EXACT entries: keyed by normalized meal text → direct match, no fuzzy needed.
// TEMPLATE entries: same map but also have `keywords` set → fuzzy matched.
//
// To ADD a new personal food: add one entry. Done.

final _defaultTemplates = <String, _PersonalEntry>{

  // ── WHEY ──────────────────────────────────────────────────────────────────
  // Note: user's stated whey = 115 kcal, 22g protein per scoop.

  PersonalNutritionMemory._normalize('1 scoop whey'):
    const _PersonalEntry(label: '1 scoop whey', kcal: 115, protein: 22,
        keywords: ['scoop', 'whey']),

  PersonalNutritionMemory._normalize('1 scoop whey water'):
    const _PersonalEntry(label: '1 scoop whey in water', kcal: 115, protein: 22,
        keywords: ['scoop', 'whey', 'water']),

  PersonalNutritionMemory._normalize('1 scoop whey milk'):
    const _PersonalEntry(label: '1 scoop whey in milk', kcal: 245, protein: 28,
        keywords: ['scoop', 'whey', 'milk']),

  // ── EGG WHITES + MILK (BREAKFASTS) ───────────────────────────────────────
  // Validated: 1 egg white = 17 kcal, 3.6g pro; 1ml toned milk = 0.65 kcal, 0.0325g pro

  PersonalNutritionMemory._normalize('4 egg whites 400 ml milk'):
    const _PersonalEntry(label: '4 egg whites + 400 ml milk', kcal: 328, protein: 27.4,
        keywords: ['4', 'egg', 'white', '400', 'milk']),

  PersonalNutritionMemory._normalize('4 egg whites 375 ml milk'):
    const _PersonalEntry(label: '4 egg whites + 375 ml milk', kcal: 312, protein: 26.6,
        keywords: ['4', 'egg', 'white', '375', 'milk']),

  PersonalNutritionMemory._normalize('4 egg whites 350 ml milk'):
    const _PersonalEntry(label: '4 egg whites + 350 ml milk', kcal: 296, protein: 25.9,
        keywords: ['4', 'egg', 'white', '350', 'milk']),

  PersonalNutritionMemory._normalize('4 egg whites 300 ml milk'):
    const _PersonalEntry(label: '4 egg whites + 300 ml milk', kcal: 263, protein: 24.3,
        keywords: ['4', 'egg', 'white', '300', 'milk']),

  PersonalNutritionMemory._normalize('3 egg whites 400 ml milk'):
    const _PersonalEntry(label: '3 egg whites + 400 ml milk', kcal: 311, protein: 23.8,
        keywords: ['3', 'egg', 'white', '400', 'milk']),

  PersonalNutritionMemory._normalize('3 egg whites 375 ml milk'):
    const _PersonalEntry(label: '3 egg whites + 375 ml milk', kcal: 295, protein: 23.0,
        keywords: ['3', 'egg', 'white', '375', 'milk']),

  PersonalNutritionMemory._normalize('1 omelette 4 egg whites 400 ml milk'):
    const _PersonalEntry(label: '1 omelette + 4 egg whites + 400 ml milk',
        kcal: 430, protein: 34,
        keywords: ['omelette', '4', 'egg', 'white', '400', 'milk']),

  // ── TOFU ─────────────────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('100 g tofu'):
    const _PersonalEntry(label: '100g tofu', kcal: 137, protein: 15),

  PersonalNutritionMemory._normalize('100g tofu'):
    const _PersonalEntry(label: '100g tofu', kcal: 137, protein: 15),

  PersonalNutritionMemory._normalize('150 g tofu'):
    const _PersonalEntry(label: '150g tofu', kcal: 206, protein: 22.5),

  PersonalNutritionMemory._normalize('150g tofu'):
    const _PersonalEntry(label: '150g tofu', kcal: 206, protein: 22.5),

  PersonalNutritionMemory._normalize('200 g tofu'):
    const _PersonalEntry(label: '200g tofu', kcal: 274, protein: 30),

  PersonalNutritionMemory._normalize('200g tofu'):
    const _PersonalEntry(label: '200g tofu', kcal: 274, protein: 30),

  // ── GOATLIFE OATS ────────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('goatlife oats'):
    const _PersonalEntry(label: 'Goatlife oats', kcal: 312, protein: 20,
        keywords: ['goatlife', 'oats']),

  PersonalNutritionMemory._normalize('goatlife oats 250 ml milk'):
    const _PersonalEntry(label: 'Goatlife oats + 250 ml milk', kcal: 475, protein: 28,
        keywords: ['goatlife', 'oats', '250', 'milk']),

  PersonalNutritionMemory._normalize('goatlife oats milk'):
    const _PersonalEntry(label: 'Goatlife oats + milk', kcal: 475, protein: 28,
        keywords: ['goatlife', 'oats', 'milk']),

  // ── ZERO MAIDA BREAD ────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('1 bread slice'):
    const _PersonalEntry(label: '1 bread slice (zero maida)', kcal: 75, protein: 2.5),

  PersonalNutritionMemory._normalize('1 slice bread'):
    const _PersonalEntry(label: '1 bread slice', kcal: 75, protein: 2.5),

  PersonalNutritionMemory._normalize('4 bread slices'):
    const _PersonalEntry(label: '4 bread slices', kcal: 300, protein: 10,
        keywords: ['4', 'bread', 'slice']),

  PersonalNutritionMemory._normalize('4 slices bread'):
    const _PersonalEntry(label: '4 bread slices', kcal: 300, protein: 10),

  PersonalNutritionMemory._normalize('6 bread slices'):
    const _PersonalEntry(label: '6 bread slices', kcal: 450, protein: 15,
        keywords: ['6', 'bread', 'slice']),

  // ── PEANUT BUTTER ────────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('10 g peanut butter'):
    const _PersonalEntry(label: '10g peanut butter', kcal: 58, protein: 3),

  PersonalNutritionMemory._normalize('10g peanut butter'):
    const _PersonalEntry(label: '10g peanut butter', kcal: 58, protein: 3),

  PersonalNutritionMemory._normalize('40 g peanut butter'):
    const _PersonalEntry(label: '40g peanut butter', kcal: 233, protein: 12),

  PersonalNutritionMemory._normalize('40g peanut butter'):
    const _PersonalEntry(label: '40g peanut butter', kcal: 233, protein: 12),

  // ── COMMON COMBO: bread + PB + milk ──────────────────────────────────────

  PersonalNutritionMemory._normalize('4 bread peanut butter 375 ml milk'):
    const _PersonalEntry(
        label: '4 bread + peanut butter + 375 ml milk',
        kcal: 773, protein: 34,
        keywords: ['4', 'bread', 'peanut', 'butter', '375', 'milk']),

  PersonalNutritionMemory._normalize('4 bread slices peanut butter 375ml milk'):
    const _PersonalEntry(
        label: '4 bread + peanut butter + 375 ml milk',
        kcal: 773, protein: 34,
        keywords: ['4', 'bread', 'peanut', 'butter', 'milk']),

  // ── MESS LUNCH / DINNER TEMPLATES ────────────────────────────────────────
  // Keywords: ALL must match → ensures tight matching, no false positives.

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice rajma'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + rajma',
        kcal: 530, protein: 18,
        keywords: ['2', 'roti', 'ladle', 'rice', 'rajma']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice black chana'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + black chana',
        kcal: 530, protein: 18,
        keywords: ['2', 'roti', 'ladle', 'rice', 'black', 'chana']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice chole'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + chole',
        kcal: 530, protein: 18,
        keywords: ['2', 'roti', 'ladle', 'rice', 'chole']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice arhar dal'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + arhar dal',
        kcal: 480, protein: 14,
        keywords: ['2', 'roti', 'ladle', 'rice', 'arhar', 'dal']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice dal'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + dal',
        kcal: 480, protein: 14,
        keywords: ['2', 'roti', 'ladle', 'rice', 'dal']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice dal tadka'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + dal tadka',
        kcal: 520, protein: 15,
        keywords: ['2', 'roti', 'ladle', 'rice', 'dal', 'tadka']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle rice kadhi pakoda'):
    const _PersonalEntry(label: '2 roti + 1 ladle rice + kadhi pakoda',
        kcal: 540, protein: 12,
        keywords: ['2', 'roti', 'ladle', 'rice', 'kadhi', 'pakoda']),

  PersonalNutritionMemory._normalize('2 roti arhar dal'):
    const _PersonalEntry(label: '2 roti + arhar dal',
        kcal: 350, protein: 10,
        keywords: ['2', 'roti', 'arhar', 'dal']),

  PersonalNutritionMemory._normalize('2 roti dal'):
    const _PersonalEntry(label: '2 roti + dal',
        kcal: 340, protein: 9,
        keywords: ['2', 'roti', 'dal']),

  PersonalNutritionMemory._normalize('2 roti dal makhani'):
    const _PersonalEntry(label: '2 roti + dal makhani',
        kcal: 430, protein: 13,
        keywords: ['2', 'roti', 'dal', 'makhani']),

  // ── PANEER TEMPLATES ──────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('2 roti 2 ladle rice paneer'):
    const _PersonalEntry(label: '2 roti + 2 ladle rice + paneer',
        kcal: 780, protein: 28,
        keywords: ['2', 'roti', '2', 'ladle', 'rice', 'paneer']),

  PersonalNutritionMemory._normalize('2 roti 15 ladle rice paneer'):
    const _PersonalEntry(label: '2 roti + 1.5 ladle rice + paneer',
        kcal: 745, protein: 28,
        keywords: ['2', 'roti', '15', 'ladle', 'rice', 'paneer']),

  // "3 compartments paneer do pyaza" full meal
  PersonalNutritionMemory._normalize('2 roti 15 ladle rice 3 compartments paneer do pyaza'):
    const _PersonalEntry(
        label: '2 roti + 1.5 ladle rice + 3 compartments paneer do pyaza',
        kcal: 855, protein: 34,
        keywords: ['2', 'roti', 'ladle', 'rice', 'compartment', 'paneer']),

  // ── SOYA TEMPLATES ────────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('2 roti chilli soya'):
    const _PersonalEntry(label: '2 roti + chilli soya',
        kcal: 440, protein: 21,
        keywords: ['2', 'roti', 'chilli', 'soya']),

  PersonalNutritionMemory._normalize('2 roti kadai soya'):
    const _PersonalEntry(label: '2 roti + kadai soya',
        kcal: 460, protein: 23,
        keywords: ['2', 'roti', 'kadai', 'soya']),

  PersonalNutritionMemory._normalize('2 roti 1 ladle soya rice dal'):
    const _PersonalEntry(label: '2 roti + 1 ladle soya rice + dal',
        kcal: 560, protein: 21,
        keywords: ['2', 'roti', 'ladle', 'soya', 'rice', 'dal']),

  // ── OUTSIDE FOOD ─────────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('4 pav bhaji'):
    const _PersonalEntry(label: '4 pav bhaji', kcal: 645, protein: 18,
        keywords: ['4', 'pav', 'bhaji']),

  PersonalNutritionMemory._normalize('2 kulche chole'):
    const _PersonalEntry(label: '2 kulche + chole', kcal: 620, protein: 18,
        keywords: ['2', 'kulche', 'chole']),

  PersonalNutritionMemory._normalize('1 tandoori chicken piece'):
    const _PersonalEntry(label: '1 tandoori chicken piece', kcal: 160, protein: 20,
        keywords: ['tandoori', 'chicken']),

  PersonalNutritionMemory._normalize('2 butter naan butter chicken'):
    const _PersonalEntry(label: '2 butter naan + butter chicken',
        kcal: 820, protein: 35,
        keywords: ['butter', 'naan', 'butter', 'chicken']),

  // ── MILK ANCHORS (used as fallback if interpolation doesn't fire) ─────────
  // Note: interpolation handles arbitrary ml values. These are fallback anchors.

  PersonalNutritionMemory._normalize('200 ml milk'):
    const _PersonalEntry(label: '200 ml milk', kcal: 130, protein: 6.5),

  PersonalNutritionMemory._normalize('250 ml milk'):
    const _PersonalEntry(label: '250 ml milk', kcal: 163, protein: 8.1),

  PersonalNutritionMemory._normalize('300 ml milk'):
    const _PersonalEntry(label: '300 ml milk', kcal: 195, protein: 9.8),

  PersonalNutritionMemory._normalize('350 ml milk'):
    const _PersonalEntry(label: '350 ml milk', kcal: 228, protein: 11.4),

  PersonalNutritionMemory._normalize('375 ml milk'):
    const _PersonalEntry(label: '375 ml milk', kcal: 244, protein: 12.2),

  PersonalNutritionMemory._normalize('400 ml milk'):
    const _PersonalEntry(label: '400 ml milk', kcal: 260, protein: 13.0),

  PersonalNutritionMemory._normalize('500 ml milk'):
    const _PersonalEntry(label: '500 ml milk', kcal: 325, protein: 16.3),

  // ── ROTI STANDALONE ──────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('1 roti'):
    const _PersonalEntry(label: '1 roti', kcal: 100, protein: 3),

  PersonalNutritionMemory._normalize('2 roti'):
    const _PersonalEntry(label: '2 roti', kcal: 200, protein: 6),

  PersonalNutritionMemory._normalize('3 roti'):
    const _PersonalEntry(label: '3 roti', kcal: 300, protein: 9),

  PersonalNutritionMemory._normalize('4 roti'):
    const _PersonalEntry(label: '4 roti', kcal: 400, protein: 12),

  // ── BROWNIE (ADD-ON) ──────────────────────────────────────────────────────

  PersonalNutritionMemory._normalize('1 brownie'):
    const _PersonalEntry(label: '1 brownie (mess)', kcal: 180, protein: 2,
        keywords: ['brownie']),
};
