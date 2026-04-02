import '../services/mock_estimation_service.dart' show NutrientRange;

enum MealDensityCategory { light, medium, high, veryHigh }

class MealClassification {
  final MealDensityCategory category;
  final List<String> matchedSignals;
  final String reason;

  const MealClassification({
    required this.category,
    required this.matchedSignals,
    required this.reason,
  });

  NutrientRange recommendedMealFloor({required bool hasCarbBase}) {
    return switch (category) {
      MealDensityCategory.light => NutrientRange(
          min: hasCarbBase ? 220 : 120,
          max: hasCarbBase ? 300 : 180,
        ),
      MealDensityCategory.medium => NutrientRange(
          min: hasCarbBase ? 300 : 200,
          max: hasCarbBase ? 420 : 310,
        ),
      MealDensityCategory.high => NutrientRange(
          min: hasCarbBase ? 450 : 300,
          max: hasCarbBase ? 580 : 420,
        ),
      MealDensityCategory.veryHigh => NutrientRange(
          min: hasCarbBase ? 550 : 400,
          max: hasCarbBase ? 700 : 540,
        ),
    };
  }
}

class MealClassifier {
  const MealClassifier._();
  static const MealClassifier instance = MealClassifier._();

  // ── Mess / hostel context signals ────────────────────────────────────────
  //
  // When these are present in the input, the meal is interpreted as hostel
  // mess food — portions are smaller, gravy is partial, and the density
  // category is capped at `medium` EVEN IF other signals suggest higher.
  //
  // This prevents "paneer do pyaza + roti" from being flagged veryHigh and
  // getting restaurant-level floors applied to it.

  static const _messContextSignals = [
    'mess',
    'hostel',
    'compartment',
    'compartments',
    'thali',
    'section',
    'tray',
  ];

  static final Map<MealDensityCategory, List<String>> _signals = {
    MealDensityCategory.veryHigh: [
      'kadhi pakoda',
      'paneer butter masala',
      'butter paneer',
      'dal makhani',
      'biryani',
      'fried gravy',
      'fried curry',
      'restaurant curry',
      'restaurant thali',
      'dhaba thali',
    ],
    MealDensityCategory.high: [
      'kadhi',
      'pakoda',
      'pakora',
      'makhani',
      'butter masala',
      'paneer masala',
      'paneer curry',
      'oily paneer',
      'creamy curry',
      'korma',
      'malai',
      'restaurant',
      'fried',
      'fries',
      'peanut butter',
    ],
    MealDensityCategory.medium: [
      'paneer',
      'rajma',
      'chole',
      'paratha',
      'omelette',
      'curd rice',
      'poori',
      'puri',
      'soya',
      'dal',
    ],
    MealDensityCategory.light: [],
  };

  MealClassification classify(String rawInput) {
    final lc = rawInput.toLowerCase();
    final isMessContext = _messContextSignals.any(lc.contains);

    final matches = <String>[];

    for (final category in [
      MealDensityCategory.veryHigh,
      MealDensityCategory.high,
      MealDensityCategory.medium,
    ]) {
      for (final signal in _signals[category]!) {
        if (lc.contains(signal)) matches.add(signal);
      }
      if (matches.isNotEmpty) {
        // ── Mess context downgrade ────────────────────────────────────────────
        //
        // If the input contains mess/hostel/compartment signals, cap the
        // classified density at `medium`. This prevents paneer dishes in a
        // mess tray from getting restaurant-level density floors.
        //
        // Exception: explicitly restaurant/dhaba/outside context overrides
        // the downgrade (they already matched veryHigh signals like
        // "restaurant curry" rather than just "paneer").
        MealDensityCategory effective = category;
        if (isMessContext && !_isRestaurantContext(lc)) {
          if (effective == MealDensityCategory.veryHigh) {
            effective = MealDensityCategory.medium;
          } else if (effective == MealDensityCategory.high) {
            effective = MealDensityCategory.medium;
          }
        }

        return MealClassification(
          category: effective,
          matchedSignals: List.unmodifiable(matches),
          reason: isMessContext && effective != category
              ? 'Mess context — downgraded from ${category.name} to ${effective.name} (matched ${matches.join(', ')})'
              : 'Matched ${matches.join(', ')}',
        );
      }
    }

    return const MealClassification(
      category: MealDensityCategory.light,
      matchedSignals: [],
      reason: 'No high-density mixed meal signals found',
    );
  }

  static bool _isRestaurantContext(String lc) => const [
    'restaurant',
    'outside',
    'hotel',
    'dhaba',
    'fast food',
    'zomato',
    'swiggy',
  ].any(lc.contains);
}