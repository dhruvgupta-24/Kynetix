import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;
import '../services/nutrition_hydration_guard.dart';

// ─── MealMemoryEntry ─────────────────────────────────────────────────────────

class MealMemoryEntry {
  final String          id;
  final String          rawInput;
  final String          normalizedInput;
  NutritionResult       result;
  int                   timesUsed;
  final DateTime        createdAt;
  DateTime              updatedAt;

  MealMemoryEntry({
    required this.id,
    required this.rawInput,
    required this.normalizedInput,
    required this.result,
    required this.timesUsed,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id':              id,
        'rawInput':        rawInput,
        'normalizedInput': normalizedInput,
        'result':          result.toJson(),
        'timesUsed':       timesUsed,
        'createdAt':       createdAt.toIso8601String(),
        'updatedAt':       updatedAt.toIso8601String(),
      };

  factory MealMemoryEntry.fromJson(Map<String, dynamic> j) => MealMemoryEntry(
        id:              j['id']              as String? ?? '',
        rawInput:        j['rawInput']        as String? ?? '',
        normalizedInput: j['normalizedInput'] as String? ?? '',
        result:          NutritionResult.fromJson(
            j['result'] as Map<String, dynamic>? ?? {}),
        timesUsed:       j['timesUsed'] as int? ?? 1,
        createdAt:       DateTime.tryParse(j['createdAt'] as String? ?? '') ??
                         DateTime.now(),
        updatedAt:       DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
                         DateTime.now(),
      );
}

class MealCandidateEntry {
  final String normalizedInput;
  NutritionResult latestResult;
  int seenCount;
  int stableHits;
  final DateTime createdAt;
  DateTime updatedAt;

