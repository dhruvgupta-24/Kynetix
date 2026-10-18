// Sign in with ChatGPT (plan usage): pure protocol helpers.
//
// No I/O lives here, so everything is unit-testable: PKCE (RFC 7636, S256),
// attempt randomness (state / nonce), the authorize URL, loopback callback
// parsing and validation, and a payload-only ID-token peek used for the
// on-device nonce check. Full ID-token verification (JWKS signature, issuer,
// audience, expiry, nonce) happens server-side in `openai-link-siwc`.
//
// Docs: https://developers.openai.com/siwc/token-sharing-open-source/sign-in

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Fixed protocol values for the official "Sign in with ChatGPT" flow.
abstract final class SiwcConfig {
  static const authorizeUrl = 'https://auth.openai.com/api/accounts/authorize';
  static const tokenUrl = 'https://auth.openai.com/api/accounts/oauth/token';
  static const resource = 'https://api.openai.com/v1';

  /// First-time registration client. The callback hands back the issued
  /// `oaiapp_…` client id, which is saved and reused afterwards.
  static const dynamicClientId = 'dynamic_agent_client';
  static const agentNameHint = 'Kynetix';

  static const scopes =
      'openid profile email offline_access resource.invoke '
      'chatgpt.tokens.use.direct';

  /// Without this scope the sign-in worked but plan usage is off.
  static const planScope = 'chatgpt.tokens.use.direct';

  /// Loopback redirect. Only the port may change between attempts; the
  /// scheme, host (127.0.0.1, never "localhost") and path stay fixed.
  static const loopbackHost = '127.0.0.1';
  static const preferredPort = 1455;
  static const callbackPath = '/auth/callback';

  static const manageUsageUrl = 'https://chatgpt.com/settings/usage';

  /// How long we wait for the browser to come back.
  static const callbackTimeout = Duration(minutes: 5);

  static String redirectUriFor(int port) =>
      'http://$loopbackHost:$port$callbackPath';
}

/// PKCE + attempt randomness.
abstract final class ChatGptPkce {
  /// RFC 7636 §4.1 unreserved characters.
  static final RegExp verifierPattern = RegExp(r'^[A-Za-z0-9\-._~]{43,128}$');

  static final Random _secure = Random.secure();

  /// [byteLength] random bytes, base64url-encoded without padding.
  static String randomUrlSafe(int byteLength, {Random? random}) {
    final rng = random ?? _secure;
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    return _b64UrlNoPad(bytes);
  }

  /// 64 random bytes -> an 86-char verifier (within the 43..128 range).
  static String generateVerifier({Random? random}) =>
      randomUrlSafe(64, random: random);

  /// `BASE64URL(SHA256(ASCII(verifier)))`, no padding.
  static String challengeS256(String verifier) =>
      _b64UrlNoPad(sha256.convert(ascii.encode(verifier)).bytes);

  static String generateState({Random? random}) =>
      randomUrlSafe(32, random: random);

  static String generateNonce({Random? random}) =>
      randomUrlSafe(32, random: random);

