import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/barcode_product.dart';

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

  const BarcodeLookupResult(this.status, [this.product]);

  bool get isFound => status == BarcodeLookupStatus.found && product != null;
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
      'serving_size,serving_quantity,nutriments';

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

    final cached = await _readCache(barcode);
    if (cached != null) {
      debugPrint('[Barcode] $barcode served from local cache');
      return BarcodeLookupResult(BarcodeLookupStatus.found, cached);
    }

    final BarcodeProduct? product;
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
      product = parseProduct(
        Map<String, dynamic>.from(payload['product'] as Map),
      );
    } catch (e) {
      // A scan that cannot reach the network is a retry, not a crash.
      debugPrint('[Barcode] $barcode lookup failed: $e');
      return const BarcodeLookupResult(BarcodeLookupStatus.networkError);
    }

    if (product == null) {
      // Present in the database but unusable — no name, no energy, or figures
      // that contradict themselves. To the user this is the same as unknown.
      return const BarcodeLookupResult(BarcodeLookupStatus.notFound);
    }

    await _writeCache(product);
    return BarcodeLookupResult(BarcodeLookupStatus.found, product);
  }

  // ── Normalisation ─────────────────────────────────────────────────────────

  /// Convert one Open Food Facts product document into a [BarcodeProduct],
  /// or null when it is unusable.
  @visibleForTesting
  static BarcodeProduct? parseProduct(Map<String, dynamic> p) {
    final code = (p['code'] ?? '').toString().trim();
    final brand = _firstBrand(p['brands']);
    final name = _buildName(p, brand);
    if (name == null || name.isEmpty) return null;

    final nutriments = p['nutriments'] is Map
        ? Map<String, dynamic>.from(p['nutriments'] as Map)
        : const <String, dynamic>{};
    final calories = _caloriesPer100g(nutriments);
    if (calories == null) return null;

    final protein = _num(nutriments['proteins_100g']);
    final carbs   = _num(nutriments['carbohydrates_100g']);
    final fat     = _num(nutriments['fat_100g']);

    final per100g = BarcodeNutriments(
      calories: _r1(calories),
      proteinG: _r1(protein ?? 0),
      carbsG:   _r1(carbs ?? 0),
      fatG:     _r1(fat ?? 0),
      fiberG:   _r1(_num(nutriments['fiber_100g']) ?? 0),
      sugarG:   _r1(_num(nutriments['sugars_100g']) ?? 0),
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
    );
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
  static double? _caloriesPer100g(Map<String, dynamic> n) {
    final kcal = _num(n['energy-kcal_100g']);
    if (kcal != null) return kcal;
    final kj = _num(n['energy-kj_100g']) ?? _num(n['energy_100g']);
    if (kj != null) return (kj / 4.184).roundToDouble();
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
  @visibleForTesting
  static String? checkPer100g(
    String name,
    BarcodeNutriments n, {
    bool hasMacros = true,
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
