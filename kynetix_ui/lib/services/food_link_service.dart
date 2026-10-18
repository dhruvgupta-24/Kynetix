import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/barcode_product.dart';
import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import 'item_parser.dart';
import 'meal_memory.dart';
import 'nutrition_hydration_guard.dart';
import 'quick_add_service.dart';
import 'unit_normalizer.dart';
import 'user_nutrition_memory.dart';

// ─── Food links ───────────────────────────────────────────────────────────────
//
// A link says "this scanned pack and the food I used to type by another name
// are the same thing". Example: the scanner calls a pack
// "Phab mini chocolate brownie bar" while the person had been logging it as
// "phab 11g chocolate brownie protein bar".
//
// - The scanned product is the source of truth: its label numbers are what
//   either name logs from now on.
// - The old name becomes an alias. Typing it (the describe-it composer, saved
//   meal search, Quick Add, the meal editor's pipeline) resolves to the
//   product.
// - The old memory entries are never deleted or rewritten. They are only
//   hidden from lists and suggestions while the link exists, so unlinking
//   brings everything back exactly as it was.
// - Past meals in day logs are never touched.
//
// Storage: per user, SharedPreferences `food_links_v1_<userId>`. The
// `_<userId>` suffix is what account deletion's per-user key sweep matches.
// Local only, like the barcode product store it builds on
// (BarcodeUserProducts) and the recurring meal memory it hides entries from
// (MealMemory): neither of those is uploaded, so a link travelling to another
// device would point at a product that device does not have.

/// One scanned product and the older names that mean the same food.
class FoodLink {
  final String barcode;

  /// Snapshot of the product at link time (refreshed on later scans), so the
  /// link resolves even when the product came from the device-wide Open Food
  /// Facts cache, which is cleared at logout.
  final BarcodeProduct product;

  /// Older names as the person wrote them, e.g. "phab 11g chocolate brownie
  /// protein bar".
  final List<String> aliases;
  final DateTime linkedAt;

  const FoodLink({
    required this.barcode,
    required this.product,
    required this.aliases,
    required this.linkedAt,
  });

  String get name => product.name;

  /// What "one" of this food means when a name is typed without an amount:
  /// the pack's own default portion (a 35 g bar logs 35 g).
  double get portionGrams => product.defaultAmount.grams;

  Set<String> get aliasKeys => {for (final a in aliases) FoodLinkMatcher.key(a)};

