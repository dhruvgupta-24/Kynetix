// ─── Indian curry table ───────────────────────────────────────────────────────
//
// Cooked dal, sabzi, legume, paneer and meat gravies as served at home or in
// a mess (2 to 5% oil or ghee), per 100 g. Values worked from IFCT 2017
// raw-ingredient data and USDA FoodData Central cooked legumes, applied to
// typical recipes. kcal ~= 4P + 4C + 9F; fibre is listed on its own.
//
// Each dish belongs to a [CurryFamily], which decides how much of it a person
// eats to finish one roti or one ladle of rice (see [CurryFamily.gramsPer]).

import '../models/user_profile.dart' show PortionAnchor;

/// How a curry is eaten with roti or rice. Rice soaks up more of a liquid dal
/// than a roti does and less of a dry sabzi, so each family has its own grams
/// per roti and per rice ladle (about 100 g cooked rice).
enum CurryFamily {
  /// Dal, kadhi, sambar.
  liquid,

  /// Rasam: thin, poured over rice.
  rasam,

  /// Chole, rajma, lobia, kala chana.
  legume,

  /// Paneer, egg, chicken, fish and kofta gravies, soya curry.
  rich,

  /// Wet vegetable curries: aloo matar, mix veg, lauki, tinda, saag.
  vegGravy,

  /// Dry sabzi: aloo gobi, aloo jeera, bhindi, baingan, cabbage, beans.
  dry,

  /// Raita.
  raita;

  /// Grams eaten to finish one roti ([perRoti] true) or one rice ladle,
  /// for an eater [anchor]. Carb first eaters use the curry as a condiment;
  /// curry first eaters finish a fuller katori.
  double gramsPer(PortionAnchor anchor, {required bool perRoti}) {
    final (carb, balanced, curry) = switch ((this, perRoti)) {
      (CurryFamily.liquid, true)    => (35.0, 50.0, 75.0),
      (CurryFamily.liquid, false)   => (60.0, 85.0, 120.0),
      (CurryFamily.rasam, true)     => (35.0, 50.0, 75.0),
      (CurryFamily.rasam, false)    => (80.0, 110.0, 150.0),
      (CurryFamily.legume, true)    => (35.0, 50.0, 70.0),
      (CurryFamily.legume, false)   => (50.0, 70.0, 100.0),
      (CurryFamily.rich, true)      => (30.0, 45.0, 65.0),
      (CurryFamily.rich, false)     => (40.0, 60.0, 85.0),
      (CurryFamily.vegGravy, true)  => (35.0, 50.0, 70.0),
      (CurryFamily.vegGravy, false) => (45.0, 60.0, 85.0),
      (CurryFamily.dry, true)       => (30.0, 45.0, 65.0),
      (CurryFamily.dry, false)      => (25.0, 35.0, 50.0),
      (CurryFamily.raita, true)     => (20.0, 30.0, 45.0),
      (CurryFamily.raita, false)    => (50.0, 75.0, 100.0),
    };
    return switch (anchor) {
      PortionAnchor.carbAnchored  => carb,
      PortionAnchor.balanced      => balanced,
      PortionAnchor.curryAnchored => curry,
    };
  }
}

/// One cooked dish, per 100 g.
class CurryDish {
  const CurryDish(this.name, this.family, this.kcal, this.protein, this.carbs, this.fat, this.fiber,
      {required this.aliases});

  final String name;
  final CurryFamily family;
  final double kcal, protein, carbs, fat, fiber;

  /// Lower case phrases that name this dish. Matched as whole words.
  final List<String> aliases;
}

