// Micronutrients for common Indian foods, per everyday serving.
//
// Sources: IFCT 2017 (Indian Food Composition Tables, ICMR-NIN; raw
// ingredient values converted to the cooked household serving) and USDA
// FoodData Central (SR Legacy / Foundation) where IFCT has no entry or no
// value (vitamin B12 and vitamin D, packaged foods). Home-cooked dishes
// include a typical pinch of salt in sodium; plain staples (roti, rice) do
// not. Values are rounded and meant for daily-trend tracking, not clinical use.
//
// Matching scales a serving by calories: a logged item worth twice this
// serving's kcal gets twice these amounts. That keeps it robust to however
// the portion was phrased ("2 roti", "1 katori", "150 g").

import '../models/micronutrients.dart';

class MicroFood {
  const MicroFood(
    this.aliases,
    this.serving,
    this.kcal, {
    required this.fe,
    required this.ca,
    required this.mg,
    required this.zn,
    required this.k,
    required this.na,
    this.b12 = 0,
    this.d = 0,
  });

  /// Lower-case names this food is logged as. The longest match wins.
  final List<String> aliases;
  final String serving;
  final double kcal;
  final double fe, ca, mg, zn, k, na, b12, d;

  String get name => aliases.first;

  Micronutrients get micros => Micronutrients({
        Micro.iron: fe,
        Micro.calcium: ca,
        Micro.vitaminB12: b12,
        Micro.vitaminD: d,
        Micro.sodium: na,
        Micro.potassium: k,
        Micro.magnesium: mg,
        Micro.zinc: zn,
      });
}

