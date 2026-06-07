import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'food_role_classifier.dart';
import '../screens/onboarding_screen.dart' show PortionAnchor;

// ─── EatingPatternService ─────────────────────────────────────────────────────
//
// PURPOSE (important — read before editing):
//
//   This service learns HOW MUCH the user typically consumes, not what foods
//   contain nutritionally.  These are fundamentally different systems:
//
//     Ingredient Memory  →  "milk = 42 kcal / 100ml"       (nutrition facts)
//     EatingPatternService → "user typically drinks 300ml"  (consumption behaviour)
//
//   The two must NEVER be merged.
//
// LEARNING MECHANISM:
//
//   Patterns are stored at the (targetRole, contextRole?) level — never at the
//   individual food-name level.  This means corrections to "dal" and "rajma"
//   and "pasta sauce" all contribute to the same "accompaniment-in-primary-context"
//   pattern, because all three items have role=accompaniment and share the same
//   contextRole=primary.
//
//   When the user corrects a "channa" item downward by 22%, that ratio (0.78)
//   is recorded under (accompaniment, primary).  If they also correct "pasta
//   sauce" the next day by 20%, that adds another data point (0.80).  After
//   3+ points the scalar 0.78–0.80 is applied to ALL future accompaniments
//   eaten alongside primary foods — not just channa or pasta sauce.
//
// RECENCY WEIGHTING:
//
//   Exponential decay: weight = 0.5 ^ (days_ago / 14).
//   14-day half-life means a correction from 2 weeks ago counts as half a
//   correction today.  Records older than 90 days are dropped entirely.
//
// CONFIDENCE:
//
//   Confidence = blend of sample-count score (asymptotic) and ratio consistency
//   (inverse variance).  Minimum 3 valid records before any scalar is applied.
//   Confidence is reported for display but does NOT reduce the scalar — the
//   scalar is either applied (≥3 records) or not (< 3 records).
//
// EXPLAINABILITY:
//
//   Every learned pattern is exposed via [allLearned] as a [LearnedPatternEntry]
//   with a human-readable [explanation] string.  No hidden adjustments.

// ─── PatternKey ───────────────────────────────────────────────────────────────

class PatternKey {
  final FoodRole targetRole;
  final FoodRole? contextRole; // null = item was eaten solo (no primary in meal)

  const PatternKey(this.targetRole, {this.contextRole});

  @override
  bool operator ==(Object other) =>
      other is PatternKey &&
      other.targetRole == targetRole &&
      other.contextRole == contextRole;

  @override
  int get hashCode => Object.hash(targetRole, contextRole);

  Map<String, dynamic> toJson() => {
        'targetRole': targetRole.name,
        if (contextRole != null) 'contextRole': contextRole!.name,
      };

  factory PatternKey.fromJson(Map<String, dynamic> j) => PatternKey(
        FoodRole.values.byName(j['targetRole'] as String),
        contextRole: j['contextRole'] != null
            ? FoodRole.values.byName(j['contextRole'] as String)
            : null,
      );

  @override
  String toString() =>
      '${targetRole.name}${contextRole != null ? '+${contextRole!.name}ctx' : ''}';
}

// ─── _CorrectionRecord ────────────────────────────────────────────────────────

class _CorrectionRecord {
  final PatternKey key;
  final double pipelineEstimate; // what the pipeline thought (kcal)
  final double userCorrectedCal; // what the user corrected to (kcal)
  final double ratio;            // userCorrectedCal / pipelineEstimate
  final DateTime timestamp;

  _CorrectionRecord({
    required this.key,
    required this.pipelineEstimate,
    required this.userCorrectedCal,
    required this.ratio,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'key':               key.toJson(),
        'pipelineEstimate':  pipelineEstimate,
        'userCorrectedCal':  userCorrectedCal,
        'ratio':             ratio,
        'timestamp':         timestamp.toIso8601String(),
      };

  factory _CorrectionRecord.fromJson(Map<String, dynamic> j) =>
      _CorrectionRecord(
        key:               PatternKey.fromJson(j['key'] as Map<String, dynamic>),
        pipelineEstimate:  (j['pipelineEstimate'] as num).toDouble(),
        userCorrectedCal:  (j['userCorrectedCal'] as num).toDouble(),
        ratio:             (j['ratio'] as num).toDouble(),
        timestamp:         DateTime.parse(j['timestamp'] as String),
      );
}

// ─── _MealContextRecord ───────────────────────────────────────────────────────

class _MealContextRecord {
  final List<String> primaryFoodNames; // names of primary-role foods in the meal
  final double primaryTotalQty;        // sum of primary quantities (in their native units)
  final String primaryDominant;        // most frequent primary food name
  final DateTime timestamp;

