import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends one scrubbed error report. Swap this to change the transport
/// (for example to a `report-error` edge function).
typedef ErrorTransport = Future<void> Function(Map<String, Object?> report);

/// Reports uncaught errors without personal data.
///
/// Wire-up (in `main.dart`, after `Supabase.initialize`, before `runApp`):
/// ```dart
/// ErrorReporter.instance.install();
/// ```
///
/// - Hooks `FlutterError.onError` and `PlatformDispatcher.instance.onError`,
///   keeping whatever handlers were there (console output in debug).
/// - Scrubs emails, phone numbers and tokens from messages and stacks, and
///   truncates both.
/// - At most [maxPerSession] reports per app session, de-duplicated.
/// - Never throws. A no-op in debug builds unless `enableInDebug: true`.
/// - Sends only when someone is signed in (the table accepts inserts from
///   authenticated users).
class ErrorReporter {
  ErrorReporter._({
    ErrorTransport? transport,
    String? Function()? currentUserId,
    bool? debugMode,
  })  : transport = transport ?? _insertClientError,
        _currentUserId = currentUserId ?? _defaultUserId,
        _debugMode = debugMode ?? kDebugMode;

  static final ErrorReporter instance = ErrorReporter._();

  @visibleForTesting
  factory ErrorReporter.forTesting({
    required ErrorTransport transport,
    String? Function()? currentUserId,
    bool debugMode = false,
  }) =>
      ErrorReporter._(
        transport: transport,
        currentUserId: currentUserId ?? () => 'test-user',
        debugMode: debugMode,
      );

  static const maxPerSession = 20;
  static const maxMessageLength = 500;
  static const maxStackLines = 25;
  static const maxStackLength = 3000;

  /// App version sent with each report. Set at build time with
  /// `--dart-define=KYNETIX_APP_VERSION=1.2.3+45`.
  static const appVersion =
      String.fromEnvironment('KYNETIX_APP_VERSION', defaultValue: '1.0.0+1');

  /// The one place reports leave the app.
  ErrorTransport transport;

  final String? Function() _currentUserId;
  final bool _debugMode;

  bool _installed = false;
  bool _enabledInDebug = false;
  bool _reporting = false;
  int _sent = 0;
  final Set<String> _seen = <String>{};

  bool get _active => !_debugMode || _enabledInDebug;

  @visibleForTesting
  int get sentCount => _sent;

  /// Hooks the global error handlers. Safe to call more than once.
  void install({bool enableInDebug = false}) {
    try {
      _enabledInDebug = enableInDebug;
      if (_installed) return;
      _installed = true;

      final previousFlutter = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        try {
          (previousFlutter ?? FlutterError.presentError)(details);
        } catch (_) {}
        report(details.exception, details.stack, type: 'flutter');
      };

      final previousPlatform = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        report(error, stack, type: 'platform');
        try {
          if (previousPlatform != null) return previousPlatform(error, stack);
        } catch (_) {}
        // Debug: let the engine print it. Release: handled.
        return !kDebugMode;
      };
    } catch (_) {}
  }

  /// Reports one error. Fire-and-forget; never throws.
  void report(Object error, StackTrace? stack, {String type = 'manual'}) {
    // Re-entrancy guard: an error raised while building a report is dropped.
    if (_reporting) return;
    _reporting = true;
    try {
      if (!_active) return;
      if (_sent >= maxPerSession) return;
      final userId = _currentUserId();
      if (userId == null || userId.isEmpty) return;

      final message = truncate(scrub(_describe(error)), maxMessageLength);
      final trace = scrubStack(stack);
      final key = '$type|${error.runtimeType}|$message|${_firstLine(trace)}';
      if (!_seen.add(key)) return;
      _sent++;

      final row = <String, Object?>{
        'user_id': userId,
        'app_version': appVersion,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'error_type': '$type:${error.runtimeType}',
        'message': message,
        'stack': trace,
      };
      Future<void>.sync(() => transport(row)).catchError((Object _) {}).ignore();
    } catch (_) {
      // Never throw from the error path.
    } finally {
      _reporting = false;
    }
  }

  // ── Scrubbing ─────────────────────────────────────────────────────────────

  static final _email = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
  static final _jwt = RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+');
  static final _bearer = RegExp(r'(Bearer|token|apikey|key)([=:\s]+)[A-Za-z0-9._\-]{12,}', caseSensitive: false);
  // 10+ digits, optionally with +, spaces, dashes, dots or brackets between.
  static final _phone = RegExp(r'\+?\d[\d\s\-().]{8,}\d');

  /// Removes emails, phone numbers and tokens.
  static String scrub(String s) => s
      .replaceAll(_email, '[email]')
      .replaceAll(_jwt, '[token]')
      .replaceAllMapped(_bearer, (m) => '${m[1]}${m[2]}[token]')
      .replaceAllMapped(_phone, (m) {
        final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
        return digits.length >= 10 ? '[phone]' : m[0]!;
      });

  static String truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  static String? scrubStack(StackTrace? stack) {
    if (stack == null) return null;
    final lines = stack.toString().split('\n').where((l) => l.trim().isNotEmpty);
    final kept = lines.take(maxStackLines).join('\n');
    return truncate(scrub(kept), maxStackLength);
  }

  static String _describe(Object error) {
    try {
      return error.toString();
    } catch (_) {
      return error.runtimeType.toString();
    }
  }

  static String _firstLine(String? s) =>
      s == null ? '' : s.split('\n').first;

  // ── Default transport ─────────────────────────────────────────────────────

  static String? _defaultUserId() {
    try {
      return Supabase.instance.client.auth.currentSession?.user.id;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _insertClientError(Map<String, Object?> report) async {
    await Supabase.instance.client
        .from('client_errors')
        .insert(report)
        .timeout(const Duration(seconds: 10));
  }
}
