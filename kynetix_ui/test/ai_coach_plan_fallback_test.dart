import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/ai_coach_service.dart';

void main() {
  group('AiCoachService plan fallback reason', () {
    test('cleanFallbackReason trims and drops empty values', () {
      expect(AiCoachService.cleanFallbackReason(' usage_limit '), 'usage_limit');
      expect(AiCoachService.cleanFallbackReason(''), isNull);
      expect(AiCoachService.cleanFallbackReason('   '), isNull);
      expect(AiCoachService.cleanFallbackReason(null), isNull);
      expect(AiCoachService.cleanFallbackReason(42), isNull);
    });

    test('AiCoachResponse reads plan_fallback_reason from the body', () {
      final r = AiCoachResponse.fromJson({
        'message': 'hi',
        'provider_used': 'openrouter',
        'fallback_used': false,
        'plan_fallback_reason': 'not_eligible',
      });
      expect(r.planFallbackReason, 'not_eligible');
      expect(r.providerUsed, 'openrouter');
    });

    test('AiCoachResponse keeps planFallbackReason null when absent', () {
      final r = AiCoachResponse.fromJson({
        'message': 'hi',
        'provider_used': 'openai',
        'fallback_used': false,
      });
      expect(r.planFallbackReason, isNull);
      expect(r.message, 'hi');
    });

    test('the shared notifier starts empty', () {
      expect(AiCoachService.instance.planFallbackReason.value, isNull);
    });
  });
}