  _MealContextRecord({
    required this.primaryFoodNames,
    required this.primaryTotalQty,
    required this.primaryDominant,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'primaryFoodNames': primaryFoodNames,
        'primaryTotalQty':  primaryTotalQty,
        'primaryDominant':  primaryDominant,
        'timestamp':        timestamp.toIso8601String(),
      };

  factory _MealContextRecord.fromJson(Map<String, dynamic> j) =>
      _MealContextRecord(
        primaryFoodNames: List<String>.from(j['primaryFoodNames'] ?? []),
        primaryTotalQty:  (j['primaryTotalQty'] as num?)?.toDouble() ?? 1.0,
        primaryDominant:  j['primaryDominant'] as String? ?? '',
        timestamp:        DateTime.parse(j['timestamp'] as String),
      );
}

// ─── LearnedPatternEntry ──────────────────────────────────────────────────────

class LearnedPatternEntry {
  final PatternKey key;
  final double scalar;
  final double confidence;
  final int sampleCount;
  final DateTime lastUpdated;

  const LearnedPatternEntry({
    required this.key,
    required this.scalar,
    required this.confidence,
    required this.sampleCount,
    required this.lastUpdated,
  });

  /// Human-readable explanation for the Nutrition Intelligence screen.
  String get explanation {
    final pct = ((1.0 - scalar).abs() * 100).round();
    final direction = scalar < 1.0 ? 'less' : 'more';
    final roleLabel = _roleLabel(key.targetRole);
    final ctxLabel  = key.contextRole != null
        ? ' when paired with ${_roleLabel(key.contextRole!)}'
        : ' when eaten alone';
    final conf = (confidence * 100).round();
    return 'You typically eat ~$pct% $direction $roleLabel$ctxLabel. '
        'Based on $sampleCount corrections. Confidence: $conf%.';
  }

  String _roleLabel(FoodRole r) => switch (r) {
        FoodRole.primary       => 'primary/starch foods',
        FoodRole.protein       => 'protein foods',
        FoodRole.accompaniment => 'accompaniment foods (dal, curry, sauce, etc.)',
        FoodRole.addOn         => 'add-on foods (butter, spreads, dressings, etc.)',
        FoodRole.completeMeal  => 'complete-meal foods',
      };
}

// ─── EatingPatternService ─────────────────────────────────────────────────────

class EatingPatternService {
  EatingPatternService._();
  static final EatingPatternService instance = EatingPatternService._();

  static const _kPatterns = 'eating_patterns_v1';
  static const _kContext  = 'meal_context_v1';
  static const _kSeeded  = 'eating_pattern_seeded_anchor_v1';
  static const _halfLifeDays = 14.0;
  static const _dropAfterDays = 90;
  static const _minSamples = 3;
  static const _maxRecordsPerKey = 50; // rolling window cap

  final Map<PatternKey, List<_CorrectionRecord>> _records = {};
  final List<_MealContextRecord> _contextRecords = [];
  bool _dirty = false;
  PortionAnchor? _seededAnchor; // tracks which anchor was last seeded

  // ── Recording ───────────────────────────────────────────────────────────────

  /// Record a correction made via the "Edit Ingredients" UI.
  ///
  /// [correctedItemRole]   — FoodRole of the ingredient being corrected.
  /// [mealHasPrimary]      — whether the current meal contains a primary food.
  /// [pipelineCalEstimate] — what the pipeline estimated for this ingredient.
  /// [userCorrectedCal]    — what the user corrected it to.
  ///
  /// No-ops when pipelineCalEstimate ≤ 0 (prevents division by zero).
  void recordIngredientCorrection({
    required FoodRole correctedItemRole,
    required bool mealHasPrimary,
    required double pipelineCalEstimate,
    required double userCorrectedCal,
    DateTime? timestamp,
  }) {
    if (pipelineCalEstimate <= 0) return;
    // completeMeal items are self-contained — no role-relationship learning.
    if (correctedItemRole == FoodRole.completeMeal) return;

    final ratio      = (userCorrectedCal / pipelineCalEstimate).clamp(0.1, 5.0);
    final contextRole = mealHasPrimary ? FoodRole.primary : null;
    final key        = PatternKey(correctedItemRole, contextRole: contextRole);

    _records.putIfAbsent(key, () => []).add(_CorrectionRecord(
      key:               key,
      pipelineEstimate:  pipelineCalEstimate,
      userCorrectedCal:  userCorrectedCal,
      ratio:             ratio,
      timestamp:         timestamp ?? DateTime.now(),
    ));

    // Keep rolling window — drop oldest if over cap.
    if (_records[key]!.length > _maxRecordsPerKey) {
      _records[key]!.removeAt(0);
    }

    _dirty = true;
    debugPrint('[EatingPatternService] ✍️  Recorded '
        '${correctedItemRole.name}+${contextRole?.name ?? "solo"} '
        'ratio=${ratio.toStringAsFixed(3)} '
        '($pipelineCalEstimate→$userCorrectedCal kcal)');
  }

