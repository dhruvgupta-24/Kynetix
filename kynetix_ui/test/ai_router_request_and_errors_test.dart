import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/ai_coach_service.dart';
import 'package:kynetix/services/ai_nutrition_service.dart';
import 'package:kynetix/services/ai_router_error.dart';
import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/services/profile_service.dart';

/// Client side of the server-owned AI prompts: requests carry a `purpose`,
/// never a system message, and router errors become calm typed errors.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = UserProfile(
    name: 'Test',
    age: 25,
    gender: 'male',
    height: 175,
    weight: 70,
    goal: 'Fat Loss',
    workoutDaysMin: 3,
    workoutDaysMax: 4,
    portionAnchor: PortionAnchor.curryAnchored,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  tearDown(() => ProfileService.instance.currentUserProfile = null);

  bool hasSystemMessage(Map<String, dynamic> body) =>
      (body['messages'] as List).any((m) => (m as Map)['role'] == 'system');

  group('request bodies', () {
    test('meal estimate: purpose, anchor enum name, user message only', () {
      ProfileService.instance.currentUserProfile = profile;
      final body = AiNutritionService.instance.buildRequestBody('2 roti and dal');
      expect(body['purpose'], 'meal_estimate');
      expect(body['portion_anchor'], 'curryAnchored');
      expect(hasSystemMessage(body), isFalse);
      final messages = body['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages.single as Map)['role'], 'user');
      expect((messages.single as Map)['content'] as String, contains('2 roti and dal'));
    });

    test('meal estimate without an anchor omits portion_anchor', () {
      ProfileService.instance.currentUserProfile = null;
      final body = AiNutritionService.instance.buildRequestBody('poha');
      expect(body.containsKey('portion_anchor'), isFalse);
      expect(body['purpose'], 'meal_estimate');
      expect(hasSystemMessage(body), isFalse);
    });

    test('meal estimate carries the whole meal only when mealContext is given', () {
      ProfileService.instance.currentUserProfile = null;
      String content(Map<String, dynamic> body) =>
          ((body['messages'] as List).single as Map)['content'] as String;
      const base = AiEscalationContext(
        localInterpretation: 'dal',
        localMatchConfidence: 0.5,
        localCoverageConfidence: 0.5,
        overallLocalConfidence: 0.5,
      );
      expect(content(AiNutritionService.instance.buildRequestBody('dal', context: base)),
          isNot(contains('Whole meal as typed')));
      const withMeal = AiEscalationContext(
        localInterpretation: 'dal',
        localMatchConfidence: 0.5,
        localCoverageConfidence: 0.5,
        overallLocalConfidence: 0.5,
        mealContext: '3 roti, 1 ladle rice and dal',
      );
      final text = content(AiNutritionService.instance.buildRequestBody('dal', context: withMeal));
      expect(text, contains('Whole meal as typed: "3 roti, 1 ladle rice and dal"'));
      expect(text, contains('Return exactly one item, for "dal" only.'));
    });

    test('weekly summary: purpose and user message only', () {
      final body = InsightsReportService.weeklySummaryRequestBody('Weekly Report Data: x');
      expect(body['purpose'], 'weekly_summary');
      expect(hasSystemMessage(body), isFalse);
      expect(body['messages'], [
        {'role': 'user', 'content': 'Weekly Report Data: x'},
      ]);
    });

    test('coach: portion_anchor is the enum name, no legacy hint text', () {
      ProfileService.instance.currentUserProfile = profile;
      final body = <String, dynamic>{'message': 'hi'};
      AiCoachService.addPortionAnchor(body);
      expect(body['portion_anchor'], 'curryAnchored');
      expect(body.containsKey('portion_anchor_hint'), isFalse);

      ProfileService.instance.currentUserProfile = null;
      final empty = <String, dynamic>{};
      AiCoachService.addPortionAnchor(empty);
      expect(empty, isEmpty);
    });
  });

  group('router error mapping', () {
    test('429 minute', () {
      final e = AiRouterException.from(const FunctionException(
        status: 429,
        details: {'success': false, 'error': 'rate_limited', 'retry_after': 42, 'scope': 'minute'},
      ));
      expect(e.kind, AiRouterErrorKind.rateLimitedMinute);
      expect(e.retryAfterSeconds, 42);
      expect(e.statusCode, 429);
      expect(e.userMessage, "You're going fast. Try again in a minute.");
    });

    test('429 day', () {
      final e = AiRouterException.fromResponse(
          429, '{"error":"rate_limited","retry_after":3600,"scope":"day"}');
      expect(e.kind, AiRouterErrorKind.rateLimitedDay);
      expect(e.userMessage, "That's today's AI limit. It resets tomorrow.");
    });

    test('413 too long or too many images', () {
      for (final code in ['too_many_chars', 'too_many_images', 'image_too_large']) {
        final e = AiRouterException.fromResponse(
            413, {'error': code, 'message': 'raw server text'});
        expect(e.kind, AiRouterErrorKind.tooLarge);
        expect(e.userMessage,
            "That's a bit too long. Try a shorter message or fewer photos.");
        expect(e.userMessage, isNot(contains('raw server text')));
      }
    });

    test('400 unknown_purpose and anything else are generic', () {
      final e = AiRouterException.fromResponse(400, {'error': 'unknown_purpose'});
      expect(e.kind, AiRouterErrorKind.generic);
      expect(AiRouterException.from(Exception('socket')).kind, AiRouterErrorKind.generic);
      expect(AiRouterException.fromResponse(502, '<html>bad gateway</html>').kind,
          AiRouterErrorKind.generic);
      expect(e.userMessage, isNot(contains('unknown_purpose')));
    });
  });
}
