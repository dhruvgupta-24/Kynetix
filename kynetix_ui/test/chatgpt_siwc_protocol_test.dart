import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/chatgpt_siwc_protocol.dart';

String _fakeJwt(Map<String, dynamic> payload) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(payload)}.sig';
}

SiwcAttempt _attempt({String clientId = SiwcConfig.dynamicClientId}) =>
    SiwcAttempt(
      clientId: clientId,
      redirectUri: SiwcConfig.redirectUriFor(1455),
      extAgentHostId: 'urn:uuid:3f1c2a9e-7b4d-4e2a-9c1f-0a2b3c4d5e6f',
      verifier: 'v' * 43,
      state: 'state-abc',
      nonce: 'nonce-xyz',
    );

Uri _cb(Map<String, String> q) =>
    Uri.parse('http://127.0.0.1:1455/auth/callback').replace(queryParameters: q);

void main() {
  group('PKCE', () {
    test('verifier length and charset follow RFC 7636', () {
      for (var i = 0; i < 50; i++) {
        final v = ChatGptPkce.generateVerifier();
        expect(v.length, inInclusiveRange(43, 128));
        expect(ChatGptPkce.verifierPattern.hasMatch(v), isTrue, reason: v);
        expect(v.contains('='), isFalse);
      }
    });

    test('S256 challenge matches the RFC 7636 Appendix B vector', () {
      expect(
        ChatGptPkce.challengeS256('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('challenge is unpadded base64url of 32 bytes', () {
      final c = ChatGptPkce.challengeS256(ChatGptPkce.generateVerifier());
      expect(c.length, 43);
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(c), isTrue);
    });

    test('state and nonce are random, url-safe and long enough', () {
      final states = {for (var i = 0; i < 200; i++) ChatGptPkce.generateState()};
      final nonces = {for (var i = 0; i < 200; i++) ChatGptPkce.generateNonce()};
      expect(states.length, 200);
      expect(nonces.length, 200);
      expect(states.intersection(nonces), isEmpty);
      for (final s in [...states.take(5), ...nonces.take(5)]) {
        expect(s.length, greaterThanOrEqualTo(43));
        expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(s), isTrue);
      }
    });

    test('seeded generator is deterministic (randomness comes from the RNG)', () {
      expect(
        ChatGptPkce.generateVerifier(random: Random(7)),
        ChatGptPkce.generateVerifier(random: Random(7)),
      );
    });

    test('each attempt gets fresh secrets', () {
      final a = SiwcAttempt(clientId: 'x', redirectUri: 'r', extAgentHostId: 'h');
      final b = SiwcAttempt(clientId: 'x', redirectUri: 'r', extAgentHostId: 'h');
      expect(a.verifier, isNot(b.verifier));
      expect(a.state, isNot(b.state));
      expect(a.nonce, isNot(b.nonce));
    });
  });

  group('authorize URL', () {
    test('registration carries every required parameter', () {
      final a = _attempt();
      final q = a.authorizeUri().queryParameters;
      expect(a.authorizeUri().toString(), startsWith(SiwcConfig.authorizeUrl));
      expect(q['client_id'], 'dynamic_agent_client');
      expect(q['agent_name_hint'], 'Kynetix');
      expect(q['ext_agent_host_id'], 'urn:uuid:3f1c2a9e-7b4d-4e2a-9c1f-0a2b3c4d5e6f');
      expect(q['response_type'], 'code');
      expect(q['redirect_uri'], 'http://127.0.0.1:1455/auth/callback');
      expect(q['scope'], SiwcConfig.scopes);
      expect(q['scope']!.split(' '), contains('chatgpt.tokens.use.direct'));
      expect(q['resource'], 'https://api.openai.com/v1');
      expect(q['state'], 'state-abc');
      expect(q['nonce'], 'nonce-xyz');
      expect(q['code_challenge_method'], 'S256');
      expect(q['code_challenge'], ChatGptPkce.challengeS256('v' * 43));
    });

    test('reauthorization reuses the issued id and drops agent_name_hint', () {
      final q = _attempt(clientId: 'oaiapp_123').authorizeUri().queryParameters;
      expect(q['client_id'], 'oaiapp_123');
      expect(q.containsKey('agent_name_hint'), isFalse);
    });

    test('redirect uses 127.0.0.1, never localhost; only the port varies', () {
      expect(SiwcConfig.redirectUriFor(1455), 'http://127.0.0.1:1455/auth/callback');
      expect(SiwcConfig.redirectUriFor(51234), 'http://127.0.0.1:51234/auth/callback');
      expect(SiwcConfig.redirectUriFor(1455).contains('localhost'), isFalse);
    });
  });

  group('callback parsing', () {
    test('registration success returns the issued client id', () {
      final r = SiwcCallbackParser.parse(
        _cb({
          'code': 'c1',
          'state': 'state-abc',
          'client_id': 'oaiapp_new',
          'scope': 'openid chatgpt.tokens.use.direct',
        }),
        _attempt(),
      );
      expect(r.outcome, SiwcCallbackOutcome.success);
      expect(r.code, 'c1');
      expect(r.clientId, 'oaiapp_new');
      expect(SiwcTokens.hasPlanScope(r.grantedScope), isTrue);
    });

    test('state mismatch is rejected before anything else', () {
      final r = SiwcCallbackParser.parse(
        _cb({'code': 'c1', 'state': 'other', 'client_id': 'oaiapp_new'}),
        _attempt(),
      );
      expect(r.outcome, SiwcCallbackOutcome.stateMismatch);
      expect(r.code, isNull);
    });

    test('missing state is rejected', () {
      final r = SiwcCallbackParser.parse(_cb({'code': 'c1'}), _attempt());
      expect(r.outcome, SiwcCallbackOutcome.stateMismatch);
    });

    test('access_denied with valid state is a clean denial', () {
      final r = SiwcCallbackParser.parse(
        _cb({'error': 'access_denied', 'state': 'state-abc'}),
        _attempt(),
      );
      expect(r.outcome, SiwcCallbackOutcome.denied);
    });

    test('access_denied with a forged state is still a state mismatch', () {
      final r = SiwcCallbackParser.parse(
        _cb({'error': 'access_denied', 'state': 'forged'}),
        _attempt(),
      );
      expect(r.outcome, SiwcCallbackOutcome.stateMismatch);
    });

    test('other OAuth errors are surfaced', () {
      final r = SiwcCallbackParser.parse(
        _cb({'error': 'invalid_client', 'state': 'state-abc'}),
        _attempt(clientId: 'oaiapp_1'),
      );
      expect(r.outcome, SiwcCallbackOutcome.error);
      expect(r.error, 'invalid_client');
    });

    test('registration without an issued client id is incomplete', () {
      expect(
        SiwcCallbackParser.parse(_cb({'code': 'c', 'state': 'state-abc'}), _attempt())
            .outcome,
        SiwcCallbackOutcome.missingClientId,
      );
      expect(
        SiwcCallbackParser.parse(
          _cb({'code': 'c', 'state': 'state-abc', 'client_id': 'dynamic_agent_client'}),
          _attempt(),
        ).outcome,
        SiwcCallbackOutcome.missingClientId,
      );
    });

    test('reauthorization may omit client_id but must not change it', () {
      final kept = SiwcCallbackParser.parse(
        _cb({'code': 'c', 'state': 'state-abc'}),
        _attempt(clientId: 'oaiapp_1'),
      );
      expect(kept.outcome, SiwcCallbackOutcome.success);
      expect(kept.clientId, 'oaiapp_1');

      final changed = SiwcCallbackParser.parse(
        _cb({'code': 'c', 'state': 'state-abc', 'client_id': 'oaiapp_2'}),
        _attempt(clientId: 'oaiapp_1'),
      );
      expect(changed.outcome, SiwcCallbackOutcome.clientIdMismatch);
    });

    test('missing code is reported', () {
      final r = SiwcCallbackParser.parse(
        _cb({'state': 'state-abc', 'client_id': 'oaiapp_new'}),
        _attempt(),
      );
      expect(r.outcome, SiwcCallbackOutcome.missingCode);
    });
  });

  group('tokens', () {
    test('plan scope detection', () {
      expect(SiwcTokens.hasPlanScope('openid email chatgpt.tokens.use.direct'), isTrue);
      expect(SiwcTokens.hasPlanScope('openid+chatgpt.tokens.use.direct'), isTrue);
      expect(SiwcTokens.hasPlanScope('openid email resource.invoke'), isFalse);
      expect(SiwcTokens.hasPlanScope('chatgpt.tokens.use.directX'), isFalse);
      expect(SiwcTokens.hasPlanScope(null), isFalse);
    });

    test('ID-token nonce check', () {
      final jwt = _fakeJwt({'sub': 'u1', 'nonce': 'nonce-xyz'});
      expect(SiwcTokens.idTokenNonceMatches(jwt, 'nonce-xyz'), isTrue);
      expect(SiwcTokens.idTokenNonceMatches(jwt, 'other'), isFalse);
      expect(SiwcTokens.idTokenNonceMatches(null, 'nonce-xyz'), isFalse);
      expect(SiwcTokens.idTokenNonceMatches('not.a.jwt!', 'nonce-xyz'), isFalse);
      expect(SiwcTokens.peekJwtPayload('only-one-part'), isNull);
    });
  });

  test('callback page is self-contained and points back to the app', () {
    final ok = siwcCallbackPage(ok: true);
    final denied = siwcCallbackPage(ok: false);
    expect(ok, contains('You can return to Kynetix'));
    expect(ok, contains('kynetix://openai-auth/callback'));
    expect(ok, contains('prefers-color-scheme'));
    expect(denied, contains('Nothing was connected'));
    expect(ok.contains('<script'), isFalse);
  });

  group('SiwcHostId', () {
    test('generates urn:uuid v4 values OpenAI accepts', () {
      final ids = {for (var i = 0; i < 200; i++) SiwcHostId.generate()};
      expect(ids.length, 200);
      for (final id in ids) {
        expect(SiwcHostId.isValid(id), isTrue, reason: id);
      }
    });

    test('rejects the free-form ids older builds saved', () {
      expect(SiwcHostId.isValid('kynetix-BHwKdaHqXbZ3aDRwaTxP4A'), isFalse);
      expect(SiwcHostId.isValid(null), isFalse);
      expect(SiwcHostId.isValid(''), isFalse);
    });
  });
}