  /// Record the food roles present in a meal (called after every successful log).
  /// Used to compute typical-primary-portion statistics shown in the UI.
  void recordMealContext(List<RolledFoodItem> rolledItems) {
    final primaries = rolledItems.where((r) => r.role == FoodRole.primary).toList();
    if (primaries.isEmpty) return;

    final primaryNames = primaries.map((r) => r.parsed.normalizedName).toList();
    final primaryQty   = primaries.fold(0.0, (s, r) => s + r.parsed.quantity);
    // Most frequent name in this meal (trivially: first for single-item meals)
    final dominant = primaryNames.first;

    _contextRecords.add(_MealContextRecord(
      primaryFoodNames: primaryNames,
      primaryTotalQty:  primaryQty,
      primaryDominant:  dominant,
      timestamp:        DateTime.now(),
    ));

    _dirty = true;
  }

  // ── Querying ────────────────────────────────────────────────────────────────

  /// Returns a recency-weighted consumption scalar for [targetRole] in the
  /// context of [contextRole].  Returns null when fewer than [_minSamples]
  /// valid (non-stale) records exist — caller must treat null as "no adjustment".
  double? getScalar(FoodRole targetRole, {FoodRole? contextRole}) {
    final key     = PatternKey(targetRole, contextRole: contextRole);
    final records = _validRecords(key);
    if (records.length < _minSamples) return null;

    final now = DateTime.now();
    double wSum = 0, wTotal = 0;
    for (final r in records) {
      final age = now.difference(r.timestamp).inHours / 24.0;
      final w   = math.pow(0.5, age / _halfLifeDays).toDouble();
      wSum   += r.ratio * w;
      wTotal += w;
    }
    if (wTotal == 0) return null;
    final scalar = (wSum / wTotal).clamp(0.3, 2.5);
    debugPrint('[EatingPatternService] 📐 Scalar for $key = '
        '${scalar.toStringAsFixed(3)} (${records.length} samples)');
    return scalar;
  }

  /// Confidence in [0.0, 1.0].  Blends sample count (asymptotic toward 1.0)
  /// with ratio consistency (inverse variance).  Returns 0.0 if < [_minSamples].
  double getConfidence(FoodRole targetRole, {FoodRole? contextRole}) {
    final key     = PatternKey(targetRole, contextRole: contextRole);
    final records = _validRecords(key);
    if (records.length < _minSamples) return 0.0;

    final nScore = 1.0 - math.pow(0.85, records.length).toDouble();

    final ratios  = records.map((r) => r.ratio).toList();
    final mean    = ratios.reduce((a, b) => a + b) / ratios.length;
    final variance = ratios
        .map((r) => math.pow(r - mean, 2).toDouble())
        .reduce((a, b) => a + b) /
        ratios.length;
    final consistency = 1.0 / (1.0 + variance * 4);

    return ((nScore * 0.5 + consistency * 0.5)).clamp(0.0, 1.0);
  }

  /// Number of valid (non-stale) correction records for this key.
  int getSampleCount(FoodRole targetRole, {FoodRole? contextRole}) =>
      _validRecords(PatternKey(targetRole, contextRole: contextRole)).length;

