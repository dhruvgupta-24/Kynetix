import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/barcode_product.dart';
import 'nutrition_hydration_guard.dart';

/// Products this person confirmed themselves: read off a label photo and
/// checked, or typed in. Keyed by barcode, stored per user.
///
/// - Local only (SharedPreferences), under `barcode_user_products_v1_<userId>`.
///   The `_<userId>` suffix is what account deletion's per-user key sweep
///   (`PersistenceService.removeKeysForUser`) matches, so deleting the account
///   removes these too. Nothing is uploaded.
/// - A confirmed product wins over Open Food Facts for this user: the lookup
///   reads here first, so the next scan of the same pack is instant and uses
///   the person's own numbers.
class BarcodeUserProducts {
  BarcodeUserProducts._();
  static final BarcodeUserProducts instance = BarcodeUserProducts._();

  static const keyPrefix = 'barcode_user_products_v1';

  /// A device holds a handful of accounts at most; this caps one account's
  /// store so a runaway loop can never fill preferences.
  static const _limit = 500;

  /// Injectable for tests; the app reads the signed-in user.
  @visibleForTesting
  String? Function()? userIdOverride;

  String get _userId {
    final id = userIdOverride?.call() ??
        NutritionHydrationGuard.instance.currentUserId;
    return (id == null || id.trim().isEmpty) ? 'guest' : id;
  }

  /// The storage key for [userId].
  static String keyFor(String userId) => '${keyPrefix}_$userId';

  Future<Map<String, dynamic>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(keyFor(_userId));
    if (raw == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// This user's confirmed product for [barcode], or null.
  Future<BarcodeProduct?> get(String barcode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = (await _readAll(prefs))[barcode.trim()];
      if (entry is! Map<String, dynamic>) return null;
      final product = BarcodeProduct.fromJson(
        entry['product'] as Map<String, dynamic>? ?? const {},
      );
      if (product.name.isEmpty || product.barcode.isEmpty) return null;
      return product;
    } catch (e) {
      debugPrint('[Barcode] user product read failed: $e');
      return null;
    }
  }

  /// Save (or replace) a confirmed product. Only user-confirmed sources are
  /// stored here; an Open Food Facts product has its own cache.
  Future<void> save(BarcodeProduct product) async {
    assert(product.source.isUserConfirmed);
    final prefs = await SharedPreferences.getInstance();
    final map = await _readAll(prefs);
    map.remove(product.barcode);
    map[product.barcode] = {
      'savedAt': DateTime.now().toIso8601String(),
      'product': product.toJson(),
    };
    while (map.length > _limit) {
      map.remove(map.keys.first);
    }
    await prefs.setString(keyFor(_userId), jsonEncode(map));
  }

  /// Forget one product (for "this is wrong, scan it fresh").
  Future<void> remove(String barcode) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await _readAll(prefs);
    if (map.remove(barcode.trim()) != null) {
      await prefs.setString(keyFor(_userId), jsonEncode(map));
    }
  }
}