  MealCandidateEntry({
    required this.normalizedInput,
    required this.latestResult,
    required this.seenCount,
    required this.stableHits,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'normalizedInput': normalizedInput,
        'latestResult': latestResult.toJson(),
        'seenCount': seenCount,
        'stableHits': stableHits,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MealCandidateEntry.fromJson(Map<String, dynamic> j) => MealCandidateEntry(
        normalizedInput: j['normalizedInput'] as String? ?? '',
        latestResult: NutritionResult.fromJson(
          j['latestResult'] as Map<String, dynamic>? ?? {},
        ),
        seenCount: j['seenCount'] as int? ?? 1,
        stableHits: j['stableHits'] as int? ?? 1,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

// ─── MealMemory ──────────────────────────────────────────────────────────────

/// Words stripped during cache-key normalization. Top-level so the static
/// [MealMemory.normalize] method can reference it.
const _fillerWords = {'and', 'with', 'some', 'a', 'an', 'of', 'the'};

// ─── Two-tier token-alias guards ─────────────────────────────────────────────
//
// When a query is a strict token-subset of a stored key (all query tokens
// appear in the stored key AND the stored key has exactly 1 extra token),
// the match is allowed ONLY if the extra token is in _safeQualifiers.
//
// An extra token in _ingredientModifiers means the stored food is
// nutritionally DIFFERENT from the query (e.g. "dal" ≠ "dal makhani").
// These matches are ALWAYS rejected, regardless of the ≤1 extra token rule.
//
// Any extra token NOT in either list → conservative reject.

/// Non-nutritional brand/format/texture qualifiers that do not change the
/// core food identity. Matching is ALLOWED when the extra token is one of these.
const _safeQualifiers = <String>{
  'biscuit', 'cookie', 'crackers', 'protein', 'powder',
  'shake', 'concentrate', 'isolate', 'hydrolysate',
  'bar', 'wafer', 'flavour', 'flavor', 'vanilla',
  'chocolate', 'unflavored', 'plain',
  'original', 'classic', 'lite', 'light', 'zero',
};

/// Ingredients and cooking modifiers that CHANGE the nutritional profile
/// of the base food. Matching is REJECTED when the extra token is one of these.
const _ingredientModifiers = <String>{
  // Indian enrichment modifiers
  'makhani', 'butter', 'malai', 'cream', 'ghee',
  'tadka', 'jeera', 'tikka', 'masala', 'fried',
  'korma', 'biryani', 'pulao', 'pilaf',
  // General cooking modifiers
  'baked', 'grilled', 'roasted', 'smoked', 'curried',
  'sweet', 'spicy', 'salted', 'unsalted',
};

/// Session-persistent + SharedPreferences-backed meal cache.
///
/// Cache matching is CONSERVATIVE:
///   - Only exact normalized matches are returned.
///   - Normalization strips only pure filler words; quantities are kept intact.
///   - "2 roti sabzi" and "3 roti sabzi" → different cache keys.
class MealMemory {
  MealMemory._();
  static final MealMemory instance = MealMemory._();

  static const _prefKey   = 'meal_memory_v1';
  static const _candidatePrefKey = 'meal_memory_candidates_v1';
  static const _knownFoodPrefKey = 'known_food_memory_v1';
  static const _maxEntries = 250; // prune oldest beyond this
  static const _promoteSeenThreshold = 2;
  static const _promoteStableThreshold = 2;
  static const _stableCaloriesDelta = 0.12;
  static const _stableProteinDelta = 0.16;

  final _store = <String, MealMemoryEntry>{};
  final _candidates = <String, MealCandidateEntry>{};
  final _knownFoods = <String, NutritionResult>{};
  /// Tracks which _knownFoods keys came from the compiled-in bootstrap.
  /// These are safe to serve before hydration completes (identical for all users).
  final _bootstrapKeys = <String>{};
  bool _initialized = false;
  String? _ownerUserId;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_prefKey);
      if (raw != null) {
        final list  = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final entry = MealMemoryEntry.fromJson(item as Map<String, dynamic>);
          _store[entry.normalizedInput] = entry;
        }
      }

      final candidateRaw = prefs.getString(_candidatePrefKey);
      if (candidateRaw != null) {
        final list = jsonDecode(candidateRaw) as List<dynamic>;
        for (final item in list) {
          final entry = MealCandidateEntry.fromJson(item as Map<String, dynamic>);
          _candidates[entry.normalizedInput] = entry;
        }
      }

      final knownRaw = prefs.getString(_knownFoodPrefKey);
      if (knownRaw != null) {
        final map = jsonDecode(knownRaw) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _knownFoods[entry.key] = NutritionResult.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }

      _bootstrapDefaultKnownFoods();
      _ownerUserId = prefs.getString('cached_owner_user_id_v1');
    } catch (_) {
      // Corrupt prefs — start fresh; next store() will rebuild.
      _store.clear();
      _candidates.clear();
      _knownFoods.clear();
      _ownerUserId = null;
      _bootstrapDefaultKnownFoods();
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns a cached result for [rawInput] if one exists, else null.
  ///
  /// FAIL CLOSED: returns null unless NutritionHydrationGuard is ready
  /// for the currently authenticated user. This prevents User A's AI-confirmed
  /// recurring meal data from being served to User B during account switches.
  ///
  /// Increments [timesUsed] and updates [updatedAt] on hit.
  NutritionResult? lookup(String rawInput) {
    // FAIL CLOSED: user-specific recurring store
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) {
      debugPrint('[MealMemory] 🔒 guard not ready — skipping recurring lookup for "$rawInput"');
      return null;
    }

    // DEFENSE-IN-DEPTH: cache-level ownership verification
    final currentUserId = NutritionHydrationGuard.instance.currentUserId;
    if (_ownerUserId == null || _ownerUserId != currentUserId) {
      debugPrint('[MealMemory] ⛔ OWNERSHIP MISMATCH at cache layer: '
          'cache owned by $_ownerUserId, current user is $currentUserId');
      return null;
    }

    final key   = normalize(rawInput);
    final entry = _store[key];
    if (entry == null) return null;
    entry.timesUsed++;
    entry.updatedAt = DateTime.now();
    // Persist async (fire-and-forget)
    _persist().ignore();
    return entry.result.copyWith(source: 'cache').rebuildFromIngredientsAndOverrides();
  }

  /// Exact known foods / saved defaults have highest priority.
  ///
  /// FAIL CLOSED for user-learned entries (_knownFoods entries saved via
  /// storeKnownFood). The compiled-in bootstrap defaults are always safe
  /// since they are identical for all users.
  ///
  /// Falls back to a conservative token-subset match when no exact hit exists:
  /// all query tokens must be present in the stored key AND the stored key may
  /// have at most 1 extra token beyond the query (to avoid collapsing distinct
  /// foods like "paneer" and "paneer butter masala").
  NutritionResult? lookupExactKnownFood(String rawInput) {
    final key = normalize(rawInput);

    // _knownFoods contains both bootstrapped defaults (safe) and user-learned
    // entries (user-specific). We guard user-learned entries conservatively:
    // if guard is not ready, we only serve bootstrapped defaults, identified
    // by checking against the bootstrap key set.
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) {
      debugPrint('[MealMemory] 🔒 guard not ready — returning compiled-in defaults only');
      // Serve only if it exists in the bootstrap set (no user-learned contamination)
      final boot = _knownFoods[key];
      if (boot != null && _bootstrapKeys.contains(key)) {
        return boot.copyWith(source: 'memory_exact').rebuildFromIngredientsAndOverrides();
      }
      return null;
    }

    // If it is in the bootstrapKeys, it's a default and we can always return it.
    // Otherwise, it is user-learned, so we MUST check the cache owner ID.
    if (_bootstrapKeys.contains(key)) {
      final boot = _knownFoods[key];
      if (boot != null) return boot.copyWith(source: 'memory_exact').rebuildFromIngredientsAndOverrides();
    }

    // DEFENSE-IN-DEPTH: cache-level ownership verification for user-learned known food
    final currentUserId = NutritionHydrationGuard.instance.currentUserId;
    if (_ownerUserId == null || _ownerUserId != currentUserId) {
      debugPrint('[MealMemory] ⛔ OWNERSHIP MISMATCH at cache layer (user-learned known food): '
          'cache owned by $_ownerUserId, current user is $currentUserId');
      return null;
    }

    final exact = _knownFoods[key];
    if (exact != null) return exact.copyWith(source: 'memory_exact').rebuildFromIngredientsAndOverrides();
    // Conservative alias fallback
    final alias = _lookupByTokenSubset(_knownFoods, key);
    return alias?.copyWith(source: 'memory_exact').rebuildFromIngredientsAndOverrides();
  }

