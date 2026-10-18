import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/ai_coach_screen.dart';

/// The coach backend now enforces limits (429 per minute or per day, 413 for
/// too long or too many photos). The screen must show calm copy for each,
/// never the raw status line or response body.
class _TypedError implements Exception {
  _TypedError(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'AiCoachError($statusCode): $body';
}

void main() {
  group('aiCoachFriendlyError', () {
    test('429 per-minute limit', () {
      final msg = aiCoachFriendlyError(
          Exception('ai-meal-coach 429: {"error":"rate_limited","window":"minute"}'));
      expect(msg, contains('in a minute'));
      expect(msg, isNot(contains('429')));
    });

    test('429 daily limit', () {
      final msg = aiCoachFriendlyError(
          Exception('ai-meal-coach 429: {"error":"rate_limited","window":"day"}'));
      expect(msg, contains("today's limit"));
    });

    test('413 too many photos', () {
      final msg = aiCoachFriendlyError(
          Exception('ai-meal-coach 413: {"error":"too_many_images"}'));
      expect(msg, contains('photos'));
      expect(msg, isNot(contains('413')));
    });

    test('413 message too long', () {
      final msg = aiCoachFriendlyError(
          Exception('ai-meal-coach 413: {"error":"payload_too_large"}'));
      expect(msg, contains('too long'));
    });

    test('typed error with statusCode is read too', () {
      expect(aiCoachFriendlyError(_TypedError(429, 'minute')), contains('in a minute'));
      expect(aiCoachFriendlyError(_TypedError(413, 'too many images')), contains('photos'));
    });

    test('other failures keep their existing copy', () {
      expect(aiCoachFriendlyError(Exception('Not authenticated')), contains('signed out'));
      expect(aiCoachFriendlyError(Exception('SocketException: failed')), contains('connection'));
      expect(aiCoachFriendlyError(Exception('ai-meal-coach 500: boom')),
          "That didn't go through. Try again in a moment.");
    });
  });
}
