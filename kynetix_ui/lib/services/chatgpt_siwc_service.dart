// Sign in with ChatGPT (plan usage): the on-device half of the flow.
//
//   1. Bind a loopback listener on 127.0.0.1 (1455, or any free port).
//   2. Open the authorize URL in the system browser (PKCE S256, state, nonce).
//   3. Validate the callback, then exchange the code on-device (public client,
//      no secret).
//   4. Hand the tokens straight to the `openai-link-siwc` edge function, which
//      verifies the ID token, checks plan access and stores everything
//      server-side. Nothing token-shaped is persisted on the device and nothing
//      token-shaped is logged.
//
// Only non-secret values live in SharedPreferences: the stable
// ext_agent_host_id, the issued `oaiapp_…` client id, and whether the
// first-time "You're using your ChatGPT plan" moment has been shown.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_client.dart';
import 'chatgpt_siwc_protocol.dart';

enum SiwcPhase { waitingForBrowser, connecting }

enum SiwcFailure {
  /// The user backed out in the app.
  cancelled,

  /// The user declined on the ChatGPT consent screen.
  denied,

  /// No callback within five minutes.
  timedOut,

  /// Couldn't open a browser.
  browserUnavailable,

  /// Couldn't open a local listener at all.
  listenerUnavailable,

  /// State / nonce / client id didn't check out. Nothing was exchanged.
  securityCheck,

  /// Registration came back without an issued client id.
  registrationIncomplete,

  /// Signed in, but plan usage (chatgpt.tokens.use.direct) wasn't granted.
  planNotEnabled,

  /// This account / workspace / region can't use plan usage here.
  notEligible,

  /// Code exchange failed (expired / reused code). Restart sign-in.
  exchangeFailed,

  /// No network, or the server couldn't be reached.
  network,

  /// Our server or OpenAI had a problem.
  server,
}

class SiwcException implements Exception {
  const SiwcException(this.failure, {this.code});
  final SiwcFailure failure;

  /// Diagnostic code (OAuth / API error code). Never shown raw to users.
  final String? code;

  @override
  String toString() => 'SiwcException(${failure.name}${code == null ? '' : ', $code'})';
}

class SiwcConnectResult {
  const SiwcConnectResult({
    this.model,
    this.usageLimited = false,
    this.firstTimePlanUse = false,
  });

  /// Model slug the server picked from the account's `visibility == list` set.
  final String? model;

  /// Connected, but the plan's usage limit is currently reached.
  final bool usageLimited;

  /// First time this Kynetix user turned on plan usage on this device.
  final bool firstTimePlanUse;
}

