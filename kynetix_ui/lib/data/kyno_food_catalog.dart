// Foods Kyno can suggest that the user may never have logged.
//
// Values are per the stated everyday serving, rounded, from IFCT 2017 /
// USDA references and common Indian pack labels. They are suggestions, not
// logs: when the user taps one, it goes through the normal meal pipeline.

/// What a food contains, used to respect what the user actually eats.
enum FoodDiet { veg, egg, nonVeg }

/// When a food is sensible to eat.
enum FoodSlot { breakfast, main, snack, late }

/// Extra facts about a food.
enum FoodTag {
  /// Allowed on common Hindu vrat days (Navratri, Ekadashi): no grains or
  /// pulses, sendha namak, fruit, dairy, sabudana, kuttu, singhara, samak.
  fasting,
}

/// Words that mark a logged food as vrat-friendly, for the user's own log.
const List<String> fastingFoodWords = [
  'sabudana', 'sago', 'kuttu', 'buckwheat', 'singhar', 'water chestnut',
  'rajgira', 'amaranth', 'samak', 'sama ', 'vrat', 'makhana', 'fox nut',
  'sweet potato', 'shakarkand', 'fruit', 'banana', 'apple', 'papaya',
  'guava', 'dates', 'khajur', 'mango', 'orange', 'curd', 'dahi', 'yogurt',
  'lassi', 'chaas', 'buttermilk', 'milk', 'paneer', 'almond', 'walnut',
  'peanut', 'coconut', 'aloo', 'potato',
];

/// Whether a logged food reads as vrat-friendly.
bool isFastingFriendlyName(String name) {
  final n = ' ${name.toLowerCase()} ';
  return fastingFoodWords.any(n.contains);
}

class CatalogFood {
  const CatalogFood(
    this.name,
    this.serving,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat, {
    this.fiber = 0,
    this.diet = FoodDiet.veg,
    this.slots = const {FoodSlot.snack},
    this.noCook = false,
    this.logAs,
    this.tags = const {},
  });

  final Set<FoodTag> tags;

  /// Fine to eat on a vrat day.
  bool get isFasting => tags.contains(FoodTag.fasting);

  final String name;

  /// Human serving, e.g. "200 g", "1 katori", "2 eggs".
  final String serving;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final FoodDiet diet;
  final Set<FoodSlot> slots;

  /// Ready to eat or a 2-minute assembly (no stove).
  final bool noCook;

  /// How to phrase a compound food for the meal box ("1 scoop whey +
  /// 250 ml milk"); null uses "serving name".
  final String? logAs;

  /// Text that goes into the meal box when the user taps "Log".
  String get logText => logAs ?? '$serving $name'.replaceAll(RegExp(r'[()]'), '');

  double get proteinDensity => kcal <= 0 ? 0 : protein * 4 / kcal;
}

const _bf = {FoodSlot.breakfast};
const _main = {FoodSlot.main};
const _snack = {FoodSlot.snack};
const _any = {FoodSlot.breakfast, FoodSlot.main, FoodSlot.snack};
const _bfSnack = {FoodSlot.breakfast, FoodSlot.snack};
const _snackLate = {FoodSlot.snack, FoodSlot.late};
const _mainLate = {FoodSlot.main, FoodSlot.late};
const _vrat = {FoodTag.fasting};

