// ─── Data model matching the estimation engine schema ─────────────────────────

class NutrientRange {
  final double min;
  final double max;
  const NutrientRange({required this.min, required this.max});

  double get mid     => (min + max) / 2;
  double get spread  => max > 0 ? (max - min) / max : 0;

  NutrientRange operator +(NutrientRange other) => NutrientRange(
        min: min + other.min,
        max: max + other.max,
      );

  NutrientRange tightenTo(double targetSpread) {
    final m   = mid;
    final half = m * targetSpread / 2;
    return NutrientRange(min: (m - half).clamp(0, double.infinity), max: m + half);
  }

  Map<String, dynamic> toJson() => {'min': min, 'max': max};

  factory NutrientRange.fromJson(dynamic j) {
    if (j is Map<String, dynamic>) {
      return NutrientRange(
        min: (j['min'] as num?)?.toDouble() ?? 0,
        max: (j['max'] as num?)?.toDouble() ?? 0,
      );
    }
    return const NutrientRange(min: 0, max: 0);
  }
}

class FoodItem {
  final String        name;
  final NutrientRange calories;
  final NutrientRange protein;
  const FoodItem(
      {required this.name,
      required this.calories,
      required this.protein});

  Map<String, dynamic> toJson() => {
    'name': name,
    'calories': calories.toJson(),
    'protein': protein.toJson(),
  };

  factory FoodItem.fromJson(Map<String, dynamic> j) => FoodItem(
    name:     j['name'] as String? ?? '',
    calories: NutrientRange.fromJson(j['calories']),
    protein:  NutrientRange.fromJson(j['protein']),
  );
}

class EstimationResult {
  final List<FoodItem>  items;
  final NutrientRange   calories;
  final NutrientRange   protein;
  final double          confidence; // 0.0 – 1.0
  final List<String>    warnings;