/// One run of the browser sign-in. Create a fresh instance per attempt.
class ChatGptSiwcFlow {
  ChatGptSiwcFlow({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  HttpServer? _server;
  Completer<Uri>? _callback;
  bool _cancelled = false;

  static const _prefsHostId = 'chatgpt_siwc_ext_agent_host_id';
  static String _prefsClientId(String uid) => 'chatgpt_siwc_client_id_$uid';
  static String _prefsWelcome(String uid) => 'chatgpt_siwc_welcome_shown_$uid';

  /// Stops waiting, closes the listener. Safe to call any time.
  void cancel() {
    _cancelled = true;
    final c = _callback;
    if (c != null && !c.isCompleted) {
      c.completeError(const SiwcException(SiwcFailure.cancelled));
    }
    _closeServer();
  }

  Future<SiwcConnectResult> run({
    required void Function(SiwcPhase phase) onPhase,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) throw const SiwcException(SiwcFailure.server, code: 'no_session');

    final prefs = await SharedPreferences.getInstance();
    final hostId = _hostId(prefs);
    final savedClientId = prefs.getString(_prefsClientId(uid));

    try {
      // 1. Listener first, then the browser.
      final port = await _bindLoopback();
      final attempt = SiwcAttempt(
        clientId: savedClientId ?? SiwcConfig.dynamicClientId,
        redirectUri: SiwcConfig.redirectUriFor(port),
        extAgentHostId: hostId,
      );
      _callback = Completer<Uri>();
      // A cancel can land before anyone awaits; don't let it surface as an
      // unhandled async error. Later awaits still see it.
      _callback!.future.ignore();
      _listen();

      if (_cancelled) throw const SiwcException(SiwcFailure.cancelled);
      onPhase(SiwcPhase.waitingForBrowser);

      final launched = await _launch(attempt.authorizeUri());
      if (!launched) throw const SiwcException(SiwcFailure.browserUnavailable);

      // 2. Wait for the browser to come back.
      final Uri callbackUri;
      try {
        callbackUri = await _callback!.future.timeout(SiwcConfig.callbackTimeout);
      } on TimeoutException {
        throw const SiwcException(SiwcFailure.timedOut);
      } finally {
        _closeServer();
      }

      final parsed = SiwcCallbackParser.parse(callbackUri, attempt);
      switch (parsed.outcome) {
        case SiwcCallbackOutcome.success:
          break;
        case SiwcCallbackOutcome.denied:
          throw const SiwcException(SiwcFailure.denied);
        case SiwcCallbackOutcome.stateMismatch:
        case SiwcCallbackOutcome.clientIdMismatch:
          throw SiwcException(SiwcFailure.securityCheck, code: parsed.outcome.name);
        case SiwcCallbackOutcome.missingClientId:
          throw const SiwcException(SiwcFailure.registrationIncomplete);
        case SiwcCallbackOutcome.missingCode:
          throw const SiwcException(SiwcFailure.exchangeFailed, code: 'missing_code');
        case SiwcCallbackOutcome.error:
          // A saved client id the server no longer accepts: forget it so the
          // next attempt registers fresh.
          if (!attempt.isRegistration &&
              (parsed.error == 'invalid_client' ||
                  parsed.error == 'unauthorized_client')) {
            await prefs.remove(_prefsClientId(uid));
          }
          throw SiwcException(SiwcFailure.server, code: parsed.error);
      }

      final clientId = parsed.clientId!;
      // Registration is done the moment we have the issued id: keep it.
      await prefs.setString(_prefsClientId(uid), clientId);

      if (_cancelled) throw const SiwcException(SiwcFailure.cancelled);
      onPhase(SiwcPhase.connecting);

      // The browser is still in front here. Android freezes background apps,
      // so a request started now can stall until the user switches back and
      // then time out. Finish the handoff once Kynetix is in front again.
      await _untilForeground();
      if (_cancelled) throw const SiwcException(SiwcFailure.cancelled);

      // 3. On-device code exchange (public client, PKCE, no secret).
      final tokens = await _exchange(
        clientId: clientId,
        code: parsed.code!,
        attempt: attempt,
      );

      final grantedScope = (tokens['scope'] as String?) ?? parsed.grantedScope;
      if (!SiwcTokens.hasPlanScope(grantedScope)) {
        throw const SiwcException(SiwcFailure.planNotEnabled);
      }
      final idToken = tokens['id_token'] as String?;
      if (!SiwcTokens.idTokenNonceMatches(idToken, attempt.nonce)) {
        throw const SiwcException(SiwcFailure.securityCheck, code: 'nonce');
      }

      // 4. Straight to the server; the device keeps nothing secret.
      final result = await _store(
        tokens: tokens,
        clientId: clientId,
        grantedScope: grantedScope!,
        attempt: attempt,
      );

      final welcomeKey = _prefsWelcome(uid);
      final firstTime = !(prefs.getBool(welcomeKey) ?? false);
      if (firstTime) await prefs.setBool(welcomeKey, true);

      return SiwcConnectResult(
        model: result['selected_model'] as String?,
        usageLimited: result['usage_limited'] == true,
        firstTimePlanUse: firstTime,
      );
    } finally {
      _closeServer();
      _http.close();
    }
  }

  // ── Loopback listener ─────────────────────────────────────────────────────

  Future<int> _bindLoopback() async {
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        SiwcConfig.preferredPort,
      );
    } on SocketException {
      try {
        // 1455 is busy: only the port may change, so take any free one.
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      } on SocketException {
        throw const SiwcException(SiwcFailure.listenerUnavailable);
      }
    }
    return _server!.port;
  }

