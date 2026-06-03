import '../services/item_parser.dart';

// ─── FoodRole ─────────────────────────────────────────────────────────────────
//
// Generic functional roles that describe HOW a food is consumed relative to
// the other foods in the same meal.  Roles are used by EatingPatternService
// to learn consumption-behaviour scalars at a generalised level — patterns
// learned from "dal eaten with roti" apply equally to "pasta sauce eaten with
// pasta", because both are (accompaniment, context: primary).
//
// NO food-name hardcoding lives in this file.  To support a new food, add its
// keyword(s) to the appropriate list below.  The classifier is a pure
// keyword-lookup; it never contains if/else blocks for specific foods.

enum FoodRole {
  /// Starch/base foods that anchor portion size for the whole meal.
  /// More primary food → different quantity of accompaniments consumed.
  /// Examples: rice, bread, roti, pasta, oats, noodles, quinoa, tortilla.
  primary,

  /// Protein-dense foods eaten for a specific nutritional goal.
  /// Quantity is largely independent of other foods in the meal.
  /// Examples: chicken, paneer, tofu, eggs, whey, fish, yogurt, cottage cheese.
  protein,

  /// Dishes eaten alongside a primary food — consumption scales with it.
  /// Examples: dal, rajma, channa, curry, sabzi, pasta sauce, gravy, dip, soup.
  accompaniment,

  /// Calorie-dense additions applied on top of or alongside primary foods.
  /// Usually in fixed small amounts regardless of primary quantity.
  /// Examples: peanut butter, butter, cheese, dressings, jam, ghee, honey.
  addOn,

  /// Self-contained single-food portions — no role relationship to other items.
  /// Examples: protein bar, banana, apple, pizza slice, burger, fruit.
  completeMeal,
}

// ─── RolledFoodItem ───────────────────────────────────────────────────────────

class RolledFoodItem {
  final ParsedFoodItem parsed;
  final FoodRole role;

  const RolledFoodItem(this.parsed, this.role);

  @override
  String toString() =>
      'RolledFoodItem(${parsed.normalizedName}, role: ${role.name})';
}

// ─── FoodRoleClassifier ───────────────────────────────────────────────────────

class FoodRoleClassifier {
  FoodRoleClassifier._();

  // ── Keyword tables ──────────────────────────────────────────────────────────
  // Order of tables determines priority when a food matches multiple roles.
  // More specific roles (addOn) are checked before broader ones (primary).
  //
  // These are lower-cased substrings — matching uses String.contains().
  // Add new keywords here; do NOT add food-specific if/else blocks.

  static const _addOnKeywords = <String>[
    'peanut butter', 'almond butter', 'cashew butter', 'nut butter',
    'butter', 'ghee', 'oil', 'olive oil', 'coconut oil',
    'cheese', 'cream cheese', 'shredded cheese',
    'jam', 'jelly', 'honey', 'maple syrup', 'syrup',
    'nutella', 'chocolate spread',
    'mayonnaise', 'mayo', 'aioli',
    'cream', 'sour cream', 'whipped cream',
    'ketchup', 'mustard', 'hot sauce', 'bbq sauce',
    'dressing', 'ranch', 'vinaigrette',
    'topping', 'sprinkle', 'garnish',
    'spread', 'glaze',
    'condensed milk', 'coconut milk',
  ];

  static const _proteinKeywords = <String>[
    'chicken', 'turkey', 'beef', 'pork', 'lamb', 'mutton', 'shrimp',
    'fish', 'tuna', 'salmon', 'tilapia', 'cod', 'mackerel',
    'egg', 'egg white', 'boiled egg', 'omelette', 'scrambled egg',
    'paneer', 'tofu', 'tempeh', 'seitan', 'edamame',
    'whey', 'protein powder', 'casein', 'plant protein',
    'cottage cheese', 'greek yogurt', 'skyr',
    'soya chunk', 'soy chunk',
    'lentil', 'moong', 'masoor', 'arhar', 'toor',   // lentils as protein when standalone
    'chickpea alone', 'tofu scramble',
  ];

  static const _primaryKeywords = <String>[
    'rice', 'chawal', 'brown rice', 'white rice', 'fried rice', 'jeera rice',
    'roti', 'chapati', 'chapatti', 'phulka', 'naan', 'paratha', 'poori',
    'bread', 'toast', 'sourdough', 'bun', 'roll', 'bagel', 'pita',
    'wrap', 'tortilla', 'flatbread', 'lavash',
    'pasta', 'spaghetti', 'penne', 'fusilli', 'fettuccine', 'macaroni',
    'noodle', 'ramen', 'udon', 'soba', 'vermicelli', 'rice noodle',
    'oat', 'oats', 'overnight oat', 'porridge',
    'quinoa', 'couscous', 'barley', 'bulgur', 'millet', 'amaranth',
    'idli', 'dosa', 'upma', 'poha', 'khichdi', 'daliya',
    'cereal', 'muesli', 'granola', 'corn flakes', 'bran flakes',
    'pancake', 'waffle', 'crepe',
  ];

  static const _accompanimentKeywords = <String>[
    // Indian dishes
    'dal', 'daal', 'rajma', 'channa', 'chole', 'chickpea', 'chhole',
    'sabzi', 'sabji', 'curry', 'gravy', 'masala', 'bhurji',
    'paneer gravy', 'palak', 'saag', 'methi', 'mixed veg',
    'sambar', 'rasam', 'kadhi', 'korma', 'makhani',
    'aloo sabzi', 'bhindi', 'gobhi', 'gobi', 'baingan',
    'kala chana', 'black chana', 'kidney bean',
    // Western / global
    'sauce', 'pasta sauce', 'marinara', 'bolognese', 'alfredo', 'pesto',
    'salsa', 'enchilada sauce', 'tikka sauce',
    'soup', 'stew', 'broth', 'bisque', 'chowder',
    'dip', 'hummus', 'tzatziki', 'guacamole', 'salsa verde',
    'gravy', 'au jus',
    'beans', 'baked bean', 'black bean', 'refried bean', 'white bean',
    'coleslaw', 'sauerkraut',
    // Generic
    'side dish', 'side',
  ];


  // ── Public API ──────────────────────────────────────────────────────────────

  /// Classifies the food role of a single normalised food name.
  /// Priority: addOn → protein → primary → accompaniment → completeMeal.
  static FoodRole classify(String normalizedFoodName) {
    final lc = normalizedFoodName.toLowerCase();
    // addOn checked first — "peanut butter" contains "butter" and must not
    // be mis-classified as primary or protein.
    if (_matchesAny(lc, _addOnKeywords))        return FoodRole.addOn;
    if (_matchesAny(lc, _proteinKeywords))      return FoodRole.protein;
    if (_matchesAny(lc, _primaryKeywords))      return FoodRole.primary;
    if (_matchesAny(lc, _accompanimentKeywords)) return FoodRole.accompaniment;
    return FoodRole.completeMeal; // safe default
  }

  /// Classifies all items in a meal and returns [RolledFoodItem]s.
  static List<RolledFoodItem> classifyAll(List<ParsedFoodItem> items) {
    return items.map((p) => RolledFoodItem(p, classify(p.normalizedName))).toList();
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  static bool _matchesAny(String lc, List<String> keywords) =>
      keywords.any(lc.contains);
}
