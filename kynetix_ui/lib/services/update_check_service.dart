import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/distribution.dart';

// ─── UpdateCheckService ───────────────────────────────────────────────────────
// Sideload builds only (see config/distribution.dart). Reads the website's
// version.json and says whether a newer APK is out. Never downloads or
// installs anything itself: the prompt opens the download page in the
// browser, and Android's own installer takes it from there.
//
// Off when the build is a Play build, and off when Google Play installed the
// app even if the build says sideload (Play policy: no self-updates).
//
// Version codes: `flutter build apk --split-per-abi` adds an ABI offset to
// the version code (armeabi-v7a +1000, arm64-v8a +2000, x86_64 +4000), so an
// arm64 build of code 7 reports 2007. Every comparison uses `code % 1000`,
// which keeps arm64 and armv7 builds comparing equal. Plain version codes
// must therefore stay below 1000.

/// What version.json says about the newest build.
@immutable
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.page,
    this.apk,
    this.notes = const [],
    this.minVersionCode = 0,
    this.playUrl,
  });

  final int versionCode;
  final String versionName;
  final String? apk;
  final String page;
  final List<String> notes;
  final int minVersionCode;
  final String? playUrl;

  /// Null when the JSON is not a usable release.
  static AppRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['versionCode'];
    final name = json['versionName'];
    final page = json['page'];
    if (code is! int || name is! String || page is! String || page.isEmpty) return null;
    final notes = json['notes'];
    final play = json['playUrl'];
    final min = json['minVersionCode'];
    return AppRelease(
      versionCode: code,
      versionName: name,
      apk: json['apk'] is String ? json['apk'] as String : null,
      page: page,
      notes: notes is List ? [for (final n in notes) if (n is String && n.trim().isNotEmpty) n.trim()] : const [],
      minVersionCode: min is int ? min : 0,
      playUrl: play is String && play.isNotEmpty ? play : null,
    );
  }
}

/// What to show.
enum UpdateKind {
  /// Up to date.
  none,

  /// A newer build is out; "Later" is fine.
  optional,

  /// Below minVersionCode: no "Later", and it shows on every launch.
  required,

  /// Kynetix is on Google Play now: move over.
  play,
}

/// The outcome of one check.
@immutable
class UpdateCheck {
  const UpdateCheck(this.release, this.kind, {required this.reached});
  final AppRelease? release;
  final UpdateKind kind;
  final bool reached;
}

class UpdateCheckService {
  UpdateCheckService({
    Future<String?> Function()? fetch,
    Future<String> Function()? buildNumber,
    Future<String?> Function()? installer,
    DateTime Function()? now,
    bool? sideload,
  })  : _fetch = fetch ?? _httpFetch,
        _buildNumber = buildNumber ?? _packageBuildNumber,
        _installer = installer ?? _installerPackage,
        _now = now ?? DateTime.now,
        _sideload = sideload ?? kSideload;

  static final UpdateCheckService instance = UpdateCheckService();

  static const url = 'https://dhruvgupta-24.github.io/Kynetix/version.json';
  static const playStore = 'com.android.vending';
  static const interval = Duration(hours: 12);
  static const _lastKey = 'update_check_last_at';
  static const _cacheKey = 'update_check_release';

  final Future<String?> Function() _fetch;
  final Future<String> Function() _buildNumber;
  final Future<String?> Function() _installer;
  final DateTime Function() _now;
  final bool _sideload;

  Future<bool>? _active;

  /// Version code with the split-per-abi offset removed (see the top).
  static int baseCode(int code) => code % 1000;

  static int installedCode(String buildNumber) => baseCode(int.tryParse(buildNumber.trim()) ?? 0);

  /// The decision, pure. A Play move wins; then the minimum; then "newer".
  static UpdateKind decide(AppRelease r, int installed) {
    final mine = baseCode(installed);
    if (r.playUrl != null) return UpdateKind.play;
    if (mine < baseCode(r.minVersionCode)) return UpdateKind.required;
    if (baseCode(r.versionCode) > mine) return UpdateKind.optional;
    return UpdateKind.none;
  }

  /// True when a fresh fetch is due: never checked, 12 h passed, or the
  /// clock went backwards.
  static bool isDue(DateTime? last, DateTime now) =>
      last == null || now.isBefore(last) || now.difference(last) >= interval;

  /// Sideload build, and not installed by Google Play. Asked once.
  Future<bool> isActive() => _active ??= () async {
        if (!_sideload) return false;
        try {
          return await _installer() != playStore;
        } catch (_) {
          return true;
        }
      }();

  /// What to offer now. [UpdateCheck.kind] is none when there is nothing to
  /// show; [UpdateCheck.reached] says whether version.json was read this
  /// time. Never throws.
  ///
  /// [force] (Settings, "Check for updates") always fetches. Otherwise a
  /// fetch happens at most every 12 h; between fetches only a required
  /// update is shown again, from the cached release.
  Future<UpdateCheck> check({bool force = false}) async {
    const nothing = UpdateCheck(null, UpdateKind.none, reached: false);
    try {
      if (!await isActive()) return nothing;
      final prefs = await SharedPreferences.getInstance();
      final installed = installedCode(await _buildNumber());
      final now = _now();
      final lastMs = prefs.getInt(_lastKey);
      final last = lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs);

      AppRelease? release;
      var fetched = false;
      if (force || isDue(last, now)) {
        final body = await _fetch();
        if (body != null) {
          release = AppRelease.fromJson(jsonDecode(body));
          if (release != null) {
            fetched = true;
            await prefs.setInt(_lastKey, now.millisecondsSinceEpoch);
            await prefs.setString(_cacheKey, body);
          }
        }
      }
      if (release == null) {
        final cached = prefs.getString(_cacheKey);
        release = cached == null ? null : AppRelease.fromJson(jsonDecode(cached));
      }
      if (release == null) return UpdateCheck(null, UpdateKind.none, reached: fetched);

      final kind = decide(release, installed);
      // Optional and Play prompts only on a fresh fetch (so at most every
      // 12 h); a required one every launch.
      if (kind == UpdateKind.none || (!fetched && kind != UpdateKind.required)) {
        return UpdateCheck(release, UpdateKind.none, reached: fetched);
      }
      return UpdateCheck(release, kind, reached: fetched);
    } catch (e) {
      debugPrint('[UPDATE_CHECK] failed: $e');
      return nothing;
    }
  }

  static Future<String?> _httpFetch() async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      return res.statusCode == 200 ? res.body : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _packageBuildNumber() async => (await PackageInfo.fromPlatform()).buildNumber;

  static const _channel = MethodChannel('com.kynetix.app/install');

  static Future<String?> _installerPackage() => _channel.invokeMethod<String>('installerPackage');
}
