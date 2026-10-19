import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'feedback_service.dart';

// ─── AnalyticsService ─────────────────────────────────────────────────────────
// In-house product analytics: small usage events into `app_events`, no
// third-party SDK. Each event is a name plus a few numbers, booleans or short
// lowercase tokens; the sanitiser drops anything else, so meal names, Kyno
// messages and other free text can never ride along.
//
// Events queue in memory and go up in batches: every [flushAt] events, every
// [flushEvery], and when the app is paused. track() is synchronous and never
// throws; a failed flush keeps the events (bounded) and tries again later.
// Signed out, events are dropped: RLS only takes rows for the signed-in user.

/// Inserts one batch of rows. The app's sink writes to Supabase; tests swap
/// it for a list.
typedef AnalyticsSink = Future<void> Function(List<Map<String, Object?>> rows);

class AnalyticsService {
  AnalyticsService({
    AnalyticsSink? sink,
    bool Function()? signedIn,
    this.flushAt = 20,
    this.flushEvery = const Duration(seconds: 30),
    this.maxQueue = 200,
  })  : _sink = sink ?? _supabaseSink,
        _signedIn = signedIn ?? _hasSession;

  static final AnalyticsService instance = AnalyticsService();

  final AnalyticsSink _sink;
  final bool Function() _signedIn;
  final int flushAt;
  final Duration flushEvery;

  /// Most events held at once; past it the oldest go first.
  final int maxQueue;

  /// One id per app launch, so events group into sessions.
  final String sessionId = _uuidV4();

  final List<Map<String, Object?>> _queue = [];
  Timer? _timer;
  Future<void>? _flushing;
  AppLifecycleListener? _lifecycle;
  String? _appVersion;
  String? _platform;

  static final _nameRe = RegExp(r'^[a-z][a-z0-9_]{1,48}$');
  static final _keyRe = RegExp(r'^[a-z][a-z0-9_]{0,31}$');
  static final _tokenRe = RegExp(r'^[a-z0-9][a-z0-9_.\-]{0,31}$');
  static const _maxProps = 16;

  @visibleForTesting
  int get queued => _queue.length;

  /// Reads the app version and platform, and flushes when the app goes to
  /// the background. Call once after Supabase is ready.
  Future<void> init() async {
    _lifecycle ??= AppLifecycleListener(
      onPause: flush,
      onHide: flush,
      onDetach: flush,
    );
    try {
      _platform = kIsWeb ? 'web' : FeedbackService.platformLabel(Platform.operatingSystem, Platform.operatingSystemVersion);
    } catch (_) {
      _platform = defaultTargetPlatform.name;
    }
    if (_platform!.length > 60) _platform = _platform!.substring(0, 60);
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.buildNumber.trim().isEmpty ? info.version.trim() : '${info.version.trim()}+${info.buildNumber.trim()}';
      _appVersion = v.isEmpty ? null : (v.length > 40 ? v.substring(0, 40) : v);
    } catch (_) {}
  }

  /// Keeps only what is safe to store: snake_case keys, and values that are
  /// booleans, finite numbers (doubles to two places) or short lowercase
  /// tokens ("photo", "1x1", "story"). Free text, nulls, lists and maps are
  /// dropped. At most [_maxProps] keys. Pure.
  static Map<String, Object> sanitizeProps(Map<String, Object?>? props) {
    final out = <String, Object>{};
    if (props == null) return out;
    for (final e in props.entries) {
      if (out.length >= _maxProps) break;
      if (!_keyRe.hasMatch(e.key)) continue;
      final v = e.value;
      if (v is bool || v is int) {
        out[e.key] = v!;
      } else if (v is double) {
        if (v.isFinite) out[e.key] = (v * 100).roundToDouble() / 100;
      } else if (v is String && _tokenRe.hasMatch(v)) {
        out[e.key] = v;
      }
    }
    return out;
  }

  /// A coarse calorie band, so no exact meal can be pieced back together.
  static String kcalBucket(num kcal) {
    if (kcal < 200) return 'under_200';
    if (kcal < 400) return '200_399';
    if (kcal < 600) return '400_599';
    if (kcal < 900) return '600_899';
    return '900_plus';
  }

  /// Records [name] with [props]. Never throws and never waits.
  void track(String name, [Map<String, Object?>? props]) {
    try {
      if (!_nameRe.hasMatch(name)) {
        debugPrint('[ANALYTICS] bad event name: $name');
        return;
      }
      if (!_signedIn()) return;
      _queue.add({
        'name':        name,
        'props':       sanitizeProps(props),
        'session_id':  sessionId,
        'created_at':  DateTime.now().toUtc().toIso8601String(),
        'app_version': _appVersion,
        'platform':    _platform,
      });
      if (_queue.length > maxQueue) _queue.removeRange(0, _queue.length - maxQueue);
      if (_queue.length >= flushAt) {
        unawaited(flush());
      } else {
        _timer ??= Timer(flushEvery, () {
          _timer = null;
          unawaited(flush());
        });
      }
    } catch (_) {}
  }

  /// Sends what is queued. Safe to call any time; concurrent calls share one
  /// send. Failures are swallowed and the batch goes back in the queue.
  Future<void> flush() {
    return _flushing ??= _drain().whenComplete(() => _flushing = null);
  }

  Future<void> _drain() async {
    _timer?.cancel();
    _timer = null;
    while (_queue.isNotEmpty) {
      if (!_signedIn()) {
        _queue.clear();
        return;
      }
      final batch = _queue.take(50).toList();
      _queue.removeRange(0, batch.length);
      try {
        await _sink(batch);
      } catch (e) {
        debugPrint('[ANALYTICS] flush failed: $e');
        _queue.insertAll(0, batch);
        if (_queue.length > maxQueue) _queue.removeRange(0, _queue.length - maxQueue);
        _timer ??= Timer(flushEvery, () {
          _timer = null;
          unawaited(flush());
        });
        return;
      }
    }
  }

  /// Flushes before the session goes away (sign out, account deletion), so
  /// the last events still belong to the user who made them. Bounded.
  Future<void> flushBeforeSignOut() async {
    try {
      await flush().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _queue.clear();
  }

  static bool _hasSession() {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _supabaseSink(List<Map<String, Object?>> rows) =>
      Supabase.instance.client.from('app_events').insert(rows).timeout(const Duration(seconds: 12));

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
