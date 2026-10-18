import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/barcode_product.dart';
import '../models/micronutrients.dart';
import 'barcode_user_products.dart';

// ─── Barcode Food Service ─────────────────────────────────────────────────────
//
// Open Food Facts barcode lookup — the one nutrition path in this app that does
// not estimate.
//
// Everywhere else the pipeline infers what the food is and then infers how much
// of it there is, and each inference carries real error. A barcode skips both:
// the label states the composition per 100 g because a laboratory measured it,
// and the pack states its own weight. What is left is multiplication.
//
// That matters most exactly where the local estimator is weakest. The mess/home
// food lexicon has nothing useful to say about Maggi, Oreo, Lay's or a whey tub,
// because those are branded products rather than cooked dishes.
//
// Open Food Facts is free, needs no API key, is ODbL-licensed and has genuine
// Indian coverage, so this talks to it directly rather than through an edge
// function — there is no secret to hide behind a server.

/// Result of a lookup, so the UI can tell "no such product" (worth offering a
/// manual retry) apart from "the network is down" (worth offering a retry of
/// the same code).
enum BarcodeLookupStatus { found, notFound, networkError, invalidCode }

class BarcodeLookupResult {
  final BarcodeLookupStatus status;
  final BarcodeProduct?     product;

  /// What Open Food Facts knows about a product it has no usable nutrition
  /// for (name, brand, pack size, photo). Pre-fills the "read the label" and
  /// "enter it yourself" forms so the person only types the numbers.
  final BarcodePartial?     partial;

  const BarcodeLookupResult(this.status, [this.product, this.partial]);

  bool get isFound => status == BarcodeLookupStatus.found && product != null;
}

/// The non-nutrition facts about a product: enough to pre-fill a form.
class BarcodePartial {
  final String  barcode;
  final String? name;
  final String? brand;
  final double? netQuantity;
  final String  unit;
  final String? imageUrl;

  const BarcodePartial({
    required this.barcode,
    this.name,
    this.brand,
    this.netQuantity,
    this.unit = 'g',
    this.imageUrl,
  });
}

/// Pack size as printed: "40 g" → 40 g; "6 x 35 g" → 6 packs of 35 g.
class PackQuantity {
  /// Total net contents (all inner packs together).
  final double total;
  final String unit; // 'g' or 'ml'
  final int?    count;
  final double? inner;

  const PackQuantity({
    required this.total,
    required this.unit,
    this.count,
    this.inner,
  });

  bool get isMultipack => (count ?? 0) > 1 && (inner ?? 0) > 0;
}

class BarcodeFoodService {
  BarcodeFoodService._();
  static final BarcodeFoodService instance = BarcodeFoodService._();

  static const _base       = 'https://world.openfoodfacts.org';
  static const _timeout    = Duration(seconds: 8);
  static const _cachePrefs = 'barcode_product_cache_v1';
  static const _cacheLimit = 200;
  static const _cacheTtl   = Duration(days: 30);

  /// Open Food Facts asks API clients to identify themselves.
  static const _userAgent =
      'Kynetix/1.0 (Android nutrition logging; https://github.com/kynetix)';

  /// Only the fields we actually read — the full product document is large and
  /// this runs on mobile data.
  static const _fields =
      'code,product_name,product_name_en,generic_name,brands,quantity,'
      'product_quantity,product_quantity_unit,serving_size,serving_quantity,'
      'serving_quantity_unit,nutrition_data_per,image_front_small_url,'
      'nutriments';

  /// Injectable for tests; the app never passes one.
  http.Client? _client;

  @visibleForTesting
  set client(http.Client? c) => _client = c;

  /// One client for the session. A fresh [http.Client] per scan leaks its
  /// connection pool, and nothing here ever closed them.
  http.Client get _http => _client ??= http.Client();

  /// Barcodes are 8–14 digits (EAN-8 through GTIN-14).
  static bool isBarcode(String? code) =>
      RegExp(r'^\d{8,14}$').hasMatch((code ?? '').trim());