abstract final class IndianCurryTable {
  /// Most specific dishes first: "dal makhani" before "dal", "kala chana"
  /// and "chana dal" before "chana", "paneer butter masala" before
  /// "butter chicken".
  static const List<CurryDish> dishes = [
    // ── Dals
    CurryDish('dal makhani', CurryFamily.liquid, 140, 5.5, 13, 7.5, 4.0,
        aliases: ['dal makhani', 'daal makhani', 'makhani dal', 'maa ki dal', 'kali dal', 'black dal']),
    CurryDish('dal tadka', CurryFamily.liquid, 105, 4.5, 11, 4.5, 2.5,
        aliases: ['dal tadka', 'daal tadka', 'tadka dal', 'dal fry', 'daal fry', 'urad dal', 'yellow dal tadka']),
    CurryDish('chana dal', CurryFamily.liquid, 105, 4.6, 11, 4.2, 3.0,
        aliases: ['chana dal', 'chane ki dal', 'chana daal']),
    CurryDish('moong dal', CurryFamily.liquid, 90, 4.8, 10, 2.8, 1.8,
        aliases: ['moong dal', 'mung dal', 'moong daal', 'moong']),
    CurryDish('masoor dal', CurryFamily.liquid, 90, 5.0, 10, 2.8, 2.2,
        aliases: ['masoor dal', 'masoor daal', 'masoor', 'red lentil', 'red lentils']),
    CurryDish('toor dal', CurryFamily.liquid, 85, 4.0, 10, 2.8, 2.5,
        aliases: ['toor dal', 'arhar dal', 'tuvar dal', 'toor daal', 'arhar daal', 'toor', 'arhar']),
    CurryDish('kadhi pakoda', CurryFamily.liquid, 115, 3.5, 9, 7.0, 1.0,
        aliases: ['kadhi pakoda', 'kadhi pakora', 'kadi pakoda', 'kadi pakora', 'pakoda kadhi', 'pakora kadhi']),
    CurryDish('kadhi', CurryFamily.liquid, 65, 2.5, 5.5, 3.5, 0.5,
        aliases: ['kadhi', 'kadi']),
    CurryDish('sambar', CurryFamily.liquid, 70, 3.0, 8, 2.8, 2.5,
        aliases: ['sambar', 'sambhar']),
    CurryDish('rasam', CurryFamily.rasam, 30, 1.0, 4, 1.1, 0.6,
        aliases: ['rasam']),
    // Plain mess / home dal: between a thin mess dal and a home moong dal.
    CurryDish('dal', CurryFamily.liquid, 75, 3.8, 9, 2.2, 1.8,
        aliases: ['dal', 'daal', 'dhal', 'lentil', 'lentils', 'plain dal', 'mess dal']),

    // ── Legumes
    CurryDish('kala chana', CurryFamily.legume, 135, 6.0, 14, 5.0, 6.0,
        aliases: ['kala chana', 'kale chane', 'kala chane', 'black chana', 'black chickpea', 'black chickpeas']),
    CurryDish('chole', CurryFamily.legume, 150, 6.0, 15, 6.0, 5.0,
        aliases: ['chole', 'chhole', 'chole masala', 'chana masala', 'white chana', 'white chane', 'safed chana',
                  'safed chane', 'kabuli chana', 'chana', 'chane', 'channa', 'channe', 'chickpea curry',
                  'chickpea', 'chickpeas']),
    CurryDish('rajma', CurryFamily.legume, 120, 5.5, 13, 4.5, 4.5,
        aliases: ['rajma', 'rajmah', 'rajma masala', 'kidney bean', 'kidney beans']),
    CurryDish('lobia', CurryFamily.legume, 115, 5.0, 12, 4.5, 4.5,
        aliases: ['lobia', 'lobhia', 'chawli', 'black eyed peas', 'black eyed beans']),

    // ── Paneer
    CurryDish('paneer butter masala', CurryFamily.rich, 190, 7.0, 8, 14, 1.5,
        aliases: ['paneer butter masala', 'butter paneer', 'paneer makhani', 'paneer makhanwala']),
    CurryDish('shahi paneer', CurryFamily.rich, 215, 7.5, 9, 16.5, 1.0,
        aliases: ['shahi paneer', 'paneer korma']),
    CurryDish('palak paneer', CurryFamily.rich, 140, 6.5, 5.5, 10.5, 2.0,
        aliases: ['palak paneer', 'saag paneer']),
    CurryDish('matar paneer', CurryFamily.rich, 155, 6.5, 9, 10.5, 2.5,
        aliases: ['matar paneer', 'mutter paneer', 'mattar paneer', 'paneer matar']),
    CurryDish('paneer bhurji', CurryFamily.rich, 220, 12.5, 5, 16.5, 1.0,
        aliases: ['paneer bhurji']),
    CurryDish('kadai paneer', CurryFamily.rich, 175, 7.5, 7, 13, 2.0,
        aliases: ['kadai paneer', 'kadhai paneer', 'karahi paneer', 'paneer masala', 'paneer curry',
                  'paneer sabzi', 'paneer sabji', 'paneer gravy', 'chilli paneer gravy']),

    // ── Egg, meat, soya
    CurryDish('butter chicken', CurryFamily.rich, 185, 13, 6, 12, 0.8,
        aliases: ['butter chicken', 'murgh makhani', 'chicken makhani']),
    CurryDish('chicken curry', CurryFamily.rich, 145, 13, 4, 8.5, 0.8,
        aliases: ['chicken curry', 'chicken gravy', 'chicken masala', 'kadai chicken', 'chicken korma']),
    CurryDish('egg curry', CurryFamily.rich, 150, 7.5, 5, 11, 1.0,
        aliases: ['egg curry', 'anda curry', 'egg masala', 'anda masala']),
    CurryDish('fish curry', CurryFamily.rich, 120, 12, 3.5, 6.5, 0.6,
        aliases: ['fish curry', 'machli curry', 'fish masala']),
    CurryDish('soya curry', CurryFamily.rich, 135, 12, 10, 5.0, 3.5,
        aliases: ['soya chunk curry', 'soya chunks curry', 'soya curry', 'soya chunk', 'soya chunks', 'soya sabzi',
                  'soya sabji', 'nutrela', 'kadai soya', 'soyabean curry']),
    CurryDish('malai kofta', CurryFamily.rich, 230, 5.0, 14, 17, 1.5,
        aliases: ['malai kofta', 'kofta curry', 'lauki kofta', 'kofta']),

    // ── Wet vegetable curries
    CurryDish('aloo matar', CurryFamily.vegGravy, 100, 2.8, 13, 4.2, 3.0,
        aliases: ['aloo matar', 'aloo mutter', 'matar aloo', 'aloo sabzi', 'aloo sabji', 'aloo curry', 'aloo tamatar',
                  'dum aloo']),
    CurryDish('mushroom matar', CurryFamily.vegGravy, 95, 3.5, 8, 5.5, 2.5,
        aliases: ['mushroom matar', 'matar mushroom', 'mushroom masala', 'mushroom curry', 'mushroom sabzi']),
    CurryDish('saag', CurryFamily.vegGravy, 90, 3.0, 6, 6.0, 3.0,
        aliases: ['sarson ka saag', 'saag', 'palak sabzi', 'palak']),
    CurryDish('lauki', CurryFamily.vegGravy, 55, 1.0, 5, 3.5, 1.5,
        aliases: ['lauki', 'ghiya', 'bottle gourd', 'dudhi', 'lauki sabzi']),
    CurryDish('tinda', CurryFamily.vegGravy, 55, 1.1, 4.5, 3.6, 1.5,
        aliases: ['tinda', 'tinde']),
    CurryDish('mix veg', CurryFamily.vegGravy, 95, 2.5, 9, 5.5, 3.0,
        aliases: ['mix veg', 'mixed veg', 'mix vegetable', 'mixed vegetable', 'mixed vegetables', 'veg curry',
                  'sabzi', 'sabji', 'subzi', 'vegetable curry']),

    // ── Dry sabzi
    CurryDish('aloo gobi', CurryFamily.dry, 95, 2.2, 10, 5.2, 2.5,
        aliases: ['aloo gobi', 'aloo gobhi', 'gobi aloo', 'gobhi aloo', 'gobi', 'gobhi', 'cauliflower']),
    CurryDish('aloo jeera', CurryFamily.dry, 125, 2.0, 16, 6.0, 2.0,
        aliases: ['aloo jeera', 'jeera aloo', 'aloo fry', 'aloo methi', 'methi aloo', 'aloo bhujia sabzi']),
    CurryDish('bhindi', CurryFamily.dry, 110, 2.2, 8, 7.5, 3.5,
        aliases: ['bhindi masala', 'bhindi', 'bhindi fry', 'okra']),
    CurryDish('baingan bharta', CurryFamily.dry, 90, 1.8, 7, 6.0, 3.0,
        aliases: ['baingan bharta', 'baingan', 'bharta', 'brinjal', 'eggplant']),
    CurryDish('patta gobi', CurryFamily.dry, 70, 1.7, 5.5, 4.6, 2.5,
        aliases: ['patta gobi', 'patta gobhi', 'band gobi', 'band gobhi', 'cabbage']),
    CurryDish('beans sabzi', CurryFamily.dry, 75, 2.0, 6, 4.8, 3.0,
        aliases: ['beans sabzi', 'french beans', 'green beans', 'beans']),

    // ── Raita
    CurryDish('boondi raita', CurryFamily.raita, 95, 3.0, 8, 5.5, 0.5,
        aliases: ['boondi raita']),
    CurryDish('raita', CurryFamily.raita, 50, 2.5, 4, 2.7, 0.4,
        aliases: ['raita', 'cucumber raita', 'kheera raita']),
  ];

