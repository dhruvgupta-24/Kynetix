import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/nutrition_result.dart';
import '../services/mock_estimation_service.dart' show NutrientRange;

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
  bool _initialized = false;

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
    } catch (_) {
      // Corrupt prefs — start fresh; next store() will rebuild.
      _store.clear();
      _candidates.clear();
      _knownFoods.clear();
      _bootstrapDefaultKnownFoods();
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns a cached result for [rawInput] if one exists, else null.
  ///
  /// Increments [timesUsed] and updates [updatedAt] on hit.
  NutritionResult? lookup(String rawInput) {
    final key   = normalize(rawInput);
    final entry = _store[key];
    if (entry == null) return null;
    entry.timesUsed++;
    entry.updatedAt = DateTime.now();
    // Persist async (fire-and-forget)
    _persist().ignore();
    return entry.result.copyWith(source: 'cache');
  }

  /// Exact known foods / saved defaults have highest priority and must never be
  /// overridden by AI.
  NutritionResult? lookupExactKnownFood(String rawInput) {
    final key = normalize(rawInput);
    final known = _knownFoods[key];
    return known?.copyWith(source: 'memory_exact');
  }

  /// Recurring memory = previously confirmed full-meal matches.
  NutritionResult? lookupRecurring(String rawInput) => lookup(rawInput);

  /// Stores an AI result as a low-trust candidate first.
  /// Promotion to recurring memory happens only after repeated stable encounters.
  Future<void> storeAiCandidate(String rawInput, NutritionResult result) async {
    final key = normalize(rawInput);
    final now = DateTime.now();
    final existing = _candidates[key];

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

  /// Stores [result] for [rawInput].  Overwrites any existing entry with
  /// the same normalized key.
  Future<void> store(String rawInput, NutritionResult result) async {
    final key = normalize(rawInput);
    final now = DateTime.now();
    _store[key] = MealMemoryEntry(
      id:              '${now.millisecondsSinceEpoch}',
      rawInput:        rawInput,
      normalizedInput: key,
      result:          result,
      timesUsed:       1,
      createdAt:       now,
      updatedAt:       now,
    );
    await _persist();
  }

  Future<void> storeKnownFood(String rawInput, NutritionResult result) async {
    _knownFoods[normalize(rawInput)] = result.normalizedUncertainty();
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
    }
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