  static String _b64UrlNoPad(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}

/// The per-install `ext_agent_host_id`. OpenAI rejects free-form values
/// ("Invalid authorize request", param ext_agent_host_id): it must be a
/// UUIDv4 prefixed with `urn:uuid:` (or a JWK-thumbprint / did:key URI).
abstract final class SiwcHostId {
  static final RegExp _urnUuid = RegExp(
    r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isValid(String? id) => id != null && _urnUuid.hasMatch(id);

  /// A fresh `urn:uuid:` UUIDv4 (RFC 9562 §5.4).
  static String generate({Random? random}) {
    final rng = random ?? Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // RFC variant
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// One sign-in attempt's secrets. Fresh per attempt, never persisted.
class SiwcAttempt {
  SiwcAttempt({
    required this.clientId,
    required this.redirectUri,
    required this.extAgentHostId,
    String? verifier,
    String? state,
    String? nonce,
  }) : verifier = verifier ?? ChatGptPkce.generateVerifier(),
       state = state ?? ChatGptPkce.generateState(),
       nonce = nonce ?? ChatGptPkce.generateNonce();

  /// `dynamic_agent_client` on first registration, else the issued id.
  final String clientId;
  final String redirectUri;
  final String extAgentHostId;
  final String verifier;
  final String state;
  final String nonce;

  bool get isRegistration => clientId == SiwcConfig.dynamicClientId;

  String get challenge => ChatGptPkce.challengeS256(verifier);

  Uri authorizeUri() {
    final params = <String, String>{
      'client_id': clientId,
      if (isRegistration) 'agent_name_hint': SiwcConfig.agentNameHint,
      'ext_agent_host_id': extAgentHostId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': SiwcConfig.scopes,
      'resource': SiwcConfig.resource,
      'state': state,
      'nonce': nonce,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
    };
    return Uri.parse(SiwcConfig.authorizeUrl).replace(queryParameters: params);
  }
}

enum SiwcCallbackOutcome {
  /// Code + matching state (+ issued client id on registration).
  success,

  /// User said no on the consent screen.
  denied,

  /// State didn't match this attempt. Never exchange the code.
  stateMismatch,

  /// Another OAuth error came back (see [SiwcCallbackResult.error]).
  error,

  /// No authorization code in an otherwise clean callback.
  missingCode,

  /// New registration without an issued client id: registration incomplete.
  missingClientId,

  /// Reauthorization returned a different client id than we asked with.
  clientIdMismatch,
}

class SiwcCallbackResult {
  const SiwcCallbackResult(
    this.outcome, {
    this.code,
    this.clientId,
    this.grantedScope,
    this.error,
  });

  final SiwcCallbackOutcome outcome;
  final String? code;

  /// The client id to use for the exchange and to save.
  final String? clientId;

  /// Scopes from the callback, if present (the token response is checked too).
  final String? grantedScope;
  final String? error;

  bool get isSuccess => outcome == SiwcCallbackOutcome.success;
}

abstract final class SiwcCallbackParser {
  /// Validates a loopback callback against the pending [attempt].
  ///
  /// State is checked first, even for errors, per the docs ("validate state,
  /// stop, and do not exchange the code").
  static SiwcCallbackResult parse(Uri uri, SiwcAttempt attempt) {
    final q = uri.queryParameters;
    final state = q['state'];
    if (state == null || state.isEmpty || !_constantTimeEquals(state, attempt.state)) {
      return const SiwcCallbackResult(SiwcCallbackOutcome.stateMismatch);
    }

    final error = q['error'];
    if (error != null && error.isNotEmpty) {
      return SiwcCallbackResult(
        error == 'access_denied'
            ? SiwcCallbackOutcome.denied
            : SiwcCallbackOutcome.error,
        error: error,
      );
    }

    final code = q['code'];
    if (code == null || code.isEmpty) {
      return const SiwcCallbackResult(SiwcCallbackOutcome.missingCode);
    }

    final returnedClientId = q['client_id'];
    final String clientId;
    if (attempt.isRegistration) {
      if (returnedClientId == null ||
          returnedClientId.isEmpty ||
          returnedClientId == SiwcConfig.dynamicClientId) {
        return const SiwcCallbackResult(SiwcCallbackOutcome.missingClientId);
      }
      clientId = returnedClientId;
    } else {
      if (returnedClientId != null &&
          returnedClientId.isNotEmpty &&
          returnedClientId != attempt.clientId) {
        return const SiwcCallbackResult(SiwcCallbackOutcome.clientIdMismatch);
      }
      clientId = attempt.clientId;
    }

    return SiwcCallbackResult(
      SiwcCallbackOutcome.success,
      code: code,
      clientId: clientId,
      grantedScope: q['scope'],
    );
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

abstract final class SiwcTokens {
  /// True when the space-separated [scope] includes plan usage.
  static bool hasPlanScope(String? scope) {
    if (scope == null) return false;
    return scope
        .split(RegExp(r'[\s+]+'))
        .contains(SiwcConfig.planScope);
  }

  /// Decodes a JWT payload WITHOUT verifying it. Only used for the on-device
  /// nonce check; the server verifies the signature.
  static Map<String, dynamic>? peekJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  static bool idTokenNonceMatches(String? idToken, String nonce) {
    if (idToken == null || idToken.isEmpty) return false;
    final payload = peekJwtPayload(idToken);
    return payload != null && payload['nonce'] == nonce;
  }
}

/// The small page the loopback listener serves once the browser comes back.
/// Self-contained, follows the system theme, and offers a way back to the app.
String siwcCallbackPage({required bool ok}) {
  final title = ok ? "You're signed in." : 'Sign-in stopped.';
  final body = ok
      ? 'You can return to Kynetix. Kyno is finishing the setup.'
      : 'Nothing was connected. You can return to Kynetix and try again.';
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kynetix</title>
<style>
:root{--bg:#FAF7F1;--card:#FFFFFF;--fg:#141414;--muted:#5C5852;--line:rgba(20,20,20,.1);--ink:#141414;--on-ink:#FAF7F1}
@media (prefers-color-scheme:dark){:root{--bg:#000;--card:#0F0F0F;--fg:#F5F2EC;--muted:#A19D96;--line:rgba(245,242,236,.12);--ink:#F5F2EC;--on-ink:#0A0A0A}}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:var(--bg);color:var(--fg);font:16px/1.5 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif;padding:24px}
main{max-width:380px;width:100%;background:var(--card);border:1px solid var(--line);border-radius:28px;padding:32px 24px;text-align:left}
.mark{width:44px;height:44px;border-radius:14px;background:var(--ink);color:var(--on-ink);display:flex;align-items:center;justify-content:center;font-weight:800;font-size:20px;margin-bottom:20px}
h1{font-size:24px;line-height:1.2;letter-spacing:-.02em;margin:0 0 8px}
p{color:var(--muted);margin:0 0 24px}
a.btn{display:flex;align-items:center;justify-content:center;min-height:52px;border-radius:999px;background:var(--ink);color:var(--on-ink);text-decoration:none;font-weight:700}
small{display:block;margin-top:16px;color:var(--muted);text-align:center}
</style></head>
<body><main>
<div class="mark" aria-hidden="true">K</div>
<h1>$title</h1>
<p>$body</p>
<a class="btn" href="kynetix://openai-auth/callback">Back to Kynetix</a>
<small>You can close this tab.</small>
</main></body></html>''';
}