  // ── Lookup ────────────────────────────────────────────────────────────────

  /// Resolve a barcode to a product: local cache first, then Open Food Facts.
  Future<BarcodeLookupResult> lookup(String code) async {
    final barcode = code.trim();
    if (!isBarcode(barcode)) {
      return const BarcodeLookupResult(BarcodeLookupStatus.invalidCode);
    }

    // What this person confirmed themselves (label photo or typed in) wins
    // over the crowd-sourced database, and needs no network.
    final mine = await BarcodeUserProducts.instance.get(barcode);
    if (mine != null) {
      return BarcodeLookupResult(BarcodeLookupStatus.found, mine);
    }

    final cached = await _readCache(barcode);
    if (cached != null) {
      debugPrint('[Barcode] $barcode served from local cache');
      return BarcodeLookupResult(BarcodeLookupStatus.found, cached);
    }

    final BarcodeProduct? product;
    BarcodePartial? partial;
    try {
      final res = await _http
          .get(
            Uri.parse('$_base/api/v2/product/$barcode.json?fields=$_fields'),
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(_timeout);

      if (res.statusCode == 404) {
        return const BarcodeLookupResult(BarcodeLookupStatus.notFound);
      }
      if (res.statusCode != 200) {
        debugPrint('[Barcode] $barcode: HTTP ${res.statusCode}');
        return const BarcodeLookupResult(BarcodeLookupStatus.networkError);
      }

      final payload = jsonDecode(res.body);
      if (payload is! Map<String, dynamic> ||
          payload['status'] != 1 ||
          payload['product'] is! Map) {
        return const BarcodeLookupResult(BarcodeLookupStatus.notFound);
      }

      // Parsing stays inside the try: these documents are crowd-sourced, so a
      // field can arrive as the wrong type entirely. A TypeError escaping here
      // would leave the sheet's spinner turning forever.
      final doc = Map<String, dynamic>.from(payload['product'] as Map);
      product = parseProduct(doc);
      if (product == null) partial = parsePartial(doc, barcode);
    } catch (e) {
      // A scan that cannot reach the network is a retry, not a crash.
      debugPrint('[Barcode] $barcode lookup failed: $e');
      return const BarcodeLookupResult(BarcodeLookupStatus.networkError);
    }

    if (product == null) {
      // Present in the database but unusable — no name, no energy, or figures
      // that contradict themselves. To the user this is the same as unknown,
      // but whatever it does know pre-fills the fallback forms.
      return BarcodeLookupResult(BarcodeLookupStatus.notFound, null, partial);
    }

    await _writeCache(product);
    return BarcodeLookupResult(BarcodeLookupStatus.found, product);
  }

  // ── Normalisation ─────────────────────────────────────────────────────────

  /// Convert one Open Food Facts product document into a [BarcodeProduct],
  /// or null when it is unusable.
  @visibleForTesting
  /// Micronutrients per 100 g from Open Food Facts nutriments, which stores
  /// minerals and vitamins in grams per 100 g. Only what the label lists is
  /// kept; sodium falls back to salt / 2.5. Null when none are listed.
  static Micronutrients? microsFromNutriments(double? Function(String key) per100) {
    const keys = {
      Micro.sodium: ('sodium', 1000.0),
      Micro.potassium: ('potassium', 1000.0),
      Micro.calcium: ('calcium', 1000.0),
      Micro.iron: ('iron', 1000.0),
      Micro.magnesium: ('magnesium', 1000.0),
      Micro.zinc: ('zinc', 1000.0),
      Micro.vitaminD: ('vitamin-d', 1e6),
      Micro.vitaminB12: ('vitamin-b12', 1e6),
    };
    final raw = <String, double>{};
    keys.forEach((m, spec) {
      final v = per100(spec.$1);
      if (v != null) raw[m.key] = v * spec.$2;
    });
    if (!raw.containsKey(Micro.sodium.key)) {
      final salt = per100('salt');
      if (salt != null) raw[Micro.sodium.key] = salt / 2.5 * 1000;
    }
    // Implausible values (a mis-keyed decimal) are dropped by fromJson.
    return Micronutrients.fromJson(raw);
  }

  static BarcodeProduct? parseProduct(Map<String, dynamic> p) {
    final code = (p['code'] ?? '').toString().trim();
    final brand = _firstBrand(p['brands']);
    final name = _buildName(p, brand);
    if (name == null || name.isEmpty) return null;

    final nutriments = p['nutriments'] is Map
        ? Map<String, dynamic>.from(p['nutriments'] as Map)
        : const <String, dynamic>{};

    final pack = packQuantityOf(p);
    final unit = _unitOf(p, pack);
    final servingQ = _servingQuantity(p, pack);

    // Most labels are per 100 g. Some entries only carry per-serving figures;
    // with a known serving size those convert exactly.
    double? per100(String key) {
      final v = _num(nutriments['${key}_100g']);
      if (v != null) return v;
      final perServing = _num(nutriments['${key}_serving']);
      if (perServing != null && servingQ != null && servingQ > 0) {
        return perServing * 100 / servingQ;
      }
      return null;
    }

    final protein = per100('proteins');
    final carbs   = per100('carbohydrates');
    final fat     = per100('fat');
    final calories = _caloriesPer100g(
      nutriments,
      servingQ: servingQ,
      atwater: (protein != null || carbs != null || fat != null)
          ? 4 * (protein ?? 0) + 4 * (carbs ?? 0) + 9 * (fat ?? 0)
          : null,
    );
    if (calories == null) return null;

    final per100g = BarcodeNutriments(
      calories: _r1(calories),
      proteinG: _r1(protein ?? 0),
      carbsG:   _r1(carbs ?? 0),
      fatG:     _r1(fat ?? 0),
      fiberG:   _r1(per100('fiber') ?? 0),
      sugarG:   _r1(per100('sugars') ?? 0),
      micros:   microsFromNutriments(per100),
    );

    // Open Food Facts is crowd-sourced, so a mis-keyed decimal produces a
    // 3,000 kcal biscuit. A wrong number that looks authoritative is worse
    // than no number at all — it silently doubles a logged day.
    final rejection = checkPer100g(
      name,
      per100g,
      // A product that simply has not had its macros filled in cannot be
      // cross-checked against them; treating that absence as a contradiction
      // would drop exactly the thinly-populated Indian entries this exists to
      // reach. The energy figure alone is still worth having.
      hasMacros: protein != null || carbs != null || fat != null,
      // Some Indian entries carry protein and carbs but no fat at all. The
      // missing macro can only add energy, so those are checked one-sided.
      partialMacros: protein == null || carbs == null || fat == null,
      // Energy the 4/4/9 rule does not account for: alcohol at 7 kcal/g and
      // sugar alcohols at ~2.4. Without these a beer or a sugar-free sweet
      // looks like a data error and gets thrown away.
      alcoholG: _num(nutriments['alcohol_100g']) ?? 0,
      polyolsG: _num(nutriments['polyols_100g']) ?? 0,
    );
    if (rejection != null) {
      debugPrint('[Barcode] rejected $code "$name": $rejection');
      return null;
    }

    return BarcodeProduct(
      barcode:  code,
      name:     name,
      brand:    brand,
      per100g:  per100g,
      servings: _servingsFor(p),
      netQuantity:     pack == null ? null : _r1(pack.total),
      unit:            unit,
      packCount:       pack?.isMultipack == true ? pack!.count : null,
      innerQuantity:   pack?.isMultipack == true ? _r1(pack!.inner!) : null,
      servingQuantity: servingQ == null ? null : _r1(servingQ),
      imageUrl:        imageUrlOf(p),
    );
  }

  /// The facts a product without usable nutrition still offers, or null when
  /// it has nothing worth pre-filling.
  @visibleForTesting
  static BarcodePartial? parsePartial(Map<String, dynamic> p, String barcode) {
    final brand = _firstBrand(p['brands']);
    final name = _buildName(p, brand);
    final pack = packQuantityOf(p);
    final image = imageUrlOf(p);
    if ((name == null || name.isEmpty) && pack == null && image == null) {
      return null;
    }
    return BarcodePartial(
      barcode:     barcode,
      name:        name,
      brand:       brand,
      netQuantity: pack?.total,
      unit:        _unitOf(p, pack),
      imageUrl:    image,
    );
  }

  /// Only Open Food Facts' own image host, over https.
  @visibleForTesting
  static String? imageUrlOf(Map<String, dynamic> p) {
    final raw = (p['image_front_small_url'] ?? '').toString().trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https') return null;
    if (!uri.host.endsWith('openfoodfacts.org')) return null;
    return raw;
  }

  /// The pack size, from the printed `quantity` text first (it carries the
  /// multipack structure), else the parsed `product_quantity` number.
  @visibleForTesting
  static PackQuantity? packQuantityOf(Map<String, dynamic> p) {
    final fromText = parseQuantity(p['quantity']);
    if (fromText != null) return fromText;

    final n = _num(p['product_quantity']);
    if (n == null || n <= 0 || n > 100000) return null;
    final u = (p['product_quantity_unit'] ?? '').toString().trim().toLowerCase();
    final unit = (u == 'ml' || u == 'l' || u == 'cl') ? 'ml' : 'g';
    final factor = switch (u) { 'l' || 'kg' => 1000.0, 'cl' => 10.0, _ => 1.0 };
    return PackQuantity(total: n * factor, unit: unit);
  }

  /// "g" or "ml": the pack's unit when known, else what the nutrition table
  /// is printed per.
  static String _unitOf(Map<String, dynamic> p, PackQuantity? pack) {
    if (pack != null) return pack.unit;
    final per = (p['nutrition_data_per'] ?? '').toString().toLowerCase();
    return per.contains('ml') ? 'ml' : 'g';
  }

  /// The label serving in the pack's unit, or null. A "serving" bigger than
  /// a single pack is a data-entry error (seen on real entries), so it is
  /// dropped rather than offered as a chip.
  static double? _servingQuantity(Map<String, dynamic> p, PackQuantity? pack) {
    final s = _num(p['serving_quantity']);
    if (s == null || s <= 0 || s > 1000) return null;
    final single = pack == null
        ? null
        : (pack.isMultipack ? pack.inner! : pack.total);
    if (single != null && s > single + 0.05) return null;
    return s;
  }

  /// Parse printed pack text. Handles "40 g", "40g", "45gm", "1 kg", "1 L",
  /// "200 ml", "500 gms", "1 ltr", "6 x 35 g", "35 g x 6", "Net wt. 40 g".
  /// Returns null when there is no number with a unit.
  @visibleForTesting
  static PackQuantity? parseQuantity(dynamic raw) {
    var text = '${raw ?? ''}'.trim().toLowerCase();
    if (text.isEmpty) return null;
    // "1,000 g" is a thousands separator; "1,5 kg" is a European decimal.
    text = text
        .replaceAllMapped(RegExp(r'(\d),(\d{3})(?!\d)'), (m) => '${m[1]}${m[2]}')
        .replaceAll(',', '.');

    const unitRe =
        r'(kg|kgs|g|gm|gms|gr|grams?|ml|mls|cl|l|ltrs?|lit(?:re|er|ter)s?)';
    double? toBase(String v, String u) {
      final value = double.tryParse(v);
      if (value == null || !value.isFinite || value <= 0) return null;
      return switch (u) {
        'kg' || 'kgs' => value * 1000,
        _ when RegExp(r'^(l|ltrs?|lit(?:re|er|ter)s?)$').hasMatch(u) =>
          value * 1000,
        'cl' => value * 10,
        _ => value,
      };
    }

    String unitOf(String u) =>
        RegExp(r'^(ml|mls|cl|l|ltrs?|lit(?:re|er|ter)s?)$').hasMatch(u)
            ? 'ml'
            : 'g';

    // "6 x 35 g", "6 packs x 11.5g"
    final multiA = RegExp(
      r'(\d+)\s*(?:packs?|pcs?|pieces?|sachets?|pouch(?:es)?|units?|nos?)?\s*[x×*]\s*(\d+(?:\.\d+)?)\s*' +
          unitRe +
          r'(?![a-z])',
    ).firstMatch(text);
    // "35 g x 6"
    final multiB = RegExp(
      r'(\d+(?:\.\d+)?)\s*' + unitRe + r'(?![a-z])\s*[x×*]\s*(\d+)',
    ).firstMatch(text);
    if (multiA != null || multiB != null) {
      final count = int.tryParse(multiA != null ? multiA.group(1)! : multiB!.group(3)!);
      final inner = multiA != null
          ? toBase(multiA.group(2)!, multiA.group(3)!)
          : toBase(multiB!.group(1)!, multiB.group(2)!);
      final u = multiA != null ? multiA.group(3)! : multiB!.group(2)!;
      if (count != null && count > 0 && count <= 100 && inner != null) {
        return PackQuantity(
          total: count * inner,
          unit: unitOf(u),
          count: count,
          inner: inner,
        );
      }
    }

    final single = RegExp(r'(\d+(?:\.\d+)?)\s*' + unitRe + r'(?![a-z])')
        .firstMatch(text);
    if (single == null) return null;
    final total = toBase(single.group(1)!, single.group(2)!);
    if (total == null || total > 100000) return null;
    return PackQuantity(total: total, unit: unitOf(single.group(2)!));
  }

  /// "Lay's Classic Salted" rather than "Classic Salted" — the brand is how
  /// people recognise packaged food on a list.
  static String? _buildName(Map<String, dynamic> p, String? brand) {
    final name = [
      p['product_name_en'],
      p['product_name'],
      p['generic_name'],
    ].map((v) => (v ?? '').toString().trim()).firstWhere(
          (v) => v.isNotEmpty,
          orElse: () => '',
        );

    if (name.isEmpty) return brand;
    if (brand == null || brand.isEmpty) return name;
    return name.toLowerCase().contains(brand.toLowerCase())
        ? name
        : '$brand $name';
  }

  static String? _firstBrand(dynamic brands) {
    final raw = (brands ?? '').toString().split(',').first.trim();
    return raw.isEmpty ? null : raw;
  }

  /// Labels state energy in kJ, kcal, or both. Prefer the stated kcal and fall
  /// back to converting kJ rather than dropping an otherwise good product.
  ///
  /// A stated zero is a real answer, not a missing one — diet drinks, black
  /// coffee and water are genuinely 0 kcal, and conflating the two made every
  /// one of them unscannable.
  ///
  /// Two real-world repairs:
  /// - per-serving energy only: converted with the serving size.
  /// - a kcal figure typed into the kJ field (seen on Indian biscuit entries:
  ///   "454 kJ" for a 454 kcal biscuit). When kJ ÷ 4.184 contradicts the
  ///   macros but the raw number matches them, the raw number is the kcal.
  static double? _caloriesPer100g(
    Map<String, dynamic> n, {
    double? servingQ,
    double? atwater,
  }) {
    final kcal = _num(n['energy-kcal_100g']);
    if (kcal != null) return kcal;
    final kj = _num(n['energy-kj_100g']) ?? _num(n['energy_100g']);
    if (kj != null) {
      final converted = (kj / 4.184).roundToDouble();
      if (atwater != null && atwater > 50) {
        bool agrees(double v) => (atwater - v).abs() / v <= _atwaterTolerance;
        if (!agrees(converted) && agrees(kj)) return kj.roundToDouble();
      }
      return converted;
    }
    if (servingQ != null && servingQ > 0) {
      final kcalS = _num(n['energy-kcal_serving']);
      if (kcalS != null) return kcalS * 100 / servingQ;
      final kjS = _num(n['energy-kj_serving']) ?? _num(n['energy_serving']);
      if (kjS != null) return (kjS / 4.184) * 100 / servingQ;
    }
    return null;
  }

  /// Portions the pack itself describes, most specific first.
  static List<BarcodeServing> _servingsFor(Map<String, dynamic> p) {
    final servings = <BarcodeServing>[];

    final servingG = _num(p['serving_quantity']);
    if (servingG != null && servingG > 0 && servingG <= 1000) {
      final stated = (p['serving_size'] ?? '').toString().trim();
      final label = stated.isEmpty ? '${servingG.round()} g' : stated;
      servings.add(BarcodeServing(
        label: label.length > 40 ? label.substring(0, 40) : label,
        unit:  'serving',
        grams: _r1(servingG),
      ));
    }

    // Whole-pack weight, when the pack is plausibly eaten as one item.
    final packG = parsePackWeight(p['quantity']);
    if (packG != null && packG > 0 && packG <= 500 && packG != servingG) {
      servings.add(BarcodeServing(
        label: '1 pack (${packG.round()} g)',
        unit:  'pack',
        grams: _r1(packG),
      ));
    }

    servings.add(BarcodeProduct.hundredGrams);
    return servings;
  }

  // ── Physical plausibility ─────────────────────────────────────────────────

  // 9 kcal/g of fat is the physical ceiling for any food.
  static const _maxKcalPer100g = 900.0;
  // Non-fat, non-nut foods above these are data errors, not foods.
  static const _maxKcalPer100gOrdinary = 600.0;
  static const _maxFatPer100gOrdinary  = 55.0;
  // Real label data disagrees with 4/4/9 by a few percent (fibre, polyols,
  // rounding). 25% is a data error, not chemistry.
  static const _atwaterTolerance = 0.25;

  static final _pureFat = RegExp(
    r'\b(oil|ghee|vanaspati|margarine|lard|tallow|butter)\b',
    caseSensitive: false,
  );
  static final _nutOrSpread = RegExp(
    r'\b(mayonnaise|almond|cashew|walnut|peanut|groundnut|pistachio|hazelnut|'
    r'macadamia|sesame|til|flax|linseed|chia|copra|nut ?butter)\b',
    caseSensitive: false,
  );

  static bool _isFatOrNutFood(String name) =>
      _pureFat.hasMatch(name) || _nutOrSpread.hasMatch(name);

  /// Returns null when the figures are physically plausible, or a reason string
  /// when they are not.
  ///
  /// [hasMacros] is false when the product simply has no macro fields, in which
  /// case there is nothing to cross-check the energy figure against.
  /// [partialMacros] is true when some macro is missing: the known macros may
  /// then fall short of the energy (the missing one fills the gap) but must
  /// not exceed it.
  @visibleForTesting
  static String? checkPer100g(
    String name,
    BarcodeNutriments n, {
    bool hasMacros = true,
    bool partialMacros = false,
    double alcoholG = 0,
    double polyolsG = 0,
  }) {
    final reasons = <String>[];
    final kcal = n.calories;
    final atwater = 4 * n.proteinG +
        4 * n.carbsG +
        9 * n.fatG +
        7 * alcoholG +
        2.4 * polyolsG;

    if (kcal < 0 || !kcal.isFinite) {
      reasons.add('calories missing');
    } else if (!hasMacros) {
      // Nothing to contradict.
    } else if (kcal == 0 && atwater > 20) {
      reasons.add('calories 0 but macros carry energy');
    } else if (kcal > 0 && partialMacros) {
      if (atwater > kcal * (1 + _atwaterTolerance)) {
        reasons.add(
          'calories ${kcal.round()} below known macros (${atwater.round()})',
        );
      }
    } else if (kcal > 0) {
      final rel = (atwater - kcal).abs() / kcal;
      if (rel > _atwaterTolerance) {
        reasons.add(
          'calories ${kcal.round()} contradict macros (${atwater.round()})',
        );
      }
    }

    if (kcal > _maxKcalPer100g) {
      reasons.add('${kcal.round()} kcal/100g exceeds pure fat');
    }
    if (!_isFatOrNutFood(name)) {
      if (n.fatG > _maxFatPer100gOrdinary) {
        reasons.add('${n.fatG} g fat/100g implausible');
      }
      if (kcal > _maxKcalPer100gOrdinary) {
        reasons.add('${kcal.round()} kcal/100g implausible');
      }
    }

    return reasons.isEmpty ? null : reasons.join('; ');
  }

  // ── Local cache ───────────────────────────────────────────────────────────
  //
  // A scanned product does not change, so the second scan of the same pack is a
  // local read. This is a lookup cache only — the moment a product is actually
  // logged, UserNutritionMemory records it by name through the normal save
  // path, which is what makes it recallable later.

  Future<BarcodeProduct?> _readCache(String barcode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefs);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entry = map[barcode];
      if (entry is! Map<String, dynamic>) return null;

      // Open Food Facts entries get corrected. Without an expiry a device would
      // serve the figures it first saw for as long as the app is installed.
      final cachedAt =
          DateTime.tryParse(entry['cachedAt'] as String? ?? '');
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > _cacheTtl) {
        return null;
      }