  /// Recurring memory = previously confirmed full-meal matches.
  ///
  /// FAIL CLOSED: delegates to lookup() which is already guarded.
  ///
  /// Falls back to token-subset matching when no exact normalized key is found
  /// (e.g. user types "oreo" but memory stored "oreo biscuit").
  NutritionResult? lookupRecurring(String rawInput) {
    // lookup() is already guard-gated — if guard not ready, returns null
    final exact = lookup(rawInput);
    if (exact != null) return exact;

    // Token-subset alias: also user-specific, must be guard-gated and owner-verified
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) return null;

    final currentUserId = NutritionHydrationGuard.instance.currentUserId;
    if (_ownerUserId == null || _ownerUserId != currentUserId) {
      debugPrint('[MealMemory] ⛔ OWNERSHIP MISMATCH at cache layer: '
          'cache owned by $_ownerUserId, current user is $currentUserId');
      return null;
    }

    final key = normalize(rawInput);
    final aliasEntry = _lookupEntryByTokenSubset(_store, key);
    if (aliasEntry == null) return null;
    aliasEntry.timesUsed++;
    aliasEntry.updatedAt = DateTime.now();
    _persist().ignore();
    return aliasEntry.result.copyWith(source: 'cache').rebuildFromIngredientsAndOverrides();
  }


  /// Stores an AI result as a low-trust candidate first.
  /// Promotion to recurring memory happens only after repeated stable encounters.
  Future<void> storeAiCandidate(String rawInput, NutritionResult result) async {
    final key = normalize(rawInput);
    final now = DateTime.now();
    final existing = _candidates[key];

    _ownerUserId = NutritionHydrationGuard.instance.currentUserId;
    if (existing == null) {
      _candidates[key] = MealCandidateEntry(
        normalizedInput: key,
        latestResult: result,
        seenCount: 1,
        stableHits: 1,
        createdAt: now,
        updatedAt: now,
      );
      await _persistCandidates();
      return;
    }

    final stable = _isStable(existing.latestResult, result);
    existing.seenCount += 1;
    existing.stableHits = stable ? existing.stableHits + 1 : 1;
    existing.latestResult = result;
    existing.updatedAt = now;

    if (existing.seenCount >= _promoteSeenThreshold &&
        existing.stableHits >= _promoteStableThreshold) {
      await store(rawInput, result.copyWith(source: 'memory_recurring_promoted'));
      _candidates.remove(key);
      await _persistCandidates();
      return;
    }

    await _persistCandidates();
  }