  void _listen() {
    final server = _server;
    if (server == null) return;
    server.listen(
      (request) async {
        final res = request.response;
        try {
          if (request.method != 'GET' ||
              request.uri.path != SiwcConfig.callbackPath) {
            res.statusCode = HttpStatus.notFound;
            await res.close();
            return;
          }
          final q = request.uri.queryParameters;
          final ok = q.containsKey('code') && !q.containsKey('error');
          res
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..headers.set('Cache-Control', 'no-store')
            ..headers.set('Referrer-Policy', 'no-referrer')
            ..write(siwcCallbackPage(ok: ok));
          await res.close();
          final c = _callback;
          if (c != null && !c.isCompleted) c.complete(request.uri);
        } catch (_) {
          try {
            await res.close();
          } catch (_) {}
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _closeServer() {
    final s = _server;
    _server = null;
    if (s != null) unawaited(s.close(force: true));
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  // ── Token exchange ────────────────────────────────────────────────────────

  /// Resolves when the app is in the foreground (immediately if it is), or
  /// after [SiwcConfig.callbackTimeout] at the latest.
  static Future<void> _untilForeground() async {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState == null || binding.lifecycleState == AppLifecycleState.resumed) return;
    final done = Completer<void>();
    final listener = AppLifecycleListener(onResume: () {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(SiwcConfig.callbackTimeout, onTimeout: () {});
    } finally {
      listener.dispose();
    }
  }

  /// One retry for a dropped connection (a phone waking up, a network
  /// switch). A timeout is not retried: the code may already be spent.
  Future<Map<String, dynamic>> _exchange({
    required String clientId,
    required String code,
    required SiwcAttempt attempt,
  }) async {
    try {
      return await _exchangeOnce(clientId: clientId, code: code, attempt: attempt);
    } on SiwcException catch (e) {
      if (e.failure != SiwcFailure.network || e.code == 'exchange_timeout') rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return _exchangeOnce(clientId: clientId, code: code, attempt: attempt);
    }
  }

  Future<Map<String, dynamic>> _exchangeOnce({
    required String clientId,
    required String code,
    required SiwcAttempt attempt,
  }) async {
    final http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse(SiwcConfig.tokenUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'grant_type': 'authorization_code',
              'client_id': clientId,
              'code': code,
              'code_verifier': attempt.verifier,
              'redirect_uri': attempt.redirectUri,
              'resource': SiwcConfig.resource,
            },
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const SiwcException(SiwcFailure.network, code: 'exchange_timeout');
    } on SocketException {
      throw const SiwcException(SiwcFailure.network);
    } on http.ClientException {
      throw const SiwcException(SiwcFailure.network);
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (res.statusCode != 200 || body == null || body['access_token'] is! String) {
      final err = body?['error'];
      final code = err is String ? err : (err is Map ? err['code']?.toString() : null);
      debugPrint('[ChatGptSiwc] exchange failed status=${res.statusCode} code=$code');
      if (code == 'invalid_client') {
        throw SiwcException(SiwcFailure.server, code: code);
      }
      throw SiwcException(SiwcFailure.exchangeFailed, code: code);
    }
    return body;
  }

  // ── Server handoff ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _store({
    required Map<String, dynamic> tokens,
    required String clientId,
    required String grantedScope,
    required SiwcAttempt attempt,
  }) async {
    try {
      return await _storeOnce(tokens: tokens, clientId: clientId, grantedScope: grantedScope, attempt: attempt);
    } on SiwcException catch (e) {
      if (e.failure != SiwcFailure.network) rethrow;
      await Future<void>.delayed(const Duration(seconds: 1));
      return _storeOnce(tokens: tokens, clientId: clientId, grantedScope: grantedScope, attempt: attempt);
    }
  }

  Future<Map<String, dynamic>> _storeOnce({
    required Map<String, dynamic> tokens,
    required String clientId,
    required String grantedScope,
    required SiwcAttempt attempt,
  }) async {
    try {
      final res = await supabase.functions.invoke(
        'openai-link-siwc',
        method: HttpMethod.post,
        body: {
          'access_token': tokens['access_token'],
          'refresh_token': tokens['refresh_token'],
          'id_token': tokens['id_token'],
          'token_type': tokens['token_type'],
          'expires_in': tokens['expires_in'],
          'scope': grantedScope,
          'client_id': clientId,
          'nonce': attempt.nonce,
          'ext_agent_host_id': attempt.extAgentHostId,
        },
      );
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (data['status'] != 'connected') {
        throw _failureFromServer(data['error']?.toString());
      }
      return data;
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error']?.toString() : null;
      debugPrint('[ChatGptSiwc] store failed status=${e.status} code=$code');
      throw _failureFromServer(code);
    } on SiwcException {
      rethrow;
    } on TimeoutException {
      throw const SiwcException(SiwcFailure.network, code: 'store_timeout');
    } on SocketException {
      throw const SiwcException(SiwcFailure.network);
    } on http.ClientException {
      throw const SiwcException(SiwcFailure.network);
    }
  }

  static SiwcException _failureFromServer(String? code) => switch (code) {
    'not_eligible' => SiwcException(SiwcFailure.notEligible, code: code),
    'plan_scope_missing' => SiwcException(SiwcFailure.planNotEnabled, code: code),
    'invalid_id_token' => SiwcException(SiwcFailure.securityCheck, code: code),
    _ => SiwcException(SiwcFailure.server, code: code),
  };

  static String _hostId(SharedPreferences prefs) {
    final existing = prefs.getString(_prefsHostId);
    // Older builds saved a free-form `kynetix-…` id, which OpenAI rejects.
    if (SiwcHostId.isValid(existing)) return existing!;
    final id = SiwcHostId.generate();
    unawaited(prefs.setString(_prefsHostId, id));
    return id;
  }
}