      return BarcodeProduct.fromJson(
        entry['product'] as Map<String, dynamic>? ?? const {},
      );
    } catch (e) {
      debugPrint('[Barcode] cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeCache(BarcodeProduct product) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefs);
      final map = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map<String, dynamic>);

      // Remove before inserting so a re-scanned product moves to the back of
      // the queue. Without this it keeps its original slot and stays first in
      // line for eviction however often it is scanned.
      map.remove(product.barcode);
      map[product.barcode] = {
        'cachedAt': DateTime.now().toIso8601String(),
        'product': product.toJson(),
      };

      // Oldest-first eviction. Insertion order is preserved by dart:convert's
      // LinkedHashMap, so the first keys are the least recently written.
      while (map.length > _cacheLimit) {
        map.remove(map.keys.first);
      }

      await prefs.setString(_cachePrefs, jsonEncode(map));
    } catch (e) {
      debugPrint('[Barcode] cache write failed: $e');
    }
  }

  /// Drop every cached product. Used when switching accounts.
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachePrefs);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double? _num(dynamic v) {
    final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return (n != null && n.isFinite && n >= 0) ? n : null;
  }

  /// Open Food Facts stores pack size as free text: "52 g", "1 L", "140g",
  /// "500 ml", "1,5 kg", "2 x 50 g".
  ///
  /// The unit is the whole point. Reading "1 L" as a bare 1 produced a one-gram
  /// pack, and logging it recorded half a calorie for a litre of juice — a
  /// silently wrong number dressed up as a measured one, which is the single
  /// failure this feature exists to rule out. Millilitres are taken as grams:
  /// for the drinks this affects the density is within a few percent, and that
  /// is far inside the error of any alternative.
  ///
  /// Multipacks return null rather than a guess. "2 x 50 g" could mean the
  /// 100 g box or the 50 g sachet someone actually opened, and a chip labelled
  /// "1 pack" cannot say which.
  @visibleForTesting
  static double? parsePackWeight(dynamic raw) {
    final text = '${raw ?? ''}'.trim().toLowerCase();
    if (text.isEmpty) return null;
    if (RegExp(r'\d\s*[x×]\s*\d').hasMatch(text)) return null;

    // European decimal commas appear throughout the database.
    final match = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)\b')
        .firstMatch(text.replaceAll(',', '.'));
    if (match == null) return null;

    final value = double.tryParse(match.group(1)!);
    if (value == null || !value.isFinite || value <= 0) return null;

    return switch (match.group(2)!) {
      'kg' => value * 1000,
      'l'  => value * 1000,
      'cl' => value * 10,
      _    => value, // g and ml
    };
  }

  static double _r1(double v) => double.parse(v.toStringAsFixed(1));
}