  Future<void> store(
    String rawInput,
    NutritionResult result, {
    String? finalSavedInput,
    String? canonicalMeal,
  }) async {
    final now = DateTime.now();
    _ownerUserId = NutritionHydrationGuard.instance.currentUserId;

    void storeKey(String input) {
      final key = normalize(input);
      if (key.isEmpty) return;
      _store[key] = MealMemoryEntry(
        id:              '${now.millisecondsSinceEpoch}_${key.hashCode}',
        rawInput:        input,
        normalizedInput: key,
        result:          result,
        timesUsed:       1,
        createdAt:       now,
        updatedAt:       now,
      );
    }

    storeKey(rawInput);
    if (finalSavedInput != null) {
      storeKey(finalSavedInput);
    }
    if (canonicalMeal != null) {
      storeKey(canonicalMeal);
    }

    await _persist();
  }

  Future<void> storeKnownFood(String rawInput, NutritionResult result) async {
    _knownFoods[normalize(rawInput)] = result.normalizedUncertainty();
    _ownerUserId = NutritionHydrationGuard.instance.currentUserId;
    await _persistKnownFoods();
  }

  /// All entries sorted by most-recently-used.
  List<MealMemoryEntry> get allEntries =>
      _store.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      // If over limit, remove oldest entries.
      if (_store.length > _maxEntries) {
        final sorted = allEntries;
        for (int i = _maxEntries; i < sorted.length; i++) {
          _store.remove(sorted[i].normalizedInput);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final data  = jsonEncode(
          _store.values.map((e) => e.toJson()).toList());
      await prefs.setString(_prefKey, data);
    } catch (_) {
      // Persistence failure is non-fatal.
    }
  }

  Future<void> _persistKnownFoods() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        for (final e in _knownFoods.entries) e.key: e.value.toJson(),
      };
      await prefs.setString(_knownFoodPrefKey, jsonEncode(data));
    } catch (_) {}
  }

  Future<void> _persistCandidates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(
        _candidates.values.map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_candidatePrefKey, data);
    } catch (_) {}
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Wipe all user-specific memory: recurring store, AI candidates, and
  /// user-learned known foods. Restores compiled-in bootstrapped defaults.
  /// Called during logout (step 3 of the account switch sequence).
  Future<void> clearAll() async {
    _store.clear();
    _candidates.clear();
    _knownFoods.clear();
    _initialized = false;
    _ownerUserId = null;
    // Immediately restore compiled-in defaults (safe for all users)
    _bootstrapDefaultKnownFoods();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
      await prefs.remove(_candidatePrefKey);
      await prefs.remove(_knownFoodPrefKey);
    } catch (_) {}
    debugPrint('[MealMemory] 🗑️  clearAll() complete — recurring/candidates/user-foods wiped, defaults restored');
  }

  bool _isStable(NutritionResult a, NutritionResult b) {
    final aCal = ((a.calories.min + a.calories.max) / 2).abs();
    final bCal = ((b.calories.min + b.calories.max) / 2).abs();
    final aPro = ((a.protein.min + a.protein.max) / 2).abs();
    final bPro = ((b.protein.min + b.protein.max) / 2).abs();

    final calRef = aCal > 0 ? aCal : bCal;
    final proRef = aPro > 0 ? aPro : bPro;

    final calDelta = calRef == 0 ? 0 : (aCal - bCal).abs() / calRef;
    final proDelta = proRef == 0 ? 0 : (aPro - bPro).abs() / proRef;

    return calDelta <= _stableCaloriesDelta && proDelta <= _stableProteinDelta;
  }

  void _bootstrapDefaultKnownFoods() {
    if (_knownFoods.isNotEmpty) return;

    for (final entry in _defaultKnownFoods.entries) {
      _knownFoods[entry.key] = entry.value;
      _bootstrapKeys.add(entry.key); // mark as safe compiled-in default
    }
  }

  /// Conservative token-subset lookup for a map of [NutritionResult] values.
  ///
  /// Two-tier alias guard:
  ///   Tier 1 — SAFE ALIAS: all query tokens appear in the stored key AND the
  ///     single extra token is in [_safeQualifiers] (e.g. 'protein', 'biscuit').
  ///     These words do not change the core food identity. MATCH ALLOWED.
  ///   Tier 2 — RISKY MODIFIER: extra token is in [_ingredientModifiers]
  ///     (e.g. 'makhani', 'tadka', 'ghee'). These change the calorie profile
  ///     significantly. MATCH REJECTED.
  ///   Default — extra token is unknown: REJECT (conservative).
  NutritionResult? _lookupByTokenSubset(
      Map<String, NutritionResult> map, String queryKey) {
    final queryTokens = queryKey.split(' ').toSet();
    NutritionResult? best;
    int bestExtraTokens = 999;

    for (final entry in map.entries) {
      final storedTokens = entry.key.split(' ').toSet();
      final extras = storedTokens.difference(queryTokens);
      if (queryTokens.isNotEmpty &&
          queryTokens.every(storedTokens.contains) &&
          extras.length == 1 &&
          extras.length < bestExtraTokens) {
        final extraToken = extras.first;
        // Tier 2: ingredient modifier → always reject
        if (_ingredientModifiers.contains(extraToken)) continue;
        // Tier 1: safe qualifier → allow; default: reject
        if (!_safeQualifiers.contains(extraToken)) continue;
        best = entry.value;
        bestExtraTokens = extras.length;
      }
    }
    return best;
  }

  /// Conservative token-subset lookup for the [MealMemoryEntry] store.
  ///
  /// Same two-tier alias guard as [_lookupByTokenSubset].
  MealMemoryEntry? _lookupEntryByTokenSubset(
      Map<String, MealMemoryEntry> map, String queryKey) {
    final queryTokens = queryKey.split(' ').toSet();
    MealMemoryEntry? best;
    int bestExtraTokens = 999;

    for (final entry in map.entries) {
      final storedTokens = entry.key.split(' ').toSet();
      final extras = storedTokens.difference(queryTokens);
      if (queryTokens.isNotEmpty &&
          queryTokens.every(storedTokens.contains) &&
          extras.length == 1 &&
          extras.length < bestExtraTokens) {
        final extraToken = extras.first;
        // Tier 2: ingredient modifier → always reject
        if (_ingredientModifiers.contains(extraToken)) continue;
        // Tier 1: safe qualifier → allow; default: reject
        if (!_safeQualifiers.contains(extraToken)) continue;
        best = entry.value;
        bestExtraTokens = extras.length;
      }
    }
    return best;
  }

  /// Conservative normalization (strips only meaningless connector words;
  /// KEEPS all quantities so "2 roti" and "3 roti" never collapse).
  static String normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"[',.\-!?+&]"), '')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_fillerWords.contains(t))
        .join(' ')
        .trim();
  }
}