const List<MicroFood> microFoodLibrary = [
  // ── Grains & breads (IFCT 2017: whole-wheat atta, rice, flakes, oats) ────
  MicroFood(['roti', 'chapati', 'chapatti', 'phulka', 'fulka'], '1 roti (30 g atta)', 100, fe: 1.2, ca: 10, mg: 38, zn: 0.85, k: 95, na: 5),
  MicroFood(['paratha', 'parantha'], '1 paratha', 260, fe: 1.8, ca: 20, mg: 50, zn: 1.1, k: 130, na: 250),
  MicroFood(['ragi roti', 'ragi', 'nachni', 'finger millet'], '1 roti (40 g ragi)', 135, fe: 1.6, ca: 138, mg: 55, zn: 0.9, k: 163, na: 5),
  MicroFood(['rice', 'chawal', 'white rice', 'steamed rice', 'jeera rice'], '1 bowl cooked (150 g)', 195, fe: 0.3, ca: 15, mg: 18, zn: 0.75, k: 53, na: 2),
  MicroFood(['brown rice'], '1 bowl cooked (150 g)', 170, fe: 0.8, ca: 5, mg: 59, zn: 1.0, k: 129, na: 6),
  MicroFood(['poha'], '1 plate (200 g)', 250, fe: 2.3, ca: 15, mg: 30, zn: 0.6, k: 150, na: 400),
  MicroFood(['upma'], '1 plate (200 g)', 250, fe: 1.2, ca: 20, mg: 25, zn: 0.7, k: 120, na: 450),
  MicroFood(['idli'], '1 idli', 58, fe: 0.3, ca: 6, mg: 10, zn: 0.25, k: 25, na: 120),
  MicroFood(['dosa', 'plain dosa'], '1 dosa', 170, fe: 0.8, ca: 10, mg: 18, zn: 0.4, k: 60, na: 200),
  MicroFood(['sambar', 'sambhar'], '1 katori (150 g)', 110, fe: 1.5, ca: 40, mg: 30, zn: 0.6, k: 300, na: 450),
  MicroFood(['oats', 'oatmeal', 'porridge'], '50 g dry', 190, fe: 2.35, ca: 27, mg: 88, zn: 2.0, k: 215, na: 1),
  MicroFood(['bread', 'white bread', 'bread slice', 'toast'], '2 slices', 135, fe: 1.0, ca: 40, mg: 12, zn: 0.4, k: 60, na: 250),
  MicroFood(['multigrain bread', 'brown bread', 'whole wheat bread'], '2 slices', 140, fe: 1.2, ca: 50, mg: 40, zn: 0.8, k: 110, na: 250),
  MicroFood(['khichdi', 'khichri', 'dal khichdi'], '1 bowl (250 g)', 280, fe: 2.0, ca: 40, mg: 60, zn: 1.3, k: 300, na: 500),
  MicroFood(['pulao', 'veg pulao'], '1 plate (200 g)', 300, fe: 1.0, ca: 30, mg: 30, zn: 0.8, k: 180, na: 500),
  MicroFood(['biryani', 'chicken biryani'], '1 plate (300 g)', 490, fe: 2.5, ca: 60, mg: 50, zn: 3.0, k: 400, na: 900, b12: 0.4, d: 0.1),
  MicroFood(['veg biryani'], '1 plate (300 g)', 450, fe: 1.8, ca: 60, mg: 45, zn: 1.2, k: 350, na: 900),
  MicroFood(['maggi', 'instant noodles'], '1 pack (70 g)', 310, fe: 1.5, ca: 20, mg: 15, zn: 0.5, k: 150, na: 1100),

  // ── Dals & legumes (IFCT 2017 dry dal × ~30-35 g per cooked katori) ──────
  MicroFood(['dal', 'daal', 'toor dal', 'arhar dal', 'yellow dal', 'dal tadka', 'dal fry', 'plain dal'], '1 katori (150 g)', 120, fe: 1.2, ca: 22, mg: 35, zn: 0.85, k: 330, na: 350),
  MicroFood(['moong dal', 'mung dal', 'moong'], '1 katori (150 g)', 110, fe: 1.2, ca: 22, mg: 38, zn: 0.8, k: 330, na: 350),
  MicroFood(['masoor dal', 'masoor'], '1 katori (150 g)', 115, fe: 2.1, ca: 15, mg: 30, zn: 1.0, k: 300, na: 350),
  MicroFood(['chana dal'], '1 katori (150 g)', 150, fe: 1.8, ca: 20, mg: 45, zn: 1.0, k: 330, na: 350),
  MicroFood(['dal makhani', 'urad dal', 'maa ki dal'], '1 katori (150 g)', 230, fe: 2.0, ca: 60, mg: 50, zn: 1.2, k: 350, na: 450),
  MicroFood(['rajma', 'kidney beans'], '1 katori (150 g)', 140, fe: 2.2, ca: 40, mg: 45, zn: 1.0, k: 420, na: 400),
  MicroFood(['chole', 'chhole', 'chana masala', 'chickpeas', 'kabuli chana'], '1 katori (150 g)', 180, fe: 2.9, ca: 50, mg: 48, zn: 1.5, k: 320, na: 400),
  MicroFood(['sprouts', 'sprouts chaat', 'moong sprouts'], '1 bowl (150 g)', 140, fe: 1.6, ca: 30, mg: 40, zn: 0.8, k: 300, na: 250),
  MicroFood(['soya chunks', 'soya chunk', 'soy chunks', 'nutrela'], '50 g dry', 172, fe: 5.0, ca: 120, mg: 145, zn: 1.2, k: 1190, na: 10),
  MicroFood(['soya chunk curry', 'soya curry'], '1 katori (150 g)', 220, fe: 3.5, ca: 90, mg: 100, zn: 0.9, k: 800, na: 450),
  // Tofu calcium depends on the coagulant (calcium sulfate set is far higher
  // than nigari set); this is a middle value for Indian retail tofu.
  MicroFood(['tofu', 'firm tofu', 'tofu bhurji'], '150 g', 215, fe: 4.0, ca: 350, mg: 90, zn: 2.3, k: 270, na: 15),
  MicroFood(['besan cheela', 'besan chilla', 'cheela', 'chilla'], '2 cheelas (60 g besan)', 240, fe: 2.9, ca: 34, mg: 100, zn: 1.7, k: 500, na: 400),
  MicroFood(['moong dal cheela', 'moong chilla'], '2 cheelas', 220, fe: 2.3, ca: 45, mg: 90, zn: 1.6, k: 600, na: 400),
  MicroFood(['roasted chana', 'bhuna chana'], '40 g', 150, fe: 2.2, ca: 30, mg: 55, zn: 1.3, k: 340, na: 10),
  MicroFood(['peanuts', 'moongphali', 'groundnuts'], '30 g', 170, fe: 0.7, ca: 16, mg: 50, zn: 1.0, k: 200, na: 2),
  MicroFood(['peanut butter'], '1 tbsp (16 g)', 95, fe: 0.3, ca: 8, mg: 27, zn: 0.5, k: 105, na: 70),
  MicroFood(['edamame'], '100 g', 121, fe: 2.3, ca: 63, mg: 64, zn: 1.4, k: 436, na: 6),

  // ── Dairy (IFCT 2017 / USDA; B12 and D from USDA) ────────────────────────
  // Plain Indian packet milk is mostly unfortified for vitamin D; fortified
  // brands ("+F" logo) carry more, so a scanned pack's label wins.
  MicroFood(['milk', 'doodh', 'toned milk', 'full cream milk', 'skimmed milk', 'double toned milk'], '1 glass (250 ml)', 150, fe: 0.1, ca: 300, mg: 28, zn: 1.0, k: 375, na: 110, b12: 1.1, d: 0.25),
  MicroFood(['curd', 'dahi', 'yogurt', 'yoghurt', 'raita'], '1 katori (150 g)', 90, fe: 0.1, ca: 180, mg: 18, zn: 0.9, k: 230, na: 70, b12: 0.55, d: 0.1),
  MicroFood(['greek yogurt', 'skyr', 'protein yogurt'], '200 g', 146, fe: 0.1, ca: 220, mg: 22, zn: 1.0, k: 280, na: 70, b12: 1.5),
  MicroFood(['hung curd'], '200 g', 180, fe: 0.1, ca: 240, mg: 22, zn: 1.1, k: 300, na: 80, b12: 1.0),
  MicroFood(['chaas', 'buttermilk', 'chhaas'], '1 glass (250 ml)', 40, fe: 0.1, ca: 120, mg: 12, zn: 0.4, k: 150, na: 250, b12: 0.3),
  MicroFood(['lassi'], '1 glass (250 ml)', 180, fe: 0.1, ca: 250, mg: 25, zn: 1.0, k: 300, na: 100, b12: 0.8),
  MicroFood(['paneer', 'cottage cheese', 'low fat paneer'], '100 g', 295, fe: 0.3, ca: 400, mg: 25, zn: 2.7, k: 120, na: 30, b12: 0.8, d: 0.1),
  MicroFood(['paneer bhurji'], '1 katori (150 g)', 320, fe: 1.0, ca: 380, mg: 35, zn: 2.4, k: 250, na: 450, b12: 0.7),
  MicroFood(['palak paneer', 'saag paneer'], '1 katori (150 g)', 230, fe: 2.5, ca: 300, mg: 70, zn: 1.7, k: 450, na: 450, b12: 0.4),
  MicroFood(['paneer butter masala', 'shahi paneer', 'kadai paneer', 'paneer curry', 'matar paneer'], '1 katori (150 g)', 330, fe: 1.2, ca: 250, mg: 30, zn: 1.5, k: 300, na: 600, b12: 0.4),
  MicroFood(['paneer tikka'], '6 pieces (150 g)', 330, fe: 1.0, ca: 420, mg: 35, zn: 2.8, k: 250, na: 500, b12: 0.8),
  MicroFood(['cheese', 'cheese slice'], '1 slice (20 g)', 60, fe: 0.05, ca: 120, mg: 5, zn: 0.6, k: 25, na: 280, b12: 0.2),
  // Typical whey concentrate label per 30 g scoop; brands vary.
  MicroFood(['whey', 'whey protein', 'protein shake'], '1 scoop (30 g)', 120, fe: 0.2, ca: 120, mg: 25, zn: 0.4, k: 160, na: 60, b12: 0.4),
  MicroFood(['chai', 'tea', 'masala chai', 'coffee'], '1 cup with milk', 60, fe: 0.1, ca: 80, mg: 15, zn: 0.3, k: 120, na: 30, b12: 0.2),
  MicroFood(['ghee', 'butter', 'oil'], '1 tsp', 45, fe: 0, ca: 0, mg: 0, zn: 0, k: 0, na: 0),

  // ── Eggs (USDA FDC: whole egg, egg white) ────────────────────────────────
  MicroFood(['egg', 'boiled egg', 'anda', 'whole egg'], '1 large egg', 72, fe: 0.88, ca: 28, mg: 6, zn: 0.65, k: 69, na: 71, b12: 0.45, d: 1.0),
  MicroFood(['egg white', 'egg whites'], '1 white', 17, fe: 0.03, ca: 2, mg: 4, zn: 0.01, k: 54, na: 55, b12: 0.03),
  MicroFood(['omelette', 'omelet', 'egg bhurji', 'masala omelette'], '2 eggs', 200, fe: 1.8, ca: 70, mg: 15, zn: 1.3, k: 180, na: 400, b12: 0.9, d: 2.0),
  MicroFood(['egg curry', 'anda curry'], '2 eggs + gravy', 280, fe: 2.2, ca: 80, mg: 30, zn: 1.5, k: 350, na: 600, b12: 0.9, d: 2.0),

  // ── Meat & fish (USDA FDC; Indian curries add salt) ──────────────────────
  MicroFood(['chicken', 'chicken breast', 'grilled chicken'], '150 g cooked', 248, fe: 1.6, ca: 22, mg: 44, zn: 1.5, k: 385, na: 110, b12: 0.5, d: 0.15),
  MicroFood(['chicken curry', 'butter chicken', 'chicken masala'], '1 katori (200 g)', 280, fe: 1.8, ca: 40, mg: 40, zn: 2.0, k: 400, na: 650, b12: 0.4, d: 0.2),
  MicroFood(['chicken tikka', 'tandoori chicken'], '180 g', 290, fe: 1.8, ca: 40, mg: 45, zn: 2.0, k: 420, na: 700, b12: 0.5, d: 0.2),
  MicroFood(['chicken keema', 'keema'], '1 katori (150 g)', 260, fe: 1.5, ca: 25, mg: 35, zn: 2.0, k: 350, na: 500, b12: 0.5, d: 0.2),
  MicroFood(['mutton', 'mutton curry', 'goat curry', 'lamb'], '1 katori (200 g)', 380, fe: 3.0, ca: 30, mg: 35, zn: 6.0, k: 380, na: 650, b12: 2.5, d: 0.2),
  // Freshwater fish (rohu, basa) carry far less vitamin D than salmon.
  MicroFood(['fish', 'grilled fish', 'rohu', 'basa', 'pomfret'], '150 g', 180, fe: 1.0, ca: 60, mg: 45, zn: 0.8, k: 450, na: 100, b12: 3.0, d: 5.0),
  MicroFood(['fish curry'], '1 katori (200 g)', 230, fe: 1.3, ca: 70, mg: 45, zn: 0.9, k: 450, na: 600, b12: 2.5, d: 4.0),
  MicroFood(['tuna', 'canned tuna'], '100 g drained', 116, fe: 1.0, ca: 11, mg: 27, zn: 0.5, k: 237, na: 250, b12: 2.5, d: 1.7),
  MicroFood(['salmon'], '100 g', 208, fe: 0.3, ca: 9, mg: 27, zn: 0.4, k: 363, na: 60, b12: 3.2, d: 11.0),
  MicroFood(['prawns', 'prawn', 'shrimp', 'prawns masala'], '150 g', 210, fe: 0.8, ca: 105, mg: 50, zn: 2.4, k: 270, na: 700, b12: 2.0, d: 0.2),

  // ── Vegetables (IFCT 2017; cooked katori) ────────────────────────────────
  // Spinach iron and calcium are partly bound by oxalate, so less is absorbed
  // than the label number suggests.
  MicroFood(['palak', 'spinach', 'saag', 'palak sabzi', 'sarson ka saag'], '1 katori cooked (150 g)', 90, fe: 3.0, ca: 120, mg: 80, zn: 0.7, k: 450, na: 350),
  MicroFood(['sabzi', 'mixed veg', 'mix veg', 'vegetables', 'veg sabzi'], '1 katori (150 g)', 110, fe: 1.0, ca: 40, mg: 25, zn: 0.4, k: 300, na: 350),
  MicroFood(['aloo', 'aloo sabzi', 'potato', 'jeera aloo', 'vrat aloo'], '1 katori (150 g)', 160, fe: 0.8, ca: 15, mg: 25, zn: 0.4, k: 450, na: 350),
  MicroFood(['bhindi', 'okra'], '1 katori (150 g)', 120, fe: 0.9, ca: 90, mg: 50, zn: 0.6, k: 330, na: 350),
  MicroFood(['salad', 'kachumber', 'cucumber'], '1 bowl', 45, fe: 0.5, ca: 25, mg: 15, zn: 0.3, k: 300, na: 150),
  MicroFood(['sweet potato', 'shakarkandi', 'shakarkand'], '1 medium (150 g)', 130, fe: 1.1, ca: 40, mg: 27, zn: 0.3, k: 345, na: 40),

  // ── Fruit (USDA FDC) ─────────────────────────────────────────────────────
  MicroFood(['banana', 'kela'], '1 medium', 105, fe: 0.3, ca: 6, mg: 32, zn: 0.18, k: 422, na: 1),
  MicroFood(['apple', 'seb'], '1 medium', 95, fe: 0.2, ca: 11, mg: 9, zn: 0.07, k: 195, na: 2),
  MicroFood(['papaya', 'papita'], '1 bowl (200 g)', 86, fe: 0.5, ca: 40, mg: 42, zn: 0.15, k: 364, na: 16),
  MicroFood(['guava', 'amrood'], '1 medium', 68, fe: 0.26, ca: 18, mg: 22, zn: 0.23, k: 417, na: 2),
  MicroFood(['dates', 'khajur', 'date'], '3 dates', 70, fe: 0.25, ca: 15, mg: 13, zn: 0.1, k: 160, na: 0.5),
  MicroFood(['orange', 'santra', 'mosambi'], '1 medium', 62, fe: 0.13, ca: 52, mg: 13, zn: 0.1, k: 237, na: 0),
  MicroFood(['mango', 'aam'], '1 cup (165 g)', 99, fe: 0.27, ca: 18, mg: 16, zn: 0.15, k: 277, na: 2),
  MicroFood(['fruit', 'fruits', 'fruit bowl', 'fruit salad', 'fruit chaat'], '1 bowl (200 g)', 110, fe: 0.4, ca: 25, mg: 25, zn: 0.2, k: 380, na: 3),

  // ── Nuts, seeds, snacks ──────────────────────────────────────────────────
  MicroFood(['almonds', 'badam'], '20 g', 116, fe: 0.75, ca: 54, mg: 54, zn: 0.62, k: 147, na: 0),
  MicroFood(['walnuts', 'akhrot'], '15 g', 98, fe: 0.44, ca: 15, mg: 24, zn: 0.47, k: 66, na: 0),
  MicroFood(['pumpkin seeds'], '15 g', 85, fe: 1.2, ca: 7, mg: 80, zn: 1.2, k: 120, na: 1),
  // USDA dried lotus seeds; roasted makhana is usually lightly salted.
  MicroFood(['makhana', 'fox nuts', 'lotus seeds'], '30 g', 105, fe: 1.0, ca: 50, mg: 63, zn: 0.3, k: 410, na: 100),
  MicroFood(['dark chocolate'], '20 g', 120, fe: 2.4, ca: 15, mg: 46, zn: 0.66, k: 143, na: 4),
  MicroFood(['samosa'], '1 samosa', 250, fe: 1.0, ca: 20, mg: 15, zn: 0.4, k: 200, na: 350),
  MicroFood(['pizza'], '1 slice', 285, fe: 2.5, ca: 200, mg: 25, zn: 1.6, k: 180, na: 640, b12: 0.4),

  // ── Fasting (vrat) foods (IFCT 2017 sago, buckwheat, water-chestnut flour,
  // barnyard millet; dishes with peanuts and sendha namak) ──────────────────
  MicroFood(['sabudana khichdi', 'sabudana', 'sago'], '1 plate (200 g)', 350, fe: 1.2, ca: 30, mg: 50, zn: 0.8, k: 400, na: 500),
  MicroFood(['kuttu roti', 'kuttu', 'buckwheat'], '1 roti (40 g flour)', 140, fe: 1.6, ca: 16, mg: 100, zn: 1.25, k: 230, na: 100),
  // Water-chestnut flour composition is thinly documented; approximate.
  MicroFood(['singhare atta roti', 'singhara roti', 'singhare', 'singhara', 'water chestnut'], '1 roti (40 g flour)', 140, fe: 0.6, ca: 25, mg: 25, zn: 0.3, k: 260, na: 100),
  MicroFood(['samak rice', 'sama rice', 'vrat ke chawal', 'barnyard millet'], '1 bowl cooked (150 g)', 165, fe: 1.5, ca: 8, mg: 35, zn: 1.2, k: 80, na: 100),
  // ── Breads, rice dishes and South Indian plates (IFCT 2017 flours and
  // grains; USDA naan, pasta, cereals; restaurant salt for outside food) ──
  MicroFood(['naan', 'butter naan', 'garlic naan'], '1 naan (90 g)', 260, fe: 2.9, ca: 75, mg: 20, zn: 0.6, k: 110, na: 420),
  MicroFood(['kulcha', 'kulche', 'amritsari kulcha'], '1 kulcha', 280, fe: 2.5, ca: 60, mg: 20, zn: 0.6, k: 150, na: 450),
  MicroFood(['tandoori roti'], '1 roti', 120, fe: 1.4, ca: 12, mg: 40, zn: 0.9, k: 110, na: 150),
  MicroFood(['missi roti'], '1 roti', 150, fe: 1.8, ca: 25, mg: 50, zn: 1.1, k: 200, na: 200),
  MicroFood(['aloo paratha', 'aloo parantha'], '1 paratha', 300, fe: 1.8, ca: 25, mg: 45, zn: 0.9, k: 300, na: 400),
  MicroFood(['paneer paratha', 'paneer parantha'], '1 paratha', 320, fe: 1.8, ca: 150, mg: 50, zn: 1.6, k: 150, na: 350, b12: 0.3),
  MicroFood(['gobi paratha', 'mooli paratha', 'methi paratha'], '1 paratha', 270, fe: 1.8, ca: 40, mg: 45, zn: 0.9, k: 250, na: 400),
  MicroFood(['thepla', 'methi thepla'], '1 thepla', 120, fe: 1.3, ca: 30, mg: 30, zn: 0.6, k: 120, na: 150),
  MicroFood(['puri', 'poori'], '2 puris', 200, fe: 1.2, ca: 12, mg: 25, zn: 0.5, k: 70, na: 150),
  MicroFood(['bhatura', 'bhature'], '1 bhatura', 300, fe: 1.6, ca: 30, mg: 15, zn: 0.5, k: 80, na: 350),
  MicroFood(['chole bhature', 'chole bhatura'], '1 plate (2 bhature, chole)', 750, fe: 6.0, ca: 110, mg: 80, zn: 2.5, k: 600, na: 1300),
  MicroFood(['bajra roti', 'bajra', 'bajre ki roti', 'pearl millet'], '1 roti (40 g bajra)', 145, fe: 2.6, ca: 11, mg: 50, zn: 1.1, k: 120, na: 5),
  MicroFood(['jowar roti', 'jowar', 'jowar bhakri', 'bhakri', 'sorghum'], '1 roti (40 g jowar)', 135, fe: 1.6, ca: 11, mg: 55, zn: 0.8, k: 140, na: 5),
  MicroFood(['makki ki roti', 'makki roti', 'makki'], '1 roti', 150, fe: 1.0, ca: 5, mg: 50, zn: 0.8, k: 120, na: 5),
  MicroFood(['dalia', 'daliya', 'broken wheat'], '1 bowl cooked (200 g)', 180, fe: 1.8, ca: 20, mg: 60, zn: 1.2, k: 180, na: 200),
  MicroFood(['quinoa'], '1 bowl cooked (185 g)', 222, fe: 2.8, ca: 31, mg: 118, zn: 2.0, k: 318, na: 13),
  MicroFood(['cornflakes', 'corn flakes'], '30 g', 115, fe: 2.4, ca: 2, mg: 4, zn: 0.1, k: 30, na: 220),
  MicroFood(['muesli', 'granola'], '50 g', 190, fe: 2.0, ca: 30, mg: 50, zn: 1.1, k: 200, na: 60),
  MicroFood(['pasta', 'spaghetti', 'macaroni', 'white sauce pasta', 'red sauce pasta'], '1 plate (250 g)', 400, fe: 2.0, ca: 80, mg: 45, zn: 1.3, k: 300, na: 700),
  MicroFood(['noodles', 'hakka noodles', 'chowmein', 'chow mein', 'chicken noodles'], '1 plate (250 g)', 400, fe: 2.0, ca: 30, mg: 35, zn: 1.0, k: 200, na: 1200),
  MicroFood(['fried rice', 'veg fried rice', 'chicken fried rice', 'egg fried rice'], '1 plate (250 g)', 420, fe: 1.5, ca: 30, mg: 35, zn: 1.0, k: 200, na: 1100),
  MicroFood(['mutton biryani'], '1 plate (300 g)', 550, fe: 3.0, ca: 50, mg: 45, zn: 4.5, k: 400, na: 950, b12: 1.2),
  MicroFood(['egg biryani'], '1 plate (300 g)', 480, fe: 2.5, ca: 70, mg: 40, zn: 2.0, k: 350, na: 900, b12: 0.6, d: 1.0),
  MicroFood(['curd rice', 'dahi chawal', 'thayir sadam'], '1 bowl (250 g)', 280, fe: 0.5, ca: 180, mg: 30, zn: 1.0, k: 250, na: 400, b12: 0.5),
  MicroFood(['lemon rice', 'tamarind rice', 'puliyogare'], '1 plate (200 g)', 320, fe: 1.0, ca: 20, mg: 25, zn: 0.8, k: 120, na: 500),
  MicroFood(['bisi bele bath', 'bisibelebath'], '1 plate (250 g)', 330, fe: 2.0, ca: 50, mg: 50, zn: 1.2, k: 350, na: 700),
  MicroFood(['masala dosa'], '1 dosa', 350, fe: 1.5, ca: 30, mg: 40, zn: 0.8, k: 400, na: 500),
  MicroFood(['uttapam', 'uthappam'], '1 uttapam', 220, fe: 1.0, ca: 20, mg: 25, zn: 0.6, k: 150, na: 300),
  MicroFood(['medu vada', 'vada', 'wada'], '2 vadas', 280, fe: 1.5, ca: 30, mg: 40, zn: 1.0, k: 200, na: 350),
  MicroFood(['pongal', 'ven pongal'], '1 plate (200 g)', 300, fe: 1.2, ca: 30, mg: 40, zn: 1.0, k: 150, na: 450),
  MicroFood(['appam'], '2 appams', 240, fe: 0.6, ca: 15, mg: 20, zn: 0.5, k: 80, na: 150),
  MicroFood(['rasam'], '1 katori (150 ml)', 50, fe: 0.6, ca: 15, mg: 10, zn: 0.2, k: 150, na: 450),
  MicroFood(['kadhi', 'kadhi pakora'], '1 katori (150 g)', 150, fe: 0.6, ca: 100, mg: 20, zn: 0.5, k: 200, na: 450, b12: 0.2),
  MicroFood(['dal baati', 'dal bati'], '2 baati with dal', 600, fe: 4.0, ca: 60, mg: 90, zn: 2.5, k: 450, na: 700),
  MicroFood(['litti chokha', 'litti'], '2 litti with chokha', 450, fe: 3.5, ca: 50, mg: 80, zn: 2.0, k: 500, na: 600),
  MicroFood(['thali', 'veg thali'], '1 thali (rice, 2 roti, dal, sabzi, curd)', 750, fe: 4.0, ca: 250, mg: 120, zn: 3.0, k: 900, na: 1300, b12: 0.5),

  // ── Street food and outside meals (USDA FDC fast food; Indian street
  // food from IFCT ingredients with vendor salt) ─────────────────────────
  MicroFood(['sandwich', 'veg sandwich', 'grilled sandwich'], '1 sandwich', 280, fe: 1.8, ca: 100, mg: 30, zn: 0.8, k: 220, na: 550),
  MicroFood(['burger', 'veg burger', 'aloo tikki burger'], '1 burger', 400, fe: 2.5, ca: 100, mg: 30, zn: 1.5, k: 300, na: 800),
  MicroFood(['chicken burger'], '1 burger', 450, fe: 2.5, ca: 80, mg: 35, zn: 1.8, k: 350, na: 900, b12: 0.3),
  MicroFood(['french fries', 'fries'], '1 medium (117 g)', 365, fe: 0.9, ca: 20, mg: 40, zn: 0.6, k: 680, na: 250),
  MicroFood(['momos', 'veg momos', 'chicken momos'], '6 pieces', 250, fe: 1.5, ca: 30, mg: 20, zn: 0.8, k: 150, na: 650),
  MicroFood(['pav bhaji'], '1 plate (2 pav, bhaji)', 550, fe: 3.5, ca: 100, mg: 60, zn: 1.5, k: 700, na: 1300),
  MicroFood(['vada pav'], '1 vada pav', 300, fe: 1.8, ca: 40, mg: 30, zn: 0.7, k: 300, na: 600),
  MicroFood(['pav', 'ladi pav'], '1 pav (40 g)', 110, fe: 1.0, ca: 30, mg: 10, zn: 0.3, k: 45, na: 200),
  MicroFood(['misal pav', 'misal'], '1 plate', 500, fe: 4.0, ca: 80, mg: 70, zn: 2.0, k: 650, na: 1200),
  MicroFood(['pani puri', 'golgappa', 'gol gappa', 'puchka'], '6 pieces', 200, fe: 1.2, ca: 20, mg: 20, zn: 0.5, k: 200, na: 500),
  MicroFood(['bhel puri', 'bhel'], '1 plate (150 g)', 280, fe: 2.0, ca: 30, mg: 35, zn: 0.8, k: 280, na: 500),
  MicroFood(['sev puri', 'dahi puri', 'papdi chaat', 'chaat'], '1 plate', 300, fe: 1.8, ca: 60, mg: 30, zn: 0.7, k: 250, na: 600),
  MicroFood(['aloo tikki', 'tikki'], '2 tikkis', 250, fe: 1.0, ca: 20, mg: 30, zn: 0.4, k: 450, na: 450),
  MicroFood(['kachori'], '1 kachori', 190, fe: 1.0, ca: 20, mg: 20, zn: 0.5, k: 120, na: 300),
  MicroFood(['pakora', 'pakoda', 'pakode', 'bhajiya', 'onion pakora'], '6 pieces (100 g)', 300, fe: 2.0, ca: 40, mg: 40, zn: 1.0, k: 300, na: 400),
  MicroFood(['dhokla', 'khaman'], '4 pieces (100 g)', 160, fe: 1.5, ca: 30, mg: 40, zn: 0.8, k: 200, na: 500),
  MicroFood(['kathi roll', 'egg roll', 'chicken roll', 'frankie', 'wrap'], '1 roll', 400, fe: 2.5, ca: 60, mg: 30, zn: 1.5, k: 250, na: 800, b12: 0.4),
  MicroFood(['shawarma', 'chicken shawarma'], '1 roll', 450, fe: 3.0, ca: 80, mg: 40, zn: 2.5, k: 400, na: 1000, b12: 0.6),
  MicroFood(['soup', 'tomato soup', 'sweet corn soup', 'manchow soup', 'chicken soup'], '1 bowl (250 ml)', 100, fe: 1.0, ca: 20, mg: 20, zn: 0.3, k: 300, na: 800),
  MicroFood(['manchurian', 'gobi manchurian', 'veg manchurian'], '1 plate (200 g)', 350, fe: 1.5, ca: 40, mg: 25, zn: 0.6, k: 300, na: 1100),
  MicroFood(['chilli chicken', 'chicken 65', 'chicken lollipop'], '1 plate (200 g)', 450, fe: 2.0, ca: 30, mg: 40, zn: 2.0, k: 400, na: 1100, b12: 0.5),
  MicroFood(['chilli paneer'], '1 plate (200 g)', 420, fe: 1.0, ca: 380, mg: 30, zn: 2.5, k: 250, na: 1000, b12: 0.6),
  MicroFood(['nachos', 'tortilla chips'], '1 plate (60 g chips, cheese)', 350, fe: 1.0, ca: 150, mg: 50, zn: 1.2, k: 150, na: 550),
  MicroFood(['garlic bread'], '2 pieces', 200, fe: 1.2, ca: 40, mg: 12, zn: 0.4, k: 60, na: 350),

  // ── Dals, legumes and vegetables (IFCT 2017, cooked katori with salt) ──
  MicroFood(['lobia', 'black eyed peas', 'chawli'], '1 katori (150 g)', 150, fe: 2.0, ca: 35, mg: 60, zn: 1.3, k: 400, na: 350),
  MicroFood(['kala chana', 'black chana', 'black chickpeas', 'chana chaat', 'boiled chana'], '1 katori (150 g)', 170, fe: 3.0, ca: 60, mg: 55, zn: 1.4, k: 380, na: 350),
  MicroFood(['matar', 'peas', 'green peas'], '1 katori (150 g)', 120, fe: 1.8, ca: 35, mg: 40, zn: 1.2, k: 300, na: 300),
  MicroFood(['hummus'], '2 tbsp (30 g)', 80, fe: 0.7, ca: 12, mg: 21, zn: 0.5, k: 70, na: 130),
  MicroFood(['aloo gobi', 'gobi', 'gobhi', 'cauliflower'], '1 katori (150 g)', 130, fe: 0.9, ca: 35, mg: 25, zn: 0.4, k: 420, na: 350),
  MicroFood(['baingan bharta', 'baingan', 'brinjal', 'eggplant'], '1 katori (150 g)', 130, fe: 0.8, ca: 25, mg: 25, zn: 0.3, k: 350, na: 350),
  MicroFood(['lauki', 'ghiya', 'bottle gourd', 'tori', 'turai', 'tinda'], '1 katori (150 g)', 80, fe: 0.5, ca: 30, mg: 20, zn: 0.3, k: 250, na: 300),
  MicroFood(['karela', 'bitter gourd'], '1 katori (150 g)', 100, fe: 1.0, ca: 25, mg: 25, zn: 0.8, k: 350, na: 300),
  MicroFood(['cabbage', 'patta gobhi', 'band gobhi'], '1 katori (150 g)', 90, fe: 0.6, ca: 50, mg: 20, zn: 0.3, k: 250, na: 300),
  MicroFood(['beans', 'french beans'], '1 katori (150 g)', 90, fe: 1.0, ca: 50, mg: 30, zn: 0.3, k: 250, na: 300),
  MicroFood(['mushroom', 'mushroom masala'], '1 katori (150 g)', 120, fe: 0.8, ca: 10, mg: 15, zn: 0.8, k: 450, na: 400, d: 0.2),
  MicroFood(['carrot', 'gajar'], '1 medium (60 g)', 25, fe: 0.2, ca: 20, mg: 7, zn: 0.15, k: 190, na: 40),
  MicroFood(['broccoli'], '1 cup cooked (150 g)', 50, fe: 1.0, ca: 60, mg: 30, zn: 0.6, k: 440, na: 60),
  MicroFood(['tomato', 'tamatar'], '1 medium (120 g)', 22, fe: 0.3, ca: 12, mg: 13, zn: 0.2, k: 290, na: 6),
  MicroFood(['beetroot', 'chukandar'], '1 medium (100 g)', 43, fe: 0.8, ca: 16, mg: 23, zn: 0.35, k: 325, na: 78),
  MicroFood(['corn', 'sweet corn', 'bhutta', 'makai'], '1 cup (150 g)', 130, fe: 0.7, ca: 3, mg: 40, zn: 0.9, k: 330, na: 20),
  MicroFood(['avocado'], 'half (100 g)', 160, fe: 0.55, ca: 12, mg: 29, zn: 0.64, k: 485, na: 7),
  MicroFood(['coconut', 'nariyal'], '30 g fresh', 106, fe: 0.7, ca: 4, mg: 10, zn: 0.3, k: 107, na: 6),

  // ── Meat, fish and eggs, more (USDA FDC; Indian mackerel and sardine
  // B12 and D from USDA Atlantic values, rounded down) ────────────────────
  MicroFood(['kebab', 'kabab', 'seekh kebab', 'galouti'], '4 pieces (120 g)', 280, fe: 2.2, ca: 30, mg: 25, zn: 3.5, k: 300, na: 600, b12: 1.5),
  MicroFood(['fish fry', 'fried fish'], '2 pieces (150 g)', 300, fe: 1.2, ca: 60, mg: 45, zn: 0.9, k: 400, na: 450, b12: 2.5, d: 4.0),
  MicroFood(['mackerel', 'bangda', 'surmai', 'kingfish'], '150 g cooked', 280, fe: 1.8, ca: 25, mg: 50, zn: 1.0, k: 500, na: 120, b12: 6.0, d: 6.0),
  MicroFood(['sardine', 'sardines', 'mathi', 'tarli'], '100 g', 208, fe: 2.9, ca: 380, mg: 39, zn: 1.3, k: 397, na: 300, b12: 8.9, d: 4.8),
  MicroFood(['fried chicken'], '2 pieces (150 g)', 400, fe: 1.5, ca: 30, mg: 35, zn: 2.0, k: 350, na: 900, b12: 0.4),
  MicroFood(['nuggets', 'chicken nuggets'], '6 pieces (100 g)', 300, fe: 0.9, ca: 15, mg: 25, zn: 0.8, k: 300, na: 600, b12: 0.3),
  MicroFood(['sausage', 'salami', 'ham'], '2 pieces (50 g)', 150, fe: 0.5, ca: 10, mg: 10, zn: 1.0, k: 150, na: 550, b12: 0.5),

  // ── Drinks (USDA FDC; fortified plant milks and malt drinks per label
  // ranges, a scanned pack's own label wins) ──────────────────────────────
  MicroFood(['milkshake', 'shake', 'banana shake', 'cold coffee'], '1 glass (300 ml)', 300, fe: 0.4, ca: 300, mg: 40, zn: 1.0, k: 500, na: 150, b12: 1.0),
  MicroFood(['hot chocolate', 'bournvita', 'horlicks', 'boost'], '1 glass with milk (250 ml)', 220, fe: 2.5, ca: 380, mg: 45, zn: 1.5, k: 450, na: 180, b12: 1.5, d: 1.5),
  MicroFood(['soy milk', 'soya milk'], '1 glass (250 ml)', 100, fe: 1.0, ca: 250, mg: 40, zn: 0.6, k: 300, na: 100, b12: 0.6, d: 1.5),
  MicroFood(['almond milk'], '1 glass (250 ml)', 40, fe: 0.7, ca: 450, mg: 15, zn: 0.4, k: 170, na: 170, d: 2.4),
  MicroFood(['coconut water', 'nariyal pani'], '1 glass (250 ml)', 48, fe: 0.7, ca: 60, mg: 60, zn: 0.25, k: 600, na: 260),
  MicroFood(['juice', 'orange juice', 'fruit juice', 'mosambi juice'], '1 glass (250 ml)', 112, fe: 0.5, ca: 27, mg: 27, zn: 0.1, k: 450, na: 2),
  MicroFood(['nimbu pani', 'lemonade', 'shikanji'], '1 glass', 60, fe: 0.1, ca: 10, mg: 5, zn: 0.05, k: 50, na: 300),
  MicroFood(['cola', 'coke', 'pepsi', 'sprite', 'thums up', 'soft drink', 'cold drink'], '1 can (330 ml)', 140, fe: 0.1, ca: 7, mg: 0, zn: 0, k: 7, na: 15),
  MicroFood(['black coffee', 'espresso', 'americano'], '1 cup', 5, fe: 0.05, ca: 5, mg: 7, zn: 0.02, k: 116, na: 5),
  MicroFood(['green tea', 'black tea', 'lemon tea'], '1 cup', 2, fe: 0.05, ca: 0, mg: 2, zn: 0.02, k: 20, na: 2),
  MicroFood(['ors', 'electral'], '1 glass (200 ml)', 11, fe: 0, ca: 0, mg: 0, zn: 0, k: 156, na: 345),

  // ── Fruit, more (USDA FDC) ───────────────────────────────────────────────
  MicroFood(['watermelon', 'tarbooz'], '1 bowl (280 g)', 85, fe: 0.7, ca: 20, mg: 28, zn: 0.3, k: 315, na: 3),
  MicroFood(['grapes', 'angoor'], '1 cup (150 g)', 104, fe: 0.5, ca: 15, mg: 10, zn: 0.1, k: 290, na: 3),
  MicroFood(['pomegranate', 'anar'], '1 cup arils (175 g)', 145, fe: 0.5, ca: 17, mg: 21, zn: 0.6, k: 400, na: 5),
  MicroFood(['pineapple', 'ananas'], '1 cup (165 g)', 82, fe: 0.5, ca: 21, mg: 20, zn: 0.2, k: 180, na: 2),
  MicroFood(['chikoo', 'chiku', 'sapota'], '1 medium (100 g)', 83, fe: 0.8, ca: 21, mg: 12, zn: 0.1, k: 193, na: 12),
  MicroFood(['pear', 'nashpati'], '1 medium', 100, fe: 0.3, ca: 16, mg: 12, zn: 0.2, k: 206, na: 2),
  MicroFood(['kiwi'], '1 fruit (75 g)', 46, fe: 0.2, ca: 26, mg: 13, zn: 0.1, k: 230, na: 2),
  MicroFood(['strawberry', 'strawberries'], '1 cup (150 g)', 48, fe: 0.6, ca: 24, mg: 20, zn: 0.2, k: 230, na: 2),
  MicroFood(['muskmelon', 'kharbuja', 'cantaloupe'], '1 bowl (160 g)', 54, fe: 0.3, ca: 14, mg: 19, zn: 0.3, k: 427, na: 26),
  MicroFood(['litchi', 'lychee'], '10 pieces (100 g)', 66, fe: 0.3, ca: 5, mg: 10, zn: 0.07, k: 171, na: 1),
  MicroFood(['amla', 'gooseberry'], '2 amlas (50 g)', 22, fe: 0.2, ca: 13, mg: 5, zn: 0.06, k: 100, na: 1),
  MicroFood(['raisins', 'kishmish'], '20 g', 60, fe: 0.4, ca: 10, mg: 6, zn: 0.04, k: 150, na: 2),
  MicroFood(['anjeer', 'dried figs', 'fig'], '3 dried (25 g)', 62, fe: 0.5, ca: 40, mg: 17, zn: 0.14, k: 170, na: 2),

  // ── Nuts, seeds and salty snacks (USDA FDC nuts and seeds; Indian
  // packaged snacks per typical labels; IFCT papad and pickle) ────────────
  MicroFood(['cashews', 'cashew', 'kaju'], '20 g', 113, fe: 1.3, ca: 7, mg: 58, zn: 1.15, k: 130, na: 2),
  MicroFood(['pistachios', 'pista'], '20 g', 112, fe: 0.8, ca: 21, mg: 24, zn: 0.45, k: 200, na: 0),
  MicroFood(['chia seeds', 'chia'], '1 tbsp (12 g)', 58, fe: 0.9, ca: 76, mg: 40, zn: 0.55, k: 49, na: 2),
  MicroFood(['flax seeds', 'flaxseed', 'alsi'], '1 tbsp (10 g)', 53, fe: 0.6, ca: 25, mg: 39, zn: 0.43, k: 81, na: 3),
  MicroFood(['sunflower seeds'], '15 g', 87, fe: 0.8, ca: 12, mg: 49, zn: 0.75, k: 97, na: 1),
  MicroFood(['sesame', 'sesame seeds', 'til'], '1 tbsp (9 g)', 52, fe: 1.3, ca: 88, mg: 32, zn: 0.7, k: 42, na: 1),
  MicroFood(['dry fruits', 'dry fruit', 'mixed nuts', 'trail mix'], '30 g', 170, fe: 1.0, ca: 30, mg: 55, zn: 1.0, k: 200, na: 5),
  MicroFood(['chikki', 'peanut chikki'], '1 piece (25 g)', 120, fe: 0.5, ca: 15, mg: 30, zn: 0.6, k: 120, na: 10),
  MicroFood(['popcorn'], '1 bowl (25 g)', 120, fe: 0.8, ca: 3, mg: 35, zn: 0.8, k: 75, na: 200),
  MicroFood(['chips', 'potato chips', 'lays', 'crisps', 'wafers'], '1 small pack (30 g)', 160, fe: 0.5, ca: 7, mg: 20, zn: 0.3, k: 400, na: 180),
  MicroFood(['banana chips'], '30 g', 155, fe: 0.4, ca: 5, mg: 25, zn: 0.2, k: 160, na: 150),
  MicroFood(['kurkure', 'cheese balls', 'puffs'], '1 pack (30 g)', 160, fe: 0.5, ca: 10, mg: 10, zn: 0.2, k: 60, na: 300),
  MicroFood(['namkeen', 'mixture', 'chivda', 'chiwda', 'farsan'], '30 g', 160, fe: 1.0, ca: 20, mg: 30, zn: 0.5, k: 150, na: 250),
  MicroFood(['aloo bhujia', 'bikaneri bhujia', 'sev'], '30 g', 165, fe: 1.2, ca: 20, mg: 30, zn: 0.6, k: 180, na: 350),
  MicroFood(['mathri', 'khakhra'], '2 pieces (30 g)', 150, fe: 0.8, ca: 10, mg: 15, zn: 0.3, k: 40, na: 200),
  MicroFood(['papad', 'papadum', 'poppadom', 'appalam'], '1 papad, roasted (12 g)', 40, fe: 0.8, ca: 10, mg: 25, zn: 0.4, k: 120, na: 450),
  MicroFood(['pickle', 'achar', 'achaar', 'mango pickle', 'lime pickle', 'nimbu achar', 'aam ka achar'], '1 tbsp (15 g)', 40, fe: 0.3, ca: 10, mg: 5, zn: 0.05, k: 30, na: 450),
  MicroFood(['chutney', 'green chutney', 'coconut chutney'], '2 tbsp (30 g)', 40, fe: 0.4, ca: 15, mg: 10, zn: 0.2, k: 80, na: 150),
  MicroFood(['ketchup', 'tomato sauce'], '1 tbsp (17 g)', 17, fe: 0.05, ca: 3, mg: 2, zn: 0.03, k: 50, na: 150),
  MicroFood(['soy sauce'], '1 tbsp (16 g)', 9, fe: 0.3, ca: 3, mg: 7, zn: 0.07, k: 70, na: 900),
  MicroFood(['mayonnaise', 'mayo'], '1 tbsp (15 g)', 100, fe: 0, ca: 1, mg: 0, zn: 0, k: 3, na: 90),
  MicroFood(['biscuit', 'biscuits', 'cookie', 'cookies', 'marie', 'parle g'], '4 biscuits (30 g)', 140, fe: 1.0, ca: 15, mg: 8, zn: 0.2, k: 40, na: 120),
  MicroFood(['rusk', 'toast rusk'], '2 rusks (25 g)', 100, fe: 0.6, ca: 10, mg: 8, zn: 0.2, k: 40, na: 80),

  // ── Sweets (IFCT 2017 khoa, chhena, besan, jaggery; USDA cakes and ice
  // cream) ─────────────────────────────────────────────────────────────────
  MicroFood(['chocolate', 'milk chocolate', 'dairy milk'], '1 bar (25 g)', 135, fe: 0.6, ca: 47, mg: 16, zn: 0.6, k: 93, na: 20, b12: 0.2),
  MicroFood(['gulab jamun'], '2 pieces (80 g)', 300, fe: 0.7, ca: 80, mg: 12, zn: 0.5, k: 110, na: 60, b12: 0.2),
  MicroFood(['jalebi', 'imarti'], '2 pieces (50 g)', 200, fe: 0.4, ca: 5, mg: 5, zn: 0.2, k: 20, na: 10),
  MicroFood(['rasgulla', 'rasagulla', 'rasmalai', 'ras malai', 'sandesh', 'chhena'], '2 pieces (100 g)', 190, fe: 0.3, ca: 60, mg: 7, zn: 0.4, k: 40, na: 30, b12: 0.2),
  MicroFood(['ladoo', 'laddu', 'laddoo', 'besan ladoo', 'motichoor ladoo'], '1 ladoo (40 g)', 180, fe: 0.8, ca: 15, mg: 15, zn: 0.4, k: 70, na: 15),
  MicroFood(['barfi', 'burfi', 'kaju katli', 'peda', 'mithai'], '2 pieces (40 g)', 180, fe: 0.4, ca: 70, mg: 15, zn: 0.4, k: 80, na: 25, b12: 0.1),
  MicroFood(['kheer', 'payasam', 'seviyan', 'sevaiyan'], '1 katori (150 g)', 250, fe: 0.4, ca: 200, mg: 25, zn: 0.9, k: 280, na: 80, b12: 0.6),
  MicroFood(['halwa', 'gajar halwa', 'gajar ka halwa', 'sooji halwa', 'suji halwa'], '1 katori (150 g)', 400, fe: 1.0, ca: 150, mg: 30, zn: 0.6, k: 300, na: 80, b12: 0.4),
  MicroFood(['cake', 'pastry', 'brownie', 'muffin', 'cupcake'], '1 slice (80 g)', 300, fe: 1.2, ca: 40, mg: 15, zn: 0.4, k: 100, na: 250, b12: 0.1),
  MicroFood(['donut', 'doughnut'], '1 donut', 250, fe: 1.2, ca: 25, mg: 13, zn: 0.3, k: 60, na: 250),
  MicroFood(['ice cream', 'kulfi'], '1 scoop (66 g)', 140, fe: 0.1, ca: 85, mg: 10, zn: 0.4, k: 130, na: 55, b12: 0.25),
  MicroFood(['jaggery', 'gur'], '1 tbsp (15 g)', 57, fe: 0.7, ca: 12, mg: 10, zn: 0.1, k: 150, na: 5),
];