  FoodLink copyWith({BarcodeProduct? product, List<String>? aliases}) => FoodLink(
        barcode: barcode,
        product: product ?? this.product,
        aliases: aliases ?? this.aliases,
        linkedAt: linkedAt,
      );

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'product': product.toJson(),
        'aliases': aliases,
        'linkedAt': linkedAt.toIso8601String(),
      };

  static FoodLink? fromJson(Map<String, dynamic> j) {
    try {
      final product = BarcodeProduct.fromJson(
        j['product'] as Map<String, dynamic>? ?? const {},
      );
      final barcode = (j['barcode'] as String?) ?? product.barcode;
      final aliases = [
        for (final a in (j['aliases'] as List? ?? const []))
          if (a is String && a.trim().isNotEmpty) a,
      ];
      if (barcode.isEmpty || product.name.isEmpty || aliases.isEmpty) return null;
      return FoodLink(
        barcode: barcode,
        product: product,
        aliases: aliases,
        linkedAt: DateTime.tryParse(j['linkedAt'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A personal food that looks like the same thing as a scanned product.
class FoodLinkCandidate {
  /// Display name, as the person wrote it (leading amount removed).
  final String name;
  final String key;

  /// 0..1; only strong matches (>= [FoodLinkMatcher.strongScore]) are offered.
  final double score;
  final int timesUsed;

  const FoodLinkCandidate({
    required this.name,
    required this.key,
    required this.score,
    this.timesUsed = 1,
  });
}

/// Name matching between a scanned product and a person's own foods.
///
/// Conservative by design: a link is only ever offered, never made
/// automatically, and only when the brand matches and the remaining product
/// words (sizes and generic words like "mini", "protein", "bar" removed)
/// mostly overlap.
class FoodLinkMatcher {
  FoodLinkMatcher._();

  static const strongScore = 0.75;

  static const _filler = {
    'a', 'an', 'the', 'of', 'and', 'with', 'some',
    'fresh', 'boiled', 'cooked', 'raw', 'plain', 'simple',
    'homemade', 'home', 'made',
  };

  /// Words that describe the format or size, not which food it is.
  static const _generic = {
    ..._filler,
    'mini', 'protein', 'bar', 'bars', 'pack', 'packs', 'packet', 'pouch',
    'box', 'high', 'new', 'pro', 'snack', 'flavour', 'flavor', 'flavoured',
    'flavored', 'pcs', 'pc', 'piece', 'pieces', 'x', 'size', 'small', 'big',
    'large', 'serving', 'single', 'g', 'gm', 'gms', 'gram', 'grams', 'ml',
    'kg', 'l', 'ltr', 'mg', 'kcal', 'cal', 'pure', 'original', 'classic',
  };

  static final _leadingAmount = RegExp(
    r'^\s*\d+(?:[.,]\d+)?\s*(?:x|g|gm|gms|grams?|ml|kg|l|pcs?|pieces?|servings?|packs?|packets?|bars?|nos?)?\b\s*',
    caseSensitive: false,
  );
  static final _size = RegExp(
    r'\b\d+(?:[.,]\d+)?\s*(?:g|gm|gms|grams?|ml|kg|l|ltr|mg|kcal|cal)\b',
    caseSensitive: false,
  );
  static final _number = RegExp(r'\b\d+(?:[.,]\d+)?\b');
  static final _nonWord = RegExp(r'[^a-z0-9]+');

  /// [raw] without a leading amount ("35 g ", "2 ", "1x "), trimmed, in the
  /// person's own casing.
  static String displayName(String raw) {
    var s = raw.trim();
    // Strip at most two amount prefixes ("2 x 35 g ...").
    for (var i = 0; i < 2; i++) {
      final m = _leadingAmount.firstMatch(s);
      if (m == null || m.end == 0 || m.end >= s.length) break;
      s = s.substring(m.end).trim();
    }
    return s;
  }

  /// Identity key used for aliases and lookups: lower case, punctuation and
  /// filler words removed, leading amount removed. Sizes inside the name
  /// ("11g") are kept, so the alias matches the name exactly as it was typed.
  static String key(String raw) {
    final words = displayName(raw)
        .toLowerCase()
        .split(_nonWord)
        .where((t) => t.isNotEmpty && !_filler.contains(t));
    return words.join(' ');
  }

  /// The words that say which food it is: sizes, numbers, filler and generic
  /// format words removed.
  static List<String> coreTokens(String raw) {
    final s = raw
        .toLowerCase()
        .replaceAll(_size, ' ')
        .replaceAll(_number, ' ');
    return s
        .split(_nonWord)
        .where((t) => t.length > 1 && !_generic.contains(t))
        .toList();
  }

  /// The product's brand words: from the brand field when there is one,
  /// otherwise the first word of its name.
  static Set<String> brandTokens(BarcodeProduct p) {
    final brand = (p.brand ?? '').split(',').first;
    final fromBrand = coreTokens(brand);
    if (fromBrand.isNotEmpty) return fromBrand.toSet();
    final fromName = coreTokens(p.name);
    return fromName.isEmpty ? const {} : {fromName.first};
  }

  static bool _same(String a, String b) {
    if (a == b) return true;
    // "choco" / "chocolate", "brownies" / "brownie".
    if (a.length >= 4 && b.length >= 4 && (a.startsWith(b) || b.startsWith(a))) return true;
    return false;
  }

  /// How likely [candidate] names the same food as [product]: 0 when it is
  /// not a plausible match, otherwise 0.75..1.
  static double score(BarcodeProduct product, String candidate) {
    final brand = brandTokens(product);
    if (brand.isEmpty) return 0;
    final cand = coreTokens(candidate);
    if (cand.isEmpty) return 0;
    // Brand must be present in the candidate.
    for (final b in brand) {
      if (!cand.any((t) => _same(t, b))) return 0;
    }
    final pCore = coreTokens(product.name)
        .where((t) => !brand.any((b) => _same(t, b)))
        .toSet();
    final cCore = cand.where((t) => !brand.any((b) => _same(t, b))).toSet();
    // A brand alone ("Phab bar") says nothing about which product it is.
    if (pCore.isEmpty || cCore.isEmpty) return 0;

    var inter = 0;
    for (final t in pCore) {
      if (cCore.any((c) => _same(c, t))) inter++;
    }
    if (inter == 0) return 0;
    final union = pCore.length + cCore.length - inter;
    final jaccard = inter / union;
    final containment = inter / (pCore.length < cCore.length ? pCore.length : cCore.length);
    if (containment < 0.66 || jaccard < 0.5) return 0;
    return 0.5 + 0.5 * jaccard;
  }
}

class FoodLinkService {
  FoodLinkService._();
  static final FoodLinkService instance = FoodLinkService._();

  static const keyPrefix = 'food_links_v1';
  static String keyFor(String userId) => '${keyPrefix}_$userId';

  final Map<String, FoodLink> _links = {};
  final Set<String> _declined = {};
  String? _ownerUserId;

  String? get _currentUserId => NutritionHydrationGuard.instance.currentUserId;

  /// Reads are served only for the loaded owner, and only once the session
  /// is hydrated for them (same fail-closed rule as the other memories).
  bool get _readable {
    if (!NutritionHydrationGuard.instance.isReadyForCurrentUser) return false;
    final current = _currentUserId;
    return current != null && _ownerUserId == current;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initForUser(String userId, {SharedPreferences? prefsOverride}) async {
    _links.clear();
    _declined.clear();
    _ownerUserId = userId;
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      if (_ownerUserId != userId) return;
      final raw = prefs.getString(keyFor(userId));
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return;
      final links = j['links'];
      if (links is Map<String, dynamic>) {
        for (final v in links.values) {
          if (v is! Map<String, dynamic>) continue;
          final link = FoodLink.fromJson(v);
          if (link != null) _links[link.barcode] = link;
        }
      }
      for (final d in (j['declined'] as List? ?? const [])) {
        if (d is String) _declined.add(d);
      }
    } catch (e) {
      debugPrint('[FoodLinks] load failed: $e');
    }
  }

  void clearMemory() {
    _links.clear();
    _declined.clear();
    _ownerUserId = null;
  }

  Future<void> _ensureOwner() async {
    final current = _currentUserId;
    if (current == null || current.isEmpty) return;
    if (_ownerUserId != current) await initForUser(current);
  }

  Future<void> _persist() async {
    final owner = _ownerUserId;
    if (owner == null || owner.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyFor(owner),
      jsonEncode({
        'links': {for (final l in _links.values) l.barcode: l.toJson()},
        'declined': _declined.toList(),
      }),
    );
  }

  // ── Reads ──────────────────────────────────────────────────────────────────

  List<FoodLink> get links {
    if (!_readable) return const [];
    return _links.values.toList()..sort((a, b) => b.linkedAt.compareTo(a.linkedAt));
  }

  FoodLink? linkForBarcode(String barcode) => _readable ? _links[barcode.trim()] : null;

  /// The link that [name] belongs to, as an alias or as the product's own
  /// name. Leading amounts are ignored ("2 phab ..." finds the same link).
  FoodLink? linkFor(String name) {
    if (!_readable || _links.isEmpty) return null;
    final k = FoodLinkMatcher.key(name);
    if (k.isEmpty) return null;
    for (final l in _links.values) {
      if (l.aliasKeys.contains(k) || FoodLinkMatcher.key(l.name) == k) return l;
    }
    return null;
  }

  /// Whether [name] is an older name that now points at a scanned product.
  /// Such entries are hidden from lists and suggestions (never deleted).
  bool isHidden(String name) {
    if (!_readable || _links.isEmpty) return false;
    final k = FoodLinkMatcher.key(name);
    if (k.isEmpty) return false;
    for (final l in _links.values) {
      if (l.aliasKeys.contains(k)) return true;
    }
    return false;
  }

  /// Grams of the linked product for [quantity] [unit]: weights and volumes
  /// are taken as is, counts ("2", "1 serving", "1 bar") mean that many of
  /// the pack's default portion.
  static double gramsFor(FoodLink link, double quantity, String unit) {
    final q = quantity > 0 && quantity.isFinite ? quantity : 1.0;
    final u = UnitNormalizer.normalizeUnit(unit);
    if (u == 'g' || u == 'ml') return UnitNormalizer.normalizeQuantity(q, unit);
    return q * link.portionGrams;
  }

  /// One pipeline item for [name] when it belongs to a link, else null.
  NutritionItem? resolveItem(String name, double quantity, String unit) {
    final link = linkFor(name);
    if (link == null) return null;
    final grams = gramsFor(link, quantity, unit);
    if (grams <= 0) return null;
    final items = link.product.resultForAmount(grams).items;
    return items.isEmpty ? null : items.first.withScalar(1.0);
  }

  /// The full result for a typed meal that is just one linked food (with or
  /// without an amount), else null. Same numbers the scanner logs.
  NutritionResult? resolveMeal(String text) {
    if (!_readable || _links.isEmpty) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parsed = ItemParser.parse(trimmed);
    if (parsed.length == 1) {
      final p = parsed.first;
      final link = linkFor(p.normalizedName);
      if (link != null) {
        final grams = gramsFor(link, p.quantity, p.unit);
        if (grams > 0) return link.product.resultForAmount(grams);
      }
    }
    // The parser split or reshaped the name; the whole text still names a
    // linked food: log one default portion.
    final whole = linkFor(trimmed);
    if (whole == null) return null;
    return whole.product.resultForAmount(whole.portionGrams);
  }

  bool isDeclined(String barcode, String name) =>
      _declined.contains(_pair(barcode, name));

  static String _pair(String barcode, String name) =>
      '${barcode.trim()}|${FoodLinkMatcher.key(name)}';

  // ── Suggestions ────────────────────────────────────────────────────────────

  /// Personal foods that look like [product], best first. Only strong
  /// matches; declined pairs, names already linked and the product's own
  /// scanner entries are left out.
  List<FoodLinkCandidate> candidatesFor(BarcodeProduct product) {
    if (!_readable) return const [];
    final productKey = FoodLinkMatcher.key(product.name);
    final byKey = <String, FoodLinkCandidate>{};

    void consider(String raw, {int uses = 1, String? source}) {
      if (source == 'barcode') return; // already a scanned product
      final name = FoodLinkMatcher.displayName(raw);
      final k = FoodLinkMatcher.key(name);
      if (k.isEmpty || k == productKey) return;
      if (_declined.contains('${product.barcode}|$k')) return;
      for (final l in _links.values) {
        if (l.aliasKeys.contains(k) || FoodLinkMatcher.key(l.name) == k) return;
      }
      final s = FoodLinkMatcher.score(product, name);
      if (s < FoodLinkMatcher.strongScore) return;
      final prev = byKey[k];
      byKey[k] = FoodLinkCandidate(
        name: prev?.name ?? name,
        key: k,
        score: s,
        timesUsed: (prev?.timesUsed ?? 0) + uses,
      );
    }

    try {
      for (final e in MealMemory.instance.allEntries) {
        consider(e.rawInput, uses: e.timesUsed, source: e.result.source);
      }
    } catch (_) {}
    try {
      for (final o in UserNutritionMemory.instance.allOverrides) {
        consider(o.canonicalMeal, uses: o.correctionCount);
      }
    } catch (_) {}
    try {
      for (final q in QuickAddService.instance.customItems) {
        consider(q.name);
      }
    } catch (_) {}
    try {
      for (final log in dayLogStore.values) {
        for (final e in log.allEntries) {
          final text = e.finalSavedInput.isNotEmpty ? e.finalSavedInput : e.rawInput;
          consider(text, source: e.result.source);
        }
      }
    } catch (_) {}

    final out = byKey.values.toList()
      ..sort((a, b) {
        final s = b.score.compareTo(a.score);
        return s != 0 ? s : b.timesUsed.compareTo(a.timesUsed);
      });
    return out;
  }

  /// The one food to offer linking on the scan result, or null.
  FoodLinkCandidate? suggestionFor(BarcodeProduct product) {
    final c = candidatesFor(product);
    return c.isEmpty ? null : c.first;
  }

  // ── Writes ─────────────────────────────────────────────────────────────────

  /// Link [aliasName] to [product]. The product becomes the source of truth
  /// for both names. Nothing else is changed or deleted.
  Future<FoodLink> link(BarcodeProduct product, String aliasName) async {
    await _ensureOwner();
    final alias = FoodLinkMatcher.displayName(aliasName);
    final aliasKey = FoodLinkMatcher.key(alias);
    final existing = _links[product.barcode];
    final aliases = [
      ...?existing?.aliases.where((a) => FoodLinkMatcher.key(a) != aliasKey),
      alias,
    ];
    final link = FoodLink(
      barcode: product.barcode,
      product: product,
      aliases: aliases,
      linkedAt: existing?.linkedAt ?? DateTime.now(),
    );
    _links[product.barcode] = link;
    _declined.remove(_pair(product.barcode, alias));
    await _persist();
    return link;
  }

  /// Undo a link. With [alias], only that name is unlinked; otherwise every
  /// name on the product is. Hidden entries come back as they were.
  Future<void> unlink(String barcode, {String? alias}) async {
    await _ensureOwner();
    final existing = _links[barcode.trim()];
    if (existing == null) return;
    if (alias == null) {
      _links.remove(existing.barcode);
    } else {
      final k = FoodLinkMatcher.key(alias);
      final rest = existing.aliases.where((a) => FoodLinkMatcher.key(a) != k).toList();
      if (rest.isEmpty) {
        _links.remove(existing.barcode);
      } else {
        _links[existing.barcode] = existing.copyWith(aliases: rest);
      }
    }
    await _persist();
  }

  /// "Not the same": never offer this pair again.
  Future<void> decline(BarcodeProduct product, String name) async {
    await _ensureOwner();
    _declined.add(_pair(product.barcode, name));
    await _persist();
  }

  /// Keep a link's product in step with the latest confirmed or fetched
  /// figures for that barcode.
  Future<void> refreshProduct(BarcodeProduct product) async {
    final existing = _readable ? _links[product.barcode] : null;
    if (existing == null) return;
    if (jsonEncode(existing.product.toJson()) == jsonEncode(product.toJson())) return;
    _links[product.barcode] = existing.copyWith(product: product);
    await _persist();
  }
}