NutritionResult _knownSingleItem({
  required String canonicalMeal,
  required String itemName,
  required double quantity,
  required String unit,
  required NutrientRange calories,
  required NutrientRange protein,
  required EstimationMode mode,
}) => NutritionResult(
      canonicalMeal: canonicalMeal,
      items: [
        NutritionItem(
          name: itemName,
          quantity: quantity,
          unit: unit,
          estimated: false,
          mode: mode,
          calories: calories,
          protein: protein,
        ),
      ],
      calories: calories,
      protein: protein,
      confidence: 0.98,
      warnings: const [],
      source: 'memory_exact',
      createdAt: DateTime.now(),
    ).normalizedUncertainty();

final Map<String, NutritionResult> _defaultKnownFoods = {
  MealMemory.normalize('1 scoop whey'):
      _knownSingleItem(
        canonicalMeal: '1 scoop whey',
        itemName: 'Whey protein',
        quantity: 1,
        unit: 'scoop',
        calories: const NutrientRange(min: 120, max: 120),
        protein: const NutrientRange(min: 24, max: 24),
        mode: EstimationMode.packagedKnown,
      ),
  MealMemory.normalize('150 g tofu'):
      _knownSingleItem(
        canonicalMeal: '150 g tofu',
        itemName: 'Tofu',
        quantity: 150,
        unit: 'g',
        calories: const NutrientRange(min: 206, max: 206),
        protein: const NutrientRange(min: 22, max: 22),
        mode: EstimationMode.packagedKnown,
      ),
  MealMemory.normalize('2 tbsp peanut butter'):
      _knownSingleItem(
        canonicalMeal: '2 tbsp peanut butter',
        itemName: 'Peanut butter',
        quantity: 2,
        unit: 'tbsp',
        calories: const NutrientRange(min: 180, max: 180),
        protein: const NutrientRange(min: 7, max: 7),
        mode: EstimationMode.packagedKnown,
      ),
  MealMemory.normalize('400 ml milk'):
      _knownSingleItem(
        canonicalMeal: '400 ml milk',
        itemName: 'Milk (toned)',
        quantity: 400,
        unit: 'ml',
        calories: const NutrientRange(min: 232, max: 232),
        protein: const NutrientRange(min: 14, max: 14),
        mode: EstimationMode.directQuantity,
      ),
};