const List<CatalogFood> kynoFoodCatalog = [
  // ── Dairy & paneer ──────────────────────────────────────────────────────
  CatalogFood('Greek yogurt (plain)', '200 g', 146, 20, 8, 4, slots: _snackLate, noCook: true),
  CatalogFood('hung curd', '200 g', 180, 14, 10, 9, slots: _snackLate, noCook: true),
  CatalogFood('curd (dahi)', '1 katori (150 g)', 90, 5, 7, 5, slots: _any, noCook: true, tags: _vrat),
  CatalogFood('low-fat paneer', '100 g', 200, 24, 4, 10, slots: _any),
  CatalogFood('paneer', '100 g', 295, 18, 3, 23, slots: _main, tags: _vrat),
  CatalogFood('paneer bhurji', '1 katori (150 g)', 320, 20, 8, 23, slots: _bf),
  CatalogFood('toned milk', '1 glass (250 ml)', 150, 8, 12, 8, slots: _bfSnack, noCook: true, tags: _vrat),
  CatalogFood('skimmed milk', '1 glass (250 ml)', 88, 8.5, 12, 0.5, slots: _snackLate, noCook: true),
  CatalogFood('chaas (buttermilk)', '1 glass (250 ml)', 40, 2.5, 4, 1.5, slots: _main, noCook: true, tags: _vrat),
  CatalogFood('high-protein milkshake (Amul)', '1 bottle (250 ml)', 150, 20, 14, 1.5, slots: _snack, noCook: true),
  CatalogFood('high-protein lassi (Amul)', '1 pack (200 ml)', 104, 15, 10, 0.3, slots: _snack, noCook: true),
  CatalogFood('skyr / protein yogurt', '1 cup (100 g)', 70, 10, 6, 0.5, slots: _snackLate, noCook: true),
  CatalogFood('cottage cheese (cheela filling)', '50 g', 100, 9, 2, 6, slots: _bf),

  // ── Eggs ────────────────────────────────────────────────────────────────
  CatalogFood('boiled eggs', '2 eggs', 155, 13, 1, 11, diet: FoodDiet.egg, slots: _any, noCook: true),
  CatalogFood('egg whites (boiled)', '4 whites', 68, 14, 1, 0, diet: FoodDiet.egg, slots: _any),
  CatalogFood('egg bhurji', '3 eggs', 270, 19, 4, 20, diet: FoodDiet.egg, slots: _bf),
  CatalogFood('masala omelette', '2 eggs', 200, 13, 3, 15, diet: FoodDiet.egg, slots: _bf),
  CatalogFood('egg white omelette', '5 whites', 110, 18, 3, 3, diet: FoodDiet.egg, slots: _bf),
  CatalogFood('egg curry', '2 eggs + gravy', 280, 15, 9, 20, diet: FoodDiet.egg, slots: _main, logAs: '2 egg curry'),

  // ── Meat & fish ─────────────────────────────────────────────────────────
  CatalogFood('grilled chicken breast', '150 g', 248, 46, 0, 5.4, diet: FoodDiet.nonVeg, slots: _mainLate),
  CatalogFood('chicken tikka (dry)', '6 pieces (180 g)', 290, 40, 6, 11, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('tandoori chicken', '2 pieces (250 g)', 330, 40, 6, 16, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('chicken curry (home)', '1 katori (200 g)', 280, 26, 8, 16, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('fish curry (home)', '1 katori (200 g)', 230, 24, 6, 12, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('grilled fish (rohu/basa)', '150 g', 180, 30, 0, 6, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('canned tuna in water', '1 can (100 g drained)', 116, 26, 0, 1, diet: FoodDiet.nonVeg, slots: _any, noCook: true),
  CatalogFood('chicken keema', '1 katori (150 g)', 260, 28, 5, 14, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('mutton curry (home)', '1 katori (200 g)', 380, 28, 6, 27, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('prawns masala', '150 g', 210, 30, 6, 7, diet: FoodDiet.nonVeg, slots: _main),

  // ── Soy, tofu, legumes ──────────────────────────────────────────────────
  CatalogFood('soya chunks (dry weight)', '50 g', 172, 26, 17, 0.3, fiber: 6.5, slots: _main),
  CatalogFood('soya chunk curry', '1 katori (150 g)', 220, 22, 15, 8, fiber: 5, slots: _main),
  CatalogFood('tofu (firm)', '150 g', 215, 24, 4, 12, slots: _any),
  CatalogFood('tofu bhurji', '1 katori (150 g)', 240, 22, 6, 14, slots: _bf),
  CatalogFood('moong dal (home)', '1 katori (150 g)', 110, 7, 16, 2, fiber: 4, slots: _main),
  CatalogFood('chana dal (home)', '1 katori (150 g)', 150, 8, 20, 4, fiber: 5, slots: _main),
  CatalogFood('rajma (home)', '1 katori (150 g)', 140, 7, 20, 3.5, fiber: 6, slots: _main),
  CatalogFood('chole (home)', '1 katori (150 g)', 180, 8, 24, 6, fiber: 7, slots: _main),
  CatalogFood('sprouts chaat', '1 bowl (150 g)', 140, 10, 22, 1.5, fiber: 6, slots: _bfSnack, noCook: true),
  CatalogFood('besan cheela', '2 cheelas', 240, 12, 28, 8, fiber: 5, slots: _bf),
  CatalogFood('moong dal cheela', '2 cheelas', 220, 13, 30, 5, fiber: 5, slots: _bf),
  CatalogFood('roasted chana', '40 g', 150, 8, 24, 2.5, fiber: 7, slots: _snack, noCook: true),
  CatalogFood('peanuts (roasted)', '30 g', 170, 7.5, 5, 14, fiber: 2.5, slots: _snack, noCook: true, tags: _vrat),
  CatalogFood('peanut butter', '1 tbsp (16 g)', 95, 3.5, 3, 8, slots: _bfSnack, noCook: true),
  CatalogFood('edamame (shelled)', '100 g', 121, 12, 9, 5, fiber: 5, slots: _snack),

  // ── Supplements & packaged protein ──────────────────────────────────────
  CatalogFood('whey protein in water', '1 scoop (30 g)', 120, 24, 3, 1.5, slots: _any, noCook: true, logAs: '1 scoop whey in water'),
  CatalogFood('whey protein in milk', '1 scoop + 250 ml milk', 270, 32, 15, 9.5, slots: _bfSnack, noCook: true, logAs: '1 scoop whey + 250 ml milk'),
  CatalogFood('protein bar', '1 bar (60 g)', 220, 20, 22, 7, slots: _snack, noCook: true),

  // ── Grains & breakfasts ─────────────────────────────────────────────────
  CatalogFood('oats with milk', '50 g oats + 200 ml milk', 310, 15, 42, 9, fiber: 5, slots: _bf, logAs: '50 g oats + 200 ml milk'),
  CatalogFood('overnight oats + whey', '50 g oats + 1 scoop', 310, 30, 36, 5, fiber: 5, slots: _bf, noCook: true, logAs: '50 g oats + 1 scoop whey'),
  CatalogFood('poha', '1 plate (200 g)', 250, 5, 42, 7, fiber: 2, slots: _bf),
  CatalogFood('upma', '1 plate (200 g)', 250, 6, 38, 8, fiber: 3, slots: _bf),
  CatalogFood('idli with sambar', '3 idlis + 1 katori', 280, 10, 52, 3, fiber: 5, slots: _bf, logAs: '3 idli + 1 katori sambar'),
  CatalogFood('plain dosa with sambar', '1 dosa + 1 katori', 300, 9, 48, 8, fiber: 4, slots: _bf, logAs: '1 plain dosa + 1 katori sambar'),
  CatalogFood('roti (plain)', '1 roti', 90, 3, 18, 0.5, fiber: 2.5, slots: _main),
  CatalogFood('rice (cooked)', '1 bowl (150 g)', 195, 4, 43, 0.4, fiber: 0.6, slots: _main),
  CatalogFood('brown rice (cooked)', '1 bowl (150 g)', 170, 4, 36, 1.4, fiber: 2.7, slots: _main),
  CatalogFood('multigrain bread', '2 slices', 140, 6, 24, 2, fiber: 4, slots: _bf, noCook: true),
  CatalogFood('peanut butter toast', '2 slices + 1 tbsp', 235, 9.5, 27, 10, fiber: 4.5, slots: _bfSnack, noCook: true, logAs: '2 slices bread + 1 tbsp peanut butter'),
  CatalogFood('egg sandwich', '2 slices + 2 eggs', 300, 19, 25, 13, diet: FoodDiet.egg, slots: _bfSnack, logAs: '2 slices bread + 2 boiled eggs'),
  CatalogFood('paneer roti roll', '1 roll', 380, 18, 34, 19, slots: _main),
  CatalogFood('chicken roti roll', '1 roll', 360, 28, 32, 13, diet: FoodDiet.nonVeg, slots: _main),
  CatalogFood('veg pulao', '1 plate (200 g)', 300, 6, 50, 8, fiber: 3, slots: _main),
  CatalogFood('khichdi', '1 bowl (250 g)', 280, 10, 46, 6, fiber: 5, slots: _mainLate),
  CatalogFood('chicken biryani', '1 plate (300 g)', 490, 25, 55, 18, diet: FoodDiet.nonVeg, slots: _main),

  // ── Vegetables & salads ─────────────────────────────────────────────────
  CatalogFood('mixed veg sabzi', '1 katori (150 g)', 110, 3, 12, 6, fiber: 4, slots: _main),
  CatalogFood('palak paneer', '1 katori (150 g)', 230, 11, 8, 17, fiber: 3, slots: _main),
  CatalogFood('kachumber salad', '1 bowl', 45, 2, 9, 0.3, fiber: 3, slots: _main, noCook: true),
  CatalogFood('chicken salad', '1 bowl (150 g chicken)', 300, 42, 10, 9, fiber: 3, diet: FoodDiet.nonVeg, slots: _main, noCook: true, logAs: '150 g chicken salad'),
  CatalogFood('paneer tikka (dry)', '6 pieces (150 g)', 330, 22, 8, 23, slots: _main),

  // ── Fruit & light snacks ────────────────────────────────────────────────
  CatalogFood('banana', '1 medium', 105, 1.3, 27, 0.4, fiber: 3, slots: _bfSnack, noCook: true, tags: _vrat),
  CatalogFood('apple', '1 medium', 95, 0.5, 25, 0.3, fiber: 4.4, slots: _snack, noCook: true, tags: _vrat),
  CatalogFood('papaya', '1 bowl (200 g)', 86, 1, 22, 0.5, fiber: 3.4, slots: _bfSnack, noCook: true, tags: _vrat),
  CatalogFood('guava', '1 medium', 70, 2.6, 14, 1, fiber: 5.4, slots: _snack, noCook: true, tags: _vrat),
  CatalogFood('dates', '3 dates', 70, 0.6, 19, 0, fiber: 2, slots: _snack, noCook: true, tags: _vrat),
  CatalogFood('makhana (roasted)', '30 g', 105, 3, 23, 0.2, fiber: 2, slots: _snackLate, noCook: true, tags: _vrat),
  CatalogFood('almonds', '20 g', 116, 4, 4, 10, fiber: 2.5, slots: _snack, noCook: true, tags: _vrat),
  CatalogFood('walnuts', '15 g', 98, 2.3, 2, 9.8, fiber: 1, slots: _snack, noCook: true, tags: _vrat),
  CatalogFood('dark chocolate (70%)', '20 g', 120, 1.6, 9, 8.5, fiber: 2, slots: _snackLate, noCook: true),
  CatalogFood('pumpkin seeds', '15 g', 85, 4.5, 2, 7, fiber: 1, slots: _snack, noCook: true),

  // ── Millets (calcium and iron for vegetarians) ──────────────────────────
  // IFCT 2017: ragi (finger millet) ~344 mg calcium per 100 g flour.
  CatalogFood('ragi roti', '1 roti', 135, 3, 29, 0.8, fiber: 4.5, slots: _main),

  // ── Vrat (fasting) foods ────────────────────────────────────────────────
  // For Navratri / Ekadashi style fasts: no grains or pulses. Values per the
  // serving from IFCT 2017 ingredients (sago, buckwheat, water-chestnut
  // flour, barnyard millet) with typical peanuts / ghee in the dish.
  CatalogFood('sabudana khichdi', '1 plate (200 g)', 350, 4, 55, 13, fiber: 2, slots: _any, tags: _vrat),
  CatalogFood('kuttu roti', '1 roti', 140, 4.5, 26, 2, fiber: 3, slots: _main, tags: _vrat),
  CatalogFood('singhare atta roti', '1 roti', 140, 2.5, 28, 2, fiber: 2, slots: _main, tags: _vrat),
  CatalogFood('samak rice (vrat ke chawal)', '1 bowl (150 g)', 165, 3.5, 33, 2, fiber: 3, slots: _main, tags: _vrat),
  CatalogFood('vrat aloo sabzi', '1 katori (150 g)', 160, 2.5, 22, 7, fiber: 2.5, slots: _main, tags: _vrat),
  CatalogFood('sweet potato (roasted)', '1 medium (150 g)', 130, 2.4, 30, 0.2, fiber: 4, slots: _any, noCook: false, tags: _vrat),
  CatalogFood('fruit bowl', '1 bowl (200 g)', 110, 1.5, 27, 0.5, fiber: 4, slots: _bfSnack, noCook: true, tags: _vrat),
  CatalogFood('casein / milk protein shake', '1 scoop + water', 120, 24, 4, 1, slots: {FoodSlot.late}, noCook: true, logAs: '1 scoop casein in water'),
];
