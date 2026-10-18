// Tier-1 micronutrients: the gaps that matter most in Indian diets,
// especially vegetarian ones (iron, B12, vitamin D, calcium), plus the
// electrolytes (sodium, potassium) and two cheap extras (magnesium, zinc).
//
// A food carries a [Micronutrients] only when we actually know its values
// (food library, pack label, or Kyno's estimate). Absence means "not tracked",
// never zero: an old entry without micros must never read as "0 mg iron".

/// One tracked micronutrient.
enum Micro {
  iron('iron_mg', 'Iron', 'mg'),
  calcium('calcium_mg', 'Calcium', 'mg'),
  vitaminB12('vitamin_b12_ug', 'Vitamin B12', 'µg'),
  vitaminD('vitamin_d_ug', 'Vitamin D', 'µg'),
  sodium('sodium_mg', 'Sodium', 'mg'),
  potassium('potassium_mg', 'Potassium', 'mg'),
  magnesium('magnesium_mg', 'Magnesium', 'mg'),
  zinc('zinc_mg', 'Zinc', 'mg');

  const Micro(this.key, this.label, this.unit);

  /// JSON key, with the unit in the name so the stored value is unambiguous.
  final String key;
  final String label;
  final String unit;

  /// Sodium is a ceiling to stay under, not a target to reach.
  bool get isLimit => this == Micro.sodium;

  /// Most a single logged food can plausibly carry. Guards against a
  /// mis-keyed label or a model slip turning one meal into a month of iron.
  double get perFoodCap => switch (this) {
        Micro.iron => 60,
        Micro.calcium => 2500,
        Micro.vitaminB12 => 100,
        Micro.vitaminD => 100,
        Micro.sodium => 6000,
        Micro.potassium => 5000,
        Micro.magnesium => 1000,
        Micro.zinc => 40,
      };

  static Micro? fromKey(String raw) {
    final k = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final m in Micro.values) {
      if (m.key.replaceAll('_', '') == k) return m;
    }
    return _aliases[k];
  }

  static const Map<String, Micro> _aliases = {
    'iron': Micro.iron,
    'calcium': Micro.calcium,
    'vitaminb12': Micro.vitaminB12,
    'b12': Micro.vitaminB12,
    'b12ug': Micro.vitaminB12,
    'vitaminb12mcg': Micro.vitaminB12,
    'vitamind': Micro.vitaminD,
    'vitamindmcg': Micro.vitaminD,
    'sodium': Micro.sodium,
    'potassium': Micro.potassium,
    'magnesium': Micro.magnesium,
    'zinc': Micro.zinc,
  };
}

/// Known micronutrient amounts for one food or one meal. Only the keys present
/// are tracked; [operator []] returns null for the rest.
class Micronutrients {
  const Micronutrients(this.values);

  final Map<Micro, double> values;

  static const Micronutrients empty = Micronutrients({});

  bool get isEmpty => values.isEmpty;
  bool has(Micro m) => values.containsKey(m);
  double? operator [](Micro m) => values[m];

  /// Every amount multiplied by [factor] (a bigger or smaller portion).
  Micronutrients scaled(double factor) {
    if (!factor.isFinite || factor < 0) return empty;
    return Micronutrients({
      for (final e in values.entries) e.key: _round(e.value * factor),
    });
  }

  /// Sum of two foods: a key is kept when either side has it.
  Micronutrients operator +(Micronutrients other) {
    final out = Map<Micro, double>.from(values);
    other.values.forEach((k, v) => out[k] = _round((out[k] ?? 0) + v));
    return Micronutrients(out);
  }

  /// [this] with [other]'s values filling only the keys [this] lacks.
  Micronutrients fillFrom(Micronutrients other) {
    final out = Map<Micro, double>.from(other.values)..addAll(values);
    return Micronutrients(out);
  }

  Map<String, dynamic> toJson() => {
        for (final e in values.entries) e.key.key: e.value,
      };

  /// Tolerant reader: accepts our keys and loose variants ("iron", "b12"),
  /// drops non-numeric, negative or implausible values. Returns null when
  /// nothing usable is left, so "no data" stays "no data".
  static Micronutrients? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final out = <Micro, double>{};
    raw.forEach((k, v) {
      final m = Micro.fromKey(k.toString());
      if (m == null) return;
      final d = v is num ? v.toDouble() : double.tryParse(v.toString());
      if (d == null || !d.isFinite || d < 0 || d > m.perFoodCap) return;
      out[m] = _round(d);
    });
    return out.isEmpty ? null : Micronutrients(out);
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  @override
  bool operator ==(Object other) {
    if (other is! Micronutrients || other.values.length != values.length) return false;
    for (final e in values.entries) {
      if (other.values[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(values.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'Micronutrients(${toJson()})';
}
