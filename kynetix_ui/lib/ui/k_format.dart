// Small display helpers so numbers and counts read the same everywhere.

/// "1 set", "3 sets", "1 exercise". Pass [plural] for irregular words.
String plural(num count, String singular, {String? plural}) {
  final c = count is double && count == count.roundToDouble() ? count.toInt() : count;
  final word = c == 1 ? singular : (plural ?? '${singular}s');
  return '$c $word';
}

/// Whole-number display (rounds, never truncates): 201.6 → "202".
String whole(num value) => value.round().toString();

/// Grams/ml with at most one decimal and no trailing ".0": 40.0 → "40", 12.5 → "12.5".
String amount(num value) {
  final r = (value * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}

/// Whole number with thousands separators (rounds): 2181.4 → "2,181".
String thousands(num value) {
  final n = value.round();
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// Kynetix never shows an em dash: AI replies and imported text get commas
/// instead. "Dal, rice — 420 kcal" → "Dal, rice, 420 kcal".
String noEmDash(String s) {
  final dash = String.fromCharCode(0x2014);
  if (!s.contains(dash)) return s;
  return s
      .replaceAll(RegExp(r'\s*' + dash + r'\s*'), ', ')
      .replaceAll(', ,', ',');
}