/// Looks foods up by name and stamps known micros onto logged items.
class MicronutrientLibrary {
  MicronutrientLibrary._();
  static final MicronutrientLibrary instance = MicronutrientLibrary._();

  late final List<(RegExp, String, MicroFood)> _patterns = [
    for (final f in microFoodLibrary)
      for (final a in f.aliases)
        (RegExp('(^| )${RegExp.escape(a)}(e?s)?(?= |\$)'), a, f),
  ];

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Library foods named in [name]. A shorter alias inside a longer match
  /// ("dal" inside "dal makhani") is dropped, so "palak paneer" is one food,
  /// while "paneer roti roll" is paneer and roti.
  List<MicroFood> matches(String name) {
    final n = _norm(name);
    if (n.isEmpty) return const [];
    final hits = <(int, int, MicroFood)>[];
    for (final (re, _, food) in _patterns) {
      final m = re.firstMatch(n);
      if (m == null) continue;
      final start = m.start + (m.group(1)?.length ?? 0);
      hits.add((start, m.end, food));
    }
    if (hits.isEmpty) return const [];
    // Longest spans first; drop any span inside one already kept.
    hits.sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
    final kept = <(int, int, MicroFood)>[];
    for (final h in hits) {
      final inside = kept.any((k) => h.$1 >= k.$1 && h.$2 <= k.$2);
      final overlaps = kept.any((k) => h.$1 < k.$2 && h.$2 > k.$1);
      if (inside || overlaps) continue;
      if (kept.any((k) => identical(k.$3, h.$3))) continue;
      kept.add(h);
    }
    kept.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final k in kept) k.$3];
  }

  /// Micros for a food named [name] worth [kcal], or null when the name isn't
  /// in the library (or carries no calories to scale by). Several foods in
  /// one name share the calories equally.
  Micronutrients? estimate(String name, double kcal) {
    if (!kcal.isFinite || kcal <= 0) return null;
    final foods = matches(name);
    if (foods.isEmpty) return null;
    final share = kcal / foods.length;
    var sum = Micronutrients.empty;
    for (final f in foods) {
      if (f.kcal <= 0) continue;
      final factor = (share / f.kcal).clamp(0.0, 25.0);
      sum = sum + f.micros.scaled(factor);
    }
    return sum.isEmpty ? null : sum;
  }

  /// Micros for a logged food: library values where the library knows the
  /// food, merged with what the item already carries.
  ///
  /// By default the library (cited) wins and [existing] (a model estimate)
  /// only fills nutrients the library lacks. With [preferExisting] (a pack
  /// label, or values the user already saved) it is the other way round.
  /// Unknown foods keep [existing] as-is, which may be null: not tracked.
  Micronutrients? enrich(String name, double kcal, Micronutrients? existing, {bool preferExisting = false}) {
    final lib = estimate(name, kcal);
    if (lib == null) return existing;
    if (existing == null || existing.isEmpty) return lib;
    return preferExisting ? existing.fillFrom(lib) : lib.fillFrom(existing);
  }
}