  const EstimationResult({
    required this.items,
    required this.calories,
    required this.protein,
    required this.confidence,
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
    'items':      items.map((f) => f.toJson()).toList(),
    'calories':   calories.toJson(),
    'protein':    protein.toJson(),
    'confidence': confidence,
    'warnings':   warnings,
  };

  factory EstimationResult.fromJson(Map<String, dynamic> j) => EstimationResult(
    items:      (j['items'] as List<dynamic>? ?? [])
        .map((e) => FoodItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    calories:   NutrientRange.fromJson(j['calories'] ?? {}),
    protein:    NutrientRange.fromJson(j['protein']  ?? {}),
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
    warnings:   List<String>.from(j['warnings'] as List<dynamic>? ?? []),
  );
}

class LocalEstimationAnalysis {
  final EstimationResult estimation;
  final int meaningfulTokenCount;
  final int matchedTokenCount;
  final List<String> matchedKeywords;

  const LocalEstimationAnalysis({
    required this.estimation,
    required this.meaningfulTokenCount,
    required this.matchedTokenCount,
    required this.matchedKeywords,
  });

  double get coverageConfidence {
    if (meaningfulTokenCount <= 0) return 0;
    return (matchedTokenCount / meaningfulTokenCount).clamp(0.0, 1.0);
  }
}

// ─── Food database ─────────────────────────────────────────────────────────────
//
// Design rules (per the schema spec):
//   • Simple food, clear qty  → ≤10% spread  (max/min ≤ 1.10)
//   • Simple food, qty unknown → ≤15% spread
//   • Side dish base          → ≤12% spread (partial-eat handled in engine)
//
// All values are PER UNIT (one roti, one ladle, one serving).
// isCarb  = provides bulk calories from starch
// isSide  = partial-eat model applies (mess dal/sabzi: 55–65 % consumed)
// kcalMid ≈ nutritional labelling mid; spread applied symmetrically.

// ─── Confidence tiers ────────────────────────────────────────────────────────
// Reflect how predictable a food's calorie content is per typical serving.
enum _Tier {
  veryHigh,  // 0.88–0.92 — packaged / simple (egg, milk, bread, oats)
  high,      // 0.78–0.84 — well-known mess staples (roti, rice, paneer, curd)
  medium,    // 0.65–0.72 — variable preparations (dal, sabzi, biryani)
  low,       // 0.50–0.62 — highly variable / oily (puri, samosa, coffee)
}

class _FoodEntry {
  final List<String>  keywords;
  final NutrientRange calories; // tight base range per unit
  final NutrientRange protein;
  final bool          isCarb;
  final bool          isSide;
  final String        label;
  final _Tier         tier;
  /// If set, one "unit" = servingMl ml (enables "400ml milk" → qty).
  final int?          servingMl;
  /// If set, one "unit" = servingGrams g (enables "150g tofu" → qty).
  final int?          servingGrams;

  const _FoodEntry({
    required this.keywords,
    required this.calories,
    required this.protein,
    required this.label,
    this.isCarb       = false,
    this.isSide       = false,
    this.tier         = _Tier.medium,
    this.servingMl,
    this.servingGrams,
  });

  double get baseConfidence => switch (tier) {
    _Tier.veryHigh => 0.90,
    _Tier.high     => 0.81,
    _Tier.medium   => 0.68,
    _Tier.low      => 0.56,
  };
}


const List<_FoodEntry> _db = [
  // ── Simple proteins (listed first — longer keywords matched before 'egg') ──
  // Egg white (1 white) ≈ 17 kcal, 3.6 g protein
  _FoodEntry(
    label:    'Egg White',
    keywords: ['egg white', 'egg whites', 'eggwhite'],
    calories: NutrientRange(min: 15, max: 19),
    protein:  NutrientRange(min: 3.4, max: 3.8),
    tier:     _Tier.veryHigh,
  ),
  // Omelette (2-egg + oil) ≈ 160 kcal
  _FoodEntry(
    label:    'Omelette (2-egg)',
    keywords: ['omelette', 'omlette', 'omelet', 'anda omelette'],
    calories: NutrientRange(min: 145, max: 178),
    protein:  NutrientRange(min: 11.0, max: 13.5),
    tier:     _Tier.high,
  ),

  // ── Rotis / Bread ─────────────────────────────────────────────────────────
  // Plain roti ≈ 100 kcal, 3 g protein  (mid ±7 %)
  _FoodEntry(
    label:    'Roti / Chapati',
    keywords: ['roti', 'chapati', 'chapatti', 'chappati', 'phulka'],
    calories: NutrientRange(min: 93, max: 107),   // ±7 %
    protein:  NutrientRange(min: 2.8, max: 3.2),
    isCarb:   true,
    tier:     _Tier.high,
  ),
  // Puri ≈ 125 kcal (deep-fried, more oil variance → 12 %)
  _FoodEntry(
    label:    'Puri',
    keywords: ['puri', 'poori'],
    calories: NutrientRange(min: 110, max: 140),   // ±12 %
    protein:  NutrientRange(min: 2.2, max: 2.8),
    isCarb:   true,
    tier:     _Tier.low,
  ),
  // Plain paratha ≈ 170 kcal (oil usage varies → 12 %)
  _FoodEntry(
    label:    'Paratha (plain)',
    keywords: ['paratha', 'parota'],
    calories: NutrientRange(min: 150, max: 190),   // ±12 %
    protein:  NutrientRange(min: 3.5, max: 4.5),
    isCarb:   true,
    tier:     _Tier.medium,
  ),
  // Aloo paratha ≈ 230 kcal
  _FoodEntry(
    label:    'Aloo Paratha',
    keywords: ['aloo paratha', 'potato paratha'],
    calories: NutrientRange(min: 210, max: 250),   // ±9 %
    protein:  NutrientRange(min: 4.3, max: 5.2),
    isCarb:   true,
    tier:     _Tier.medium,
  ),
  // Bread slice ≈ 80 kcal (packaged → very tight)
  _FoodEntry(
    label:    'Bread slice',
    keywords: ['bread', 'toast'],
    calories: NutrientRange(min: 75, max: 85),     // ±6 %
    protein:  NutrientRange(min: 2.6, max: 3.0),
    isCarb:   true,
    tier:     _Tier.veryHigh,
  ),

  // ── Rice ──────────────────────────────────────────────────────────────────
  // Rice 1 serving ≈ 150 kcal (volume variance → 12 %)
  _FoodEntry(
    label:    'Rice (1 serving)',
    keywords: ['rice', 'chawal', 'steamed rice', 'white rice'],
    calories: NutrientRange(min: 133, max: 167),   // ±11 %
    protein:  NutrientRange(min: 2.6, max: 3.4),
    isCarb:   true,
    tier:     _Tier.high,
  ),
  _FoodEntry(
    label:    'Jeera Rice',
    keywords: ['jeera rice', 'cumin rice'],
    calories: NutrientRange(min: 165, max: 195),   // ±8 %
    protein:  NutrientRange(min: 3.2, max: 4.0),
    isCarb:   true,
    tier:     _Tier.high,
  ),
  _FoodEntry(
    label:    'Biryani (1 serving)',
    keywords: ['biryani', 'biriyani'],
    calories: NutrientRange(min: 320, max: 390),   // ±10 % – mixed meal
    protein:  NutrientRange(min: 11.0, max: 17.0),
    isCarb:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Khichdi',
    keywords: ['khichdi', 'khichri'],
    calories: NutrientRange(min: 185, max: 225),   // ±10 %
    protein:  NutrientRange(min: 6.5, max: 8.5),
    isCarb:   true,
    tier:     _Tier.medium,
  ),

  // ── Proteins ──────────────────────────────────────────────────────────────
  // Paneer 1 mess serving ≈ 80 g → 240 kcal; fully eaten.
  _FoodEntry(
    label:    'Paneer (1 serving)',
    keywords: ['paneer', 'cottage cheese'],
    calories: NutrientRange(min: 220, max: 260),   // ±8 %
    protein:  NutrientRange(min: 14.0, max: 17.0),
    tier:     _Tier.high,
  ),
  _FoodEntry(
    label:    'Paneer Bhurji',
    keywords: ['paneer bhurji', 'bhurji'],
    calories: NutrientRange(min: 230, max: 270),   // ±8 %
    protein:  NutrientRange(min: 14.5, max: 17.5),
    tier:     _Tier.high,
  ),
  // Egg (boiled whole) ≈ 75 kcal (packaged → tight) — AFTER 'egg white' entry
  _FoodEntry(
    label:    'Egg (boiled)',
    keywords: ['egg', 'anda', 'boiled egg', 'whole egg'],
    calories: NutrientRange(min: 71, max: 79),     // ±5 %
    protein:  NutrientRange(min: 6.1, max: 6.9),
    tier:     _Tier.veryHigh,
  ),
  // Whey protein (1 scoop ≈ 30 g) ≈ 120 kcal — packaged/precise
  _FoodEntry(
    label:    'Whey Protein (1 scoop)',
    keywords: ['whey', 'protein powder', 'whey protein', 'protein shake'],
    calories: NutrientRange(min: 112, max: 128),   // ±7 %
    protein:  NutrientRange(min: 22.0, max: 26.0),
    tier:     _Tier.veryHigh,
  ),
  // Chicken ≈ 250 kcal per mess serving
  _FoodEntry(
    label:    'Chicken (1 serving)',
    keywords: ['chicken', 'murgh'],
    calories: NutrientRange(min: 225, max: 275),   // ±10 %
    protein:  NutrientRange(min: 23.0, max: 28.0),
    tier:     _Tier.high,
  ),
  // Soya chunks 1 serving ≈ 165 kcal
  _FoodEntry(
    label:    'Soya Chunks (1 serving)',
    keywords: ['soya', 'soy', 'soya chunks', 'meal maker'],
    calories: NutrientRange(min: 150, max: 178),   // ±8 %
    protein:  NutrientRange(min: 18.5, max: 22.5),
    tier:     _Tier.high,
  ),

  // ── Dal / Lentils ─────────────────────────────────────────────────────────
  // Dal 1 ladle ≈ 65 kcal base; partial-eat (55–65 %) handled by engine.
  _FoodEntry(
    label:    'Dal (1 ladle)',
    keywords: ['dal', 'daal', 'lentil', 'lentils', 'tadka dal'],
    calories: NutrientRange(min: 60, max: 70),     // ±8 % tight base
    protein:  NutrientRange(min: 3.8, max: 4.8),
    isSide:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Dal Makhani',
    keywords: ['dal makhani', 'makhani dal', 'dal makahani'],
    calories: NutrientRange(min: 130, max: 148),   // ±6 %
    protein:  NutrientRange(min: 6.5, max: 8.0),
    isSide:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Rajma (1 serving)',
    keywords: ['rajma', 'kidney beans'],
    calories: NutrientRange(min: 140, max: 162),   // ±7 %
    protein:  NutrientRange(min: 7.5, max: 9.0),
    isSide:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Chole (1 serving)',
    keywords: ['chole', 'chana', 'chickpea', 'chhole'],
    calories: NutrientRange(min: 145, max: 168),   // ±7 %
    protein:  NutrientRange(min: 7.5, max: 9.0),
    isSide:   true,
    tier:     _Tier.medium,
  ),

  // ── Sabzi / Vegetables ────────────────────────────────────────────────────
  // Mixed veg sabzi 1 serving ≈ 70 kcal base
  _FoodEntry(
    label:    'Sabzi (mixed veg)',
    keywords: ['sabzi', 'sabji', 'bhaji', 'bhajji', 'curry', 'vegetable'],
    calories: NutrientRange(min: 62, max: 78),     // ±11 % base
    protein:  NutrientRange(min: 1.8, max: 3.0),
    isSide:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Aloo Sabzi',
    keywords: ['aloo', 'potato sabzi', 'aloo sabzi', 'jeera aloo'],
    calories: NutrientRange(min: 110, max: 130),   // ±8 %
    protein:  NutrientRange(min: 2.0, max: 2.8),
    isSide:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Baingan (eggplant)',
    keywords: ['baingan', 'eggplant', 'brinjal'],
    calories: NutrientRange(min: 60, max: 76),     // ±12 %
    protein:  NutrientRange(min: 1.5, max: 2.3),
    isSide:   true,
    tier:     _Tier.medium,
  ),
  _FoodEntry(
    label:    'Palak / Spinach',
    keywords: ['palak', 'spinach', 'saag'],
    calories: NutrientRange(min: 48, max: 60),     // ±11 %
    protein:  NutrientRange(min: 2.7, max: 3.5),
    isSide:   true,
    tier:     _Tier.medium,
  ),

  // ── Dairy / Snacks ────────────────────────────────────────────────────────
  // Milk 250 ml glass ≈ 122 kcal  (servingMl=250 enables ml-based qty)
  _FoodEntry(
    label:      'Milk (1 glass)',
    keywords:   ['milk', 'doodh'],
    calories:   NutrientRange(min: 114, max: 130),   // ±6 %
    protein:    NutrientRange(min: 6.5, max: 7.5),
    tier:       _Tier.veryHigh,
    servingMl:  250,
  ),
  // Curd 100 ml ≈ 75 kcal
  _FoodEntry(
    label:    'Curd / Dahi',
    keywords: ['curd', 'dahi', 'yogurt'],
    calories: NutrientRange(min: 68, max: 82),     // ±9 %
    protein:  NutrientRange(min: 3.8, max: 4.8),
    tier:     _Tier.high,
  ),
  // Oats 40 g ≈ 155 kcal
  _FoodEntry(
    label:    'Oats (1 bowl)',
    keywords: ['oats', 'oatmeal', 'porridge'],
    calories: NutrientRange(min: 143, max: 167),   // ±8 %
    protein:  NutrientRange(min: 5.0, max: 6.5),
    isCarb:   true,
    tier:     _Tier.veryHigh,
  ),
  // Samosa ≈ 145 kcal (oil varies)
  _FoodEntry(
    label:    'Samosa (1 piece)',
    keywords: ['samosa'],
    calories: NutrientRange(min: 128, max: 162),   // ±12 %
    protein:  NutrientRange(min: 3.0, max: 4.5),
    tier:     _Tier.low,
  ),
  // Banana ≈ 90 kcal
  _FoodEntry(
    label:    'Banana',
    keywords: ['banana', 'kela'],
    calories: NutrientRange(min: 82, max: 98),     // ±9 %
    protein:  NutrientRange(min: 1.0, max: 1.4),
    isCarb:   true,
    tier:     _Tier.veryHigh,
  ),
  // Apple ≈ 80 kcal
  _FoodEntry(
    label:    'Apple',
    keywords: ['apple', 'seb'],
    calories: NutrientRange(min: 74, max: 88),     // ±8 %
    protein:  NutrientRange(min: 0.3, max: 0.5),
    isCarb:   true,
    tier:     _Tier.veryHigh,
  ),
  // Chai ≈ 55 kcal
  _FoodEntry(
    label:    'Chai (with milk & sugar)',
    keywords: ['tea', 'chai', 'milk tea'],
    calories: NutrientRange(min: 48, max: 63),     // ±13 %
    protein:  NutrientRange(min: 1.5, max: 2.2),
    tier:     _Tier.medium,
  ),
  // Coffee ≈ 45 kcal
  _FoodEntry(
    label:    'Coffee (with milk)',
    keywords: ['coffee'],
    calories: NutrientRange(min: 38, max: 55),     // ±18 % (sugar varies)
    protein:  NutrientRange(min: 1.0, max: 1.8),
    tier:     _Tier.low,
  ),
  // Tofu (firm) 100 g ≈ 144 kcal — gram-aware via servingGrams
  _FoodEntry(
    label:       'Tofu (firm)',
    keywords:    ['tofu'],
    calories:    NutrientRange(min: 134, max: 155),  // ±7 %
    protein:     NutrientRange(min: 14.0, max: 16.5),
    tier:        _Tier.high,
    servingGrams: 100,
  ),

  // ── Outside / Generic Fast Food (Fallback Anchors) ────────────────────────
  // Crucial for when the AI is offline so the engine does not collapse to 0 items
  _FoodEntry(
    label:    'Pizza (1 slice)',
    keywords: ['pizza', 'dominos', 'pizzas'],
    calories: NutrientRange(min: 240, max: 280),   // ±8 %
    protein:  NutrientRange(min: 8.0, max: 11.0),
    tier:     _Tier.low,
  ),
  _FoodEntry(
    label:    'Burger',
    keywords: ['burger', 'mcdonalds', 'kfc', 'whopper'],
    calories: NutrientRange(min: 350, max: 480),   // ±15 %
    protein:  NutrientRange(min: 12.0, max: 18.0),
    tier:     _Tier.low,
  ),
  _FoodEntry(
    label:    'Wrap / Roll',
    keywords: ['wrap', 'kathi roll', 'frankie', 'burrito', 'shawarma'],
    calories: NutrientRange(min: 320, max: 450),   // ±17 %
    protein:  NutrientRange(min: 10.0, max: 16.0),
    tier:     _Tier.low,
  ),
  _FoodEntry(
    label:      'Shake / Smoothie (1 glass)',
    keywords:   ['shake', 'smoothie', 'milkshake', 'frappuccino', 'thickshake'],
    calories:   NutrientRange(min: 280, max: 360),   // ±12 %
    protein:    NutrientRange(min: 4.0, max: 8.0),
    tier:       _Tier.low,
    servingMl:  300,
  ),
  _FoodEntry(
    label:      'Soda / Coke (1 can/glass)',
    keywords:   ['coke', 'soda', 'pepsi', 'sprite', 'thumbs up'],
    calories:   NutrientRange(min: 130, max: 170),   // ±13 %
    protein:    NutrientRange(min: 0.0, max: 0.0),
    tier:       _Tier.low,
    servingMl:  330,
  ),
];

// ─── Engine constants ─────────────────────────────────────────────────────────

// Portion signals
const _thodaWords  = ['thoda', 'little', 'thodi', 'kam', 'half', 'aadha'];
const _doubleWords = ['double', 'extra', 'zyada', 'large', 'big', 'full'];

// Mess partial-eat: dal/sabzi 55–65 % eaten
const _sideEatMin = 0.55;
const _sideEatMax = 0.65;

// Uncertainty penalty when qty is not explicit (±8 % spread added)
const _unknownQtySpread = 0.08;

// ─── Helpers ─────────────────────────────────────────────────────────────────

double _rnd(double v) => double.parse(v.toStringAsFixed(1));

NutrientRange _scale(NutrientRange r, double factor) =>
    NutrientRange(min: _rnd(r.min * factor), max: _rnd(r.max * factor));

/// Scale a range by [minFactor, maxFactor] independently.
NutrientRange _scaleRange(NutrientRange r, double minF, double maxF) =>
    NutrientRange(min: _rnd(r.min * minF), max: _rnd(r.max * maxF));

bool _hasWord(List<String> tokens, Iterable<String> words) =>
    tokens.any(words.contains);

/// Extract an integer/decimal immediately before or after keyword position.
/// Returns (value, certain) — certain=false means we guessed qty=1.
(double qty, bool certain) _extractQty(List<String> tokens, int idx) {
  if (idx > 0) {
    final n = double.tryParse(tokens[idx - 1]);
    if (n != null && n > 0 && n < 20) return (n, true);
  }
  if (idx < tokens.length - 1) {
    final n = double.tryParse(tokens[idx + 1]);
    if (n != null && n > 0 && n < 20) return (n, true);
  }
  return (1.0, false);
}

/// Narrow a range to target ±halfSpread around its midpoint.
NutrientRange _clampSpread(NutrientRange r, double maxSpread) {
  final current = (r.max - r.min) / (r.mid == 0 ? 1 : r.mid);
  if (current <= maxSpread) return r;
  final half = r.mid * maxSpread / 2;
  return NutrientRange(min: _rnd(r.mid - half), max: _rnd(r.mid + half));
}

/// Widen a range by additively padding each side.
NutrientRange _widen(NutrientRange r, double extraSpread) {
  final pad = r.mid * extraSpread / 2;
  return NutrientRange(min: _rnd(r.min - pad), max: _rnd(r.max + pad));
}

/// Returns the set of token indices claimed by the match, or null if no match.
/// Uses [claimed] to avoid re-using tokens already consumed by a prior match.
/// This prevents 'egg' from matching after 'egg whites' has already claimed it.
Set<int>? _matchedIndices(
  List<String> dbKeywords,
  List<String> tokens,
  Set<int> claimed,
) {
  for (final kw in dbKeywords) {
    final parts = kw.toLowerCase().split(' ');
    final indices = <int>[];
    bool ok = true;
    for (final part in parts) {
      bool found = false;
      for (int i = 0; i < tokens.length; i++) {
        if (tokens[i] == part && !claimed.contains(i) && !indices.contains(i)) {
          indices.add(i);
          found = true;
          break;
        }
      }
      if (!found) { ok = false; break; }
    }
    if (ok && indices.length == parts.length) return indices.toSet();
  }
  return null;
}

/// Scan [raw] for a `N ml` pattern near ANY of [keywords].
/// Returns the raw ml value (not a serving multiplier), or null if not found.
double? _rawMlForEntry(String raw, List<String> keywords) {
  for (final kw in keywords) {
    final mlPat  = RegExp(r'(\d+(?:\.\d+)?)\s*ml', caseSensitive: false);
    final kwPat  = RegExp(RegExp.escape(kw), caseSensitive: false);
    final kwMatch = kwPat.firstMatch(raw);
    if (kwMatch == null) continue;
    for (final m in mlPat.allMatches(raw)) {
      if ((m.start - kwMatch.start).abs() < 35) {
        final v = double.tryParse(m.group(1)!);
        if (v != null) return v;
      }
    }
  }
  return null;
}

/// Scan [raw] for a `N g` / `Ng` pattern near ANY of [keywords].
double? _rawGramsForEntry(String raw, List<String> keywords) {
  final gPat = RegExp(r'(\d+(?:\.\d+)?)\s*g\b', caseSensitive: false);
  for (final kw in keywords) {
    final kwPat   = RegExp(RegExp.escape(kw), caseSensitive: false);
    final kwMatch = kwPat.firstMatch(raw);
    if (kwMatch == null) continue;
    for (final m in gPat.allMatches(raw)) {
      if ((m.start - kwMatch.start).abs() < 35) {
        final v = double.tryParse(m.group(1)!);
        if (v != null) return v;
      }
    }
  }
  return null;
}

// ─── Main entry point ─────────────────────────────────────────────────────────

EstimationResult mockProcessMealInput(String input) {
  return analyzeLocalEstimation(input).estimation;
}

const _coverageFillerTokens = {
  'and',
  'with',
  'some',
  'a',
  'an',
  'of',
  'the',
  'i',
  'ate',
  'had',
  'for',
  'to',
  'plus',
};

LocalEstimationAnalysis analyzeLocalEstimation(String input) {
  final lc     = input.toLowerCase().trim();
  final tokens = lc.split(RegExp(r'[\s,+&/]+'));

  if (lc.isEmpty) {
    return const LocalEstimationAnalysis(
      estimation: EstimationResult(
        items:      [],
        calories:   NutrientRange(min: 0, max: 0),
        protein:    NutrientRange(min: 0, max: 0),
        confidence: 0,
        warnings:   ['No input provided.'],
      ),
      meaningfulTokenCount: 0,
      matchedTokenCount: 0,
      matchedKeywords: [],
    );
  }

  final meaningfulTokenCount = tokens
      .where((t) => t.isNotEmpty)
      .where((t) => !_coverageFillerTokens.contains(t))
      .where((t) => double.tryParse(t) == null)
      .length;

  // ── Global portion signals ────────────────────────────────────────────────
  final hasThoda  = _hasWord(tokens, _thodaWords);
  final hasDouble = _hasWord(tokens, _doubleWords);
  final globalQtyMod = hasThoda ? 0.75 : hasDouble ? 1.75 : 1.0;

  // ── Match db entries ──────────────────────────────────────────────────────
  // Process longer keyword phrases first to avoid partial matches.
  final sortedDb = [..._db]
    ..sort((a, b) =>
        b.keywords.first.length.compareTo(a.keywords.first.length));

  final matched     = <FoodItem>[];
  final matchedKeywords = <String>[];
  final seenLabels  = <String>{};
  final claimedTokens = <int>{}; // token indices already used by a prior match
  int   uncertainItems = 0;
  final matchedEntries = <_FoodEntry>[];

  for (final entry in sortedDb) {
    final matchIdx = _matchedIndices(entry.keywords, tokens, claimedTokens);
    if (matchIdx == null) continue;
    if (seenLabels.contains(entry.label)) continue;
    seenLabels.add(entry.label);
    claimedTokens.addAll(matchIdx); // mark these token positions as consumed
    matchedEntries.add(entry);
    matchedKeywords.add(entry.keywords.first);

    // ── Quantity extraction ─────────────────────────────────────────────────
    final kwIdx = matchIdx.isNotEmpty
        ? matchIdx.reduce((a, b) => a < b ? a : b)
        : -1;

    double qty;
    bool   certain;
    String? mlLabel;

    // Gram-based foods (tofu etc.): try "Ng" pattern first.
    if (entry.servingGrams != null) {
      final rawG = _rawGramsForEntry(lc, entry.keywords);
      if (rawG != null && rawG > 0) {
        qty     = rawG / entry.servingGrams!;
        certain = true;
        mlLabel = '${rawG.toInt()} g';
      } else {
        final r = _extractQty(tokens, kwIdx);
        qty     = r.$1;
        certain = r.$2;
      }
    // Volumetric foods (milk etc.): try "Nml" pattern.
    } else if (entry.servingMl != null) {
      final rawMl = _rawMlForEntry(lc, entry.keywords);
      if (rawMl != null && rawMl > 0) {
        qty      = rawMl / entry.servingMl!;
        certain  = true;
        mlLabel  = '${rawMl.toInt()} ml';
      } else {
        final r = _extractQty(tokens, kwIdx);
        qty     = r.$1;
        certain = r.$2;
      }
    } else {
      final r = _extractQty(tokens, kwIdx);
      qty     = r.$1;
      certain = r.$2;
    }
    if (!certain) uncertainItems++;

    // ── Calories range for this item ────────────────────────────────────────
    var cal  = entry.calories;
    var prot = entry.protein;

    // Apply partial-eat for sides (dal/sabzi)
    if (entry.isSide) {
      cal  = _scaleRange(cal,  _sideEatMin, _sideEatMax);
      prot = _scaleRange(prot, _sideEatMin, _sideEatMax);
    }

    // Scale by quantity
    cal  = _scale(cal,  qty * globalQtyMod);
    prot = _scale(prot, qty * globalQtyMod);

    // Add uncertainty spread when qty was not explicit
    if (!certain) {
      cal  = _widen(cal,  _unknownQtySpread);
      prot = _widen(prot, _unknownQtySpread);
    }

    // Enforce maximum spreads per schema:
    // isSide+uncertain → up to 20%, otherwise 15%
    final maxSpread = (entry.isSide || !certain) ? 0.20 : 0.15;
    cal  = _clampSpread(cal,  maxSpread);
    prot = _clampSpread(prot, maxSpread);

    // Use ml-derived label if available, otherwise use the DB label.
    final itemName = mlLabel != null
        ? '${entry.label.split('(').first.trim()} ($mlLabel)'
        : entry.label;
    matched.add(FoodItem(name: itemName, calories: cal, protein: prot));
  }

  // ── Nothing recognised ────────────────────────────────────────────────────
  if (matched.isEmpty) {
    return LocalEstimationAnalysis(
      estimation: const EstimationResult(
        items:      [],
        calories:   NutrientRange(min: 0, max: 0),
        protein:    NutrientRange(min: 0, max: 0),
        confidence: 0,
        warnings:   ['No recognised food items — try rephrasing.'],
      ),
      meaningfulTokenCount: meaningfulTokenCount,
      matchedTokenCount: 0,
      matchedKeywords: const [],
    );
  }

  // ── Aggregate ─────────────────────────────────────────────────────────────
  var totalCal  = const NutrientRange(min: 0, max: 0);
  var totalProt = const NutrientRange(min: 0, max: 0);
  for (final item in matched) {
    totalCal  = NutrientRange(min: totalCal.min + item.calories.min,
                              max: totalCal.max + item.calories.max);
    totalProt = NutrientRange(min: totalProt.min + item.protein.min,
                              max: totalProt.max + item.protein.max);
  }

  // Enforce total spread caps: mixed meal → ≤20 %, single → ≤15 %
  final totalSpread = matched.length > 1 ? 0.20 : 0.15;
  totalCal  = _clampSpread(totalCal,  totalSpread);
  totalProt = _clampSpread(totalProt, totalSpread);

  // ── Confidence ────────────────────────────────────────────────────────────
  // Average base confidence across matched items (food-aware),
  // then reduce slightly for inferred quantities and portion signals.
  //
  // Per-item bases (from _Tier):
  //   veryHigh → 0.90  (egg, milk, oats, packaged)
  //   high     → 0.81  (roti, rice, paneer, curd)
  //   medium   → 0.68  (dal, sabzi, biryani, paratha)
  //   low      → 0.56  (puri, samosa, coffee)
  //
  // Quantity penalty: −0.04 per uncertain item, capped at −0.12.
  // Portion signal:   −0.04 for thoda/double.
  // We only penalise once even if multiple items have inferred qty.

  final avgBase = matchedEntries.isEmpty
      ? 0.68
      : matchedEntries.map((e) => e.baseConfidence).reduce((a, b) => a + b)
            / matchedEntries.length;

  double conf = avgBase
      - (uncertainItems * 0.04).clamp(0.0, 0.12)
      - ((hasThoda || hasDouble) ? 0.04 : 0.0);
  conf = conf.clamp(0.45, 0.95);

  // ── Warnings (show only when genuinely useful) ────────────────────────────
  final warnings = <String>[];

  if (hasThoda)  warnings.add('Small portion — output adjusted down slightly.');
  if (hasDouble) warnings.add('Large portion — output adjusted up.');

  // Warn only when ≥2 items were uncertain, or confidence dropped below 0.75.
  if (uncertainItems > 0 && (conf < 0.75 || uncertainItems > 1)) {
    if (uncertainItems == 1) {
      warnings.add('Estimated one item using a typical serving size.');
    } else {
      warnings.add('Used standard portions for $uncertainItems items.');
    }
  }

  final hasSide = matchedEntries.any((e) => e.isSide);
  final hasCarb = matchedEntries.any((e) => e.isCarb);
  if (hasSide && !hasCarb) {
    warnings.add('No carbs detected — looks like a light sides-only meal.');
  }

  final estimation = EstimationResult(
    items: matched,
    calories: NutrientRange(min: _rnd(totalCal.min), max: _rnd(totalCal.max)),
    protein: NutrientRange(min: _rnd(totalProt.min), max: _rnd(totalProt.max)),
    confidence: double.parse(conf.toStringAsFixed(2)),
    warnings: warnings,
  );

  return LocalEstimationAnalysis(
    estimation: estimation,
    meaningfulTokenCount: meaningfulTokenCount,
    matchedTokenCount: claimedTokens.length,
    matchedKeywords: matchedKeywords,
  );
}
