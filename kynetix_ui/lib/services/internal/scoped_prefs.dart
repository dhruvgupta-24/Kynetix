import 'package:shared_preferences/shared_preferences.dart';
import '../user_session_coordinator.dart';

/// Per-user SharedPreferences keys with the legacy-owner rule.
///
/// Every store lives at `<base>_<userId>`. The old device-wide `<base>` key is
/// only ever read by the account that owns the device's legacy data (see
/// [UserSessionCoordinator.legacyOwner]); any other account on the device
/// starts clean instead of inheriting someone else's data. With no user
/// (pre-auth / tests) the device-wide key is used as before.
///
/// Reads only: nothing here deletes or rewrites the legacy keys.
class ScopedPrefs {
  ScopedPrefs._();

  /// Where [base] is stored for [userId].
  static String key(String base, String? userId) =>
      userId == null || userId.isEmpty ? base : '${base}_$userId';

  /// Whether [userId] may fall back to the device-wide legacy keys.
  static bool mayReadLegacy(SharedPreferences prefs, String? userId) =>
      userId == null ||
      userId.isEmpty ||
      UserSessionCoordinator.legacyOwner(prefs) == userId;

  static String? getString(
      SharedPreferences prefs, String base, String? userId) {
    final own = prefs.getString(key(base, userId));
    if (own != null) return own;
    return mayReadLegacy(prefs, userId) ? prefs.getString(base) : null;
  }

  static List<String>? getStringList(
      SharedPreferences prefs, String base, String? userId) {
    final own = prefs.getStringList(key(base, userId));
    if (own != null) return own;
    return mayReadLegacy(prefs, userId) ? prefs.getStringList(base) : null;
  }

  static double? getDouble(
      SharedPreferences prefs, String base, String? userId) {
    final own = prefs.getDouble(key(base, userId));
    if (own != null) return own;
    return mayReadLegacy(prefs, userId) ? prefs.getDouble(base) : null;
  }
}
