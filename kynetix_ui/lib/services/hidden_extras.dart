/// Things people add to Indian food and forget to log: ghee on roti, the
/// tadka oil in dal, butter on paratha, sugar in coffee. Each is one standard
/// spoon with label-style numbers, offered only when the meal suggests it.
class HiddenExtra {
  final String id;
  final String label; // what gets logged, e.g. "1 tsp ghee"
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  const HiddenExtra(this.id, this.label, this.kcal, this.protein, this.carbs, this.fat);
}

abstract final class HiddenExtras {
  static const ghee = HiddenExtra('ghee', '1 tsp ghee', 45, 0, 0, 5);
  static const oil = HiddenExtra('oil', '1 tsp oil', 40, 0, 0, 4.5);
  static const butter = HiddenExtra('butter', '1 tsp butter', 36, 0, 0, 4);
  static const sugar = HiddenExtra('sugar', '2 tsp sugar', 32, 0, 8, 0);
  static const cream = HiddenExtra('cream', '1 tbsp malai', 50, 0.5, 0.5, 5);

  static final _rules = <(RegExp, List<HiddenExtra>)>[
    // Not chai / tea: the chai estimate (mock 'Chai (with milk & sugar)' and
    // the AI's Indian default) already includes ~2 tsp sugar, so suggesting
    // it again would double count.
    (RegExp(r'\b(coffee|lassi|nimbu pani|shikanji)\b'), [sugar]),
    (RegExp(r'\b(paratha|parantha|pav|bun|toast|bread|kulcha)\b'), [butter, ghee]),
    (RegExp(r'\b(roti|chapati|phulka|rotis|chapatis)\b'), [ghee, butter]),
    (RegExp(r'\b(dal|daal|sabzi|sabji|curry|bhaji|rajma|chole|chana|kadhi|sambar|poha|upma|khichdi|bhurji)\b'), [oil, ghee]),
    (RegExp(r'\b(rice|chawal|pulao|biryani)\b'), [ghee]),
    (RegExp(r'\b(dosa|uttapam|paneer)\b'), [oil, butter]),
    (RegExp(r'\b(kheer|halwa|dessert|shake)\b'), [sugar, cream]),
  ];

  /// Up to [max] extras that fit [mealText], most likely first. Extras the
  /// meal already names (it says "ghee") are left out.
  static List<HiddenExtra> suggest(String mealText, {int max = 3}) {
    final t = mealText.toLowerCase();
    final out = <HiddenExtra>[];
    for (final (re, extras) in _rules) {
      if (!re.hasMatch(t)) continue;
      for (final e in extras) {
        if (out.contains(e) || t.contains(e.id) || (e.id == 'cream' && t.contains('malai'))) continue;
        out.add(e);
      }
    }
    return out.take(max).toList();
  }
}