  /// Timestamp of the most recent correction for this key, or null.
  DateTime? getLastUpdated(FoodRole targetRole, {FoodRole? contextRole}) {
    final records = _validRecords(PatternKey(targetRole, contextRole: contextRole));
    if (records.isEmpty) return null;
    return records.map((r) => r.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  // ── Explainability ──────────────────────────────────────────────────────────

  /// All pattern keys that have enough data to produce a scalar, plus keys that
  /// have data but not yet enough (shown as "learning…" in the UI).
  List<LearnedPatternEntry> get allLearned {
    final result = <LearnedPatternEntry>[];
    for (final key in _records.keys) {
      final records = _validRecords(key);
      if (records.isEmpty) continue;
      final scalar     = getScalar(key.targetRole, contextRole: key.contextRole);
      final confidence = getConfidence(key.targetRole, contextRole: key.contextRole);
      result.add(LearnedPatternEntry(
        key:         key,
        scalar:      scalar ?? 1.0,        // 1.0 = not enough data yet
        confidence:  confidence,
        sampleCount: records.length,
        lastUpdated: records.last.timestamp,
      ));
    }
    result.sort((a, b) => b.sampleCount.compareTo(a.sampleCount));
    return result;
  }

  // ── Context stats ────────────────────────────────────────────────────────────

  /// Average quantity of primary-role foods per logged meal.
  double get avgPrimaryPortionPerLog {
    if (_contextRecords.isEmpty) return 0;
    final sum = _contextRecords.fold(0.0, (s, r) => s + r.primaryTotalQty);
    return sum / _contextRecords.length;
  }

  /// Most frequently logged primary food across all context records.
  String get dominantPrimaryFood {
    if (_contextRecords.isEmpty) return 'unknown';
    final counts = <String, int>{};
    for (final r in _contextRecords) {
      for (final n in r.primaryFoodNames) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    return counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  /// Total number of meal contexts recorded.
  int get totalMealsTracked => _contextRecords.length;

  // ── Portion Anchor Seeding ───────────────────────────────────────────────────

  /// Bootstrap the scalar system from the user's declared eating style.
  ///
  /// Inserts synthetic correction records anchored 30 days in the past so they
  /// count as half-weight after one 14-day half-life.  Real user corrections
  /// (weight = 1.0 at day 0) accumulate on top and will dominate within a few
  /// corrections.  Calling this method a second time with the same anchor is a
  /// no-op; calling with a different anchor first removes the old seed.
  ///
  /// Seeding strategy by anchor:
  ///   carbAnchored   → accompaniments small (0.55×) when primary present
  ///   curryAnchored  → accompaniments large (1.40×), primary small (0.60×)
  ///   balanced       → no synthetic seed (population average = 1.0 baseline)
  void seedFromPortionAnchor(PortionAnchor anchor) {
    if (_seededAnchor == anchor) {
      debugPrint('[EatingPatternService] 🌱 Seed already applied for ${anchor.name}. No-op.');
      return;
    }

    // Remove any previous seed records before applying the new anchor's seed.
    _removeSeedRecords();
    _seededAnchor = anchor;

    if (anchor == PortionAnchor.balanced) {
      // Balanced = population average. No synthetic tilt needed.
      debugPrint('[EatingPatternService] 🌱 balanced anchor — no synthetic seed applied.');
      _dirty = true;
      return;
    }

    // Seed timestamp: 30 days ago so it counts at ~0.25 weight relative to today.
    // This means 2 real corrections (~1.5 effective weight each) quickly dominate.
    final seedTime = DateTime.now().subtract(const Duration(days: 30));

    void addSeed(PatternKey key, double ratio, {int count = 4}) {
      final list = _records.putIfAbsent(key, () => []);
      for (int i = 0; i < count; i++) {
        // Stagger timestamps slightly so they survive the duplicate filter.
        final ts = seedTime.subtract(Duration(minutes: i * 5));
        list.add(_CorrectionRecord(
          key:               key,
          pipelineEstimate:  100.0,          // arbitrary non-zero base
          userCorrectedCal:  100.0 * ratio,  // calibrate to the target ratio
          ratio:             ratio,
          timestamp:         ts,
        ));
      }
      // Enforce rolling window cap
      if (list.length > _maxRecordsPerKey) {
        _records[key] = list.sublist(list.length - _maxRecordsPerKey);
      }
    }

    switch (anchor) {
      case PortionAnchor.carbAnchored:
        // Accompaniments (dal, sabzi, curry…) are small when carbs are present.
        addSeed(
          PatternKey(FoodRole.accompaniment, contextRole: FoodRole.primary),
          0.55,
        );
        break;

      case PortionAnchor.curryAnchored:
        // Accompaniments are large (full katori).
        addSeed(
          PatternKey(FoodRole.accompaniment, contextRole: FoodRole.primary),
          1.40,
        );
        // Carbs are smaller (just enough to go with the dal).
        addSeed(
          PatternKey(FoodRole.primary, contextRole: FoodRole.accompaniment),
          0.60,
        );
        break;

      case PortionAnchor.balanced:
        break; // handled above
    }

    _dirty = true;
    debugPrint('[EatingPatternService] 🌱 Seeded patterns for ${anchor.name}: '
        '${_records.values.fold(0, (s, l) => s + l.length)} total records');
  }

  /// Remove all synthetic seed records (identified by age ≥ 29 days and
  /// pipelineEstimate == 100.0 sentinel).  Real corrections use non-round
  /// pipeline estimates that won't match this filter.
  void _removeSeedRecords() {
    if (_seededAnchor == null) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 29));
    for (final key in _records.keys.toList()) {
      _records[key]!.removeWhere(
        (r) => r.timestamp.isBefore(cutoff) && r.pipelineEstimate == 100.0,
      );
      if (_records[key]!.isEmpty) _records.remove(key);
    }
    _seededAnchor = null;
    _dirty = true;
    debugPrint('[EatingPatternService] 🗑️  Removed seed records for anchor change.');
  }

  // ── Reset ───────────────────────────────────────────────────────────────────

  void resetPattern(FoodRole targetRole, {FoodRole? contextRole}) {
    final key = PatternKey(targetRole, contextRole: contextRole);
    _records.remove(key);
    _dirty = true;
    debugPrint('[EatingPatternService] 🗑️  Reset pattern: $key');
  }

  void resetAll() {
    _records.clear();
    _contextRecords.clear();
    _seededAnchor = null;
    _dirty = true;
    debugPrint('[EatingPatternService] 🗑️  Reset ALL patterns');
  }

  // ── Cloud Sync ───────────────────────────────────────────────────────────────

  /// Returns all correction records as a flat list for upload to Supabase.
  /// Each map has: targetRole, contextRole?, pipelineEstimate,
  ///   userCorrectedCal, ratio, recordedAt (ISO8601 string).
  List<Map<String, dynamic>> exportForCloudSync() {
    final result = <Map<String, dynamic>>[];
    for (final records in _records.values) {
      for (final r in records) {
        result.add({
          'target_role': r.key.targetRole.name,
          if (r.key.contextRole != null) 'context_role': r.key.contextRole!.name,
          'pipeline_estimate': r.pipelineEstimate,
          'user_corrected_cal': r.userCorrectedCal,
          'ratio': r.ratio,
          'recorded_at': r.timestamp.toIso8601String(),
        });
      }
    }
    return result;
  }

  /// Returns all meal context records as a list for upload to Supabase.
  List<Map<String, dynamic>> exportContextsForCloudSync() {
    return _contextRecords
        .map((r) => {
              'primary_food_names': r.primaryFoodNames,
              'primary_total_qty': r.primaryTotalQty,
              'primary_dominant': r.primaryDominant,
              'recorded_at': r.timestamp.toIso8601String(),
            })
        .toList();
  }

  /// Merge correction records received from Supabase cloud sync.
  /// Skips records that are duplicates of existing ones (same timestamp + ratio).
  void mergeFromCloud(List<Map<String, dynamic>> rows) {
    int added = 0;
    for (final row in rows) {
      try {
        final targetRoleName = row['target_role'] as String?;
        if (targetRoleName == null) continue;
        final targetRole = FoodRole.values.firstWhere(
          (e) => e.name == targetRoleName,
          orElse: () => FoodRole.primary,
        );
        final contextRoleName = row['context_role'] as String?;
        final contextRole = contextRoleName != null
            ? FoodRole.values.firstWhere(
                (e) => e.name == contextRoleName,
                orElse: () => FoodRole.primary,
              )
            : null;
        final key = PatternKey(targetRole, contextRole: contextRole);
        final timestamp = DateTime.tryParse(
                (row['recorded_at'] ?? row['created_at'] ?? '') as String) ??
            DateTime.now();
        final ratio =
            (row['ratio'] as num?)?.toDouble() ?? 1.0;
        final pipelineEstimate =
            (row['pipeline_estimate'] as num?)?.toDouble() ?? 0.0;
        final userCorrectedCal =
            (row['user_corrected_cal'] as num?)?.toDouble() ?? 0.0;

        // Skip duplicate (same timestamp within 1 second)
        final existing = _records[key];
        final isDuplicate = existing?.any((r) =>
                r.timestamp.difference(timestamp).inSeconds.abs() < 1) ??
            false;
        if (isDuplicate) continue;

        _records.putIfAbsent(key, () => []).add(_CorrectionRecord(
          key: key,
          pipelineEstimate: pipelineEstimate,
          userCorrectedCal: userCorrectedCal,
          ratio: ratio,
          timestamp: timestamp,
        ));
        added++;
      } catch (e) {
        debugPrint('[EatingPatternService] ⚠️  Failed to merge cloud row: $e');
      }
    }
    if (added > 0) {
      _dirty = true;
      debugPrint('[EatingPatternService] ☁️  Merged $added records from cloud');
    }
  }

  /// Merge meal context records received from Supabase cloud sync.
  void mergeContextsFromCloud(List<Map<String, dynamic>> rows) {
    int added = 0;
    for (final row in rows) {
      try {
        final timestamp = DateTime.tryParse(
                (row['recorded_at'] ?? row['created_at'] ?? '') as String) ??
            DateTime.now();
        // Skip duplicates (same timestamp within 1 second)
        final isDuplicate = _contextRecords.any(
            (r) => r.timestamp.difference(timestamp).inSeconds.abs() < 1);
        if (isDuplicate) continue;
        _contextRecords.add(_MealContextRecord(
          primaryFoodNames: (row['primary_food_names'] as List<dynamic>?)
                  ?.map((e) => e as String)
                  .toList() ??
              [],
          primaryTotalQty:
              (row['primary_total_qty'] as num?)?.toDouble() ?? 1.0,
          primaryDominant: (row['primary_dominant'] as String?) ?? '',
          timestamp: timestamp,
        ));
        added++;
      } catch (e) {
        debugPrint('[EatingPatternService] ⚠️  Failed to merge context row: $e');
      }
    }
    if (added > 0) {
      _dirty = true;
      debugPrint('[EatingPatternService] ☁️  Merged $added context records from cloud');
    }
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load correction records
      final patternsRaw = prefs.getString(_kPatterns);
      if (patternsRaw != null) {
        final list = jsonDecode(patternsRaw) as List<dynamic>;
        for (final item in list) {
          final r = _CorrectionRecord.fromJson(item as Map<String, dynamic>);
          _records.putIfAbsent(r.key, () => []).add(r);
        }
      }

      // Load context records
      final ctxRaw = prefs.getString(_kContext);
      if (ctxRaw != null) {
        final list = jsonDecode(ctxRaw) as List<dynamic>;
        for (final item in list) {
          _contextRecords.add(
              _MealContextRecord.fromJson(item as Map<String, dynamic>));
        }
      }

      // Restore seeded anchor sentinel
      final seededRaw = prefs.getString(_kSeeded);
      if (seededRaw != null) {
        _seededAnchor = PortionAnchor.values.firstWhere(
          (e) => e.name == seededRaw,
          orElse: () => PortionAnchor.balanced,
        );
      }

      _dirty = false;
      debugPrint('[EatingPatternService] ✅ Loaded '
          '${_records.length} pattern keys, '
          '${_contextRecords.length} context records');
    } catch (e) {
      debugPrint('[EatingPatternService] ⚠️  Load failed: $e');
    }
  }

  Future<void> save() async {
    if (!_dirty) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Flatten all records to a JSON list
      final allRecords = _records.values.expand((list) => list).toList();
      await prefs.setString(
          _kPatterns, jsonEncode(allRecords.map((r) => r.toJson()).toList()));

      // Trim context records (keep last 200)
      final trimmed = _contextRecords.length > 200
          ? _contextRecords.sublist(_contextRecords.length - 200)
          : _contextRecords;
      await prefs.setString(
          _kContext, jsonEncode(trimmed.map((r) => r.toJson()).toList()));

      // Persist seeded anchor sentinel
      if (_seededAnchor != null) {
        await prefs.setString(_kSeeded, _seededAnchor!.name);
      } else {
        await prefs.remove(_kSeeded);
      }

      _dirty = false;
      debugPrint('[EatingPatternService] 💾 Saved patterns');
    } catch (e) {
      debugPrint('[EatingPatternService] ⚠️  Save failed: $e');
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  List<_CorrectionRecord> _validRecords(PatternKey key) {
    final all = _records[key] ?? [];
    final cutoff = DateTime.now().subtract(const Duration(days: _dropAfterDays));
    return all.where((r) => r.timestamp.isAfter(cutoff)).toList();
  }
}