  /// Words that make a name something other than a curry ("roasted chana",
  /// "chana chaat", "besan"), or a combo plate that already carries its own
  /// carb ("rajma chawal", "chole bhature").
  static final RegExp _notACurry = RegExp(
    r'\b(roasted|bhuna|sprouts?|sprouted|chaat|sattu|flour|atta|besan|salad|soup|biryani|pulao|'
    r'khichdi|khichri|rice|chawal|roti|chapati|naan|paratha|kulcha|bhature|bhatura|puri|poori|pav|'
    r'bread|wrap|roll|sandwich|burger|pizza|pasta|noodles?|dosa|idli|vada|tikki|samosa|pakode|'
    r'momos?|bar|powder|chips|namkeen|halwa|ladoo|laddu)\b',
  );

  /// Generic words that stand for a dish only on their own: "sabzi" is a mix
  /// veg, but "arbi sabzi" is a vegetable this table doesn't know (Kyno
  /// estimates it, sized by the same roti and rice rules).
  static const Set<String> _onlyAlone = {
    'sabzi', 'sabji', 'subzi', 'veg curry', 'vegetable curry',
  };

  static final RegExp _fillerWords = RegExp(r'\b(mess|plain|simple|ghar ki|home|homemade|hostel|some|thoda|thodi)\b');

  static final Map<String, RegExp> _aliasRe = {
    for (final d in dishes)
      for (final a in d.aliases) a: RegExp('(^|[^a-z])${RegExp.escape(a)}(\$|[^a-z])'),
  };

  /// The dish [name] refers to, or null when it is not a known curry. The
  /// longest matching alias wins, so "bhindi sabzi" is bhindi (not the
  /// generic sabzi) and "aloo matar paneer" is matar paneer; ties go to the
  /// dish listed first.
  static CurryDish? match(String name) {
    final lc = name.toLowerCase().trim();
    if (lc.isEmpty || _notACurry.hasMatch(lc)) return null;
    CurryDish? best;
    var bestLen = 0;
    for (final d in dishes) {
      for (final a in d.aliases) {
        if (_onlyAlone.contains(a) && lc.replaceAll(_fillerWords, ' ').trim().replaceAll(RegExp(r'\s+'), ' ') != a) {
          continue;
        }
        if (a.length > bestLen && _aliasRe[a]!.hasMatch(lc)) {
          best = d;
          bestLen = a.length;
        }
      }
    }
    return best;
  }
}
