class ParserLexicon {
  /// Protected phrases that contain spaces but must NOT be split,
  /// as they represent a single atomic food item.
  static const Set<String> protectedPhrases = {
    'chana dal',
    'mango shake',
    'whey protein',
    'peanut butter',
    'paneer bhurji',
    'grilled chicken',
    'tofu curry',
    'chicken sandwich',
    'egg white',
    'egg whites',
    'fruit juice',
    'veg fried rice',
    'butter chicken',
    'masala dosa',
    'dominos pizza',
    'pizza slice',
    'chicken biryani',
    'mutton biryani',
    'veg biryani',
    'brown rice',
    'white rice',
    'black coffee',
    'cold coffee',
    'ice cream',
    'french fries',
    'sweet potato',
    'burger king',
    'kfc chicken',
  };

  /// Implicit pairing mapping.
  /// Used to split space-separated foods without explicit conjunctions.
  /// For instance: 'dal chawal' -> 'dal' and 'chawal'.
  static const Map<String, List<String>> implicitPairs = {
    'dal chawal': ['dal', 'chawal'],
    'rajma chawal': ['rajma', 'chawal'],
    'chole chawal': ['chole', 'chawal'],
    'kadhi chawal': ['kadhi', 'chawal'],
    'roti sabzi': ['roti', 'sabzi'],
    'roti dal': ['roti', 'dal'],
    'rice dal': ['rice', 'dal'],
    'dal rice': ['dal', 'rice'],
    'paneer rice': ['paneer', 'rice'],
    'bread omelette': ['bread', 'omelette'],
    'bread butter': ['bread', 'butter'],
    'idli sambar': ['idli', 'sambar'],
    'wada sambar': ['wada', 'sambar'],
    'vada pav': ['vada pav'], // vada pav is generally one item conceptually, but if split, vada and pav. Let's keep it protected.
    'samosa pav': ['samosa', 'pav'],
    'puri sabzi': ['puri', 'sabzi'],
    'poori sabzi': ['poori', 'sabzi'],
  };

  static const Set<String> commonUnits = {
    'g', 'gram', 'grams',
    'kg', 'kilo', 'kilos',
    'ml', 'l', 'liter', 'liters', 'litre', 'litres',
    'scoop', 'scoops',
    'slice', 'slices',
    'piece', 'pieces', 'pc', 'pcs',
    'bowl', 'bowls',
    'ladle', 'ladles',
    'cup', 'cups',
    'tbsp', 'tablespoon', 'tablespoons',
    'tsp', 'teaspoon', 'teaspoons',
    'serving', 'servings',
    'plate', 'plates',
    'glass', 'glasses',
    'roti', 'rotis',
    'chapati', 'chapatis',
    'egg', 'eggs',
    'packet', 'packets',
  };

  /// Fractional representations.
  static const Map<String, double> fractions = {
    'half': 0.5,
    '1/2': 0.5,
    'quarter': 0.25,
    '1/4': 0.25,
    '3/4': 0.75,
    'one third': 0.33,
    '1/3': 0.33,
    'one and half': 1.5,
    '1.5': 1.5,
  };

  /// Explicit delimiters for splitting items.
  static const List<String> delimiters = [
    ' with ',
    ' and ',
    ' plus ',
    ' & ',
    ' + ',
    ', ',
    ',',
  ];
}
