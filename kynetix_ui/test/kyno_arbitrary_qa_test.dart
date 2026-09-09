import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/kyno_context_service.dart';
import 'package:kynetix/services/kyno_historical_analysis_service.dart';
import 'package:kynetix/services/kyno_assistant_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSessionCoordinator.instance.clearAllUserServices();
    ProfileService.instance.currentUserProfile = const UserProfile(
      name: 'Test User',
      age: 26,
      gender: 'male',
      height: 175,
      weight: 75,
      workoutDaysMin: 3,
      workoutDaysMax: 4,
      goal: 'Strength & Hypertrophy',
    );
  });

  tearDown(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  group('Kyno Intent Classification & Arbitrary QA', () {
    test('Classifies body composition and belly fat queries correctly', () {
      final s = KynoHistoricalAnalysisService.instance;
      expect(s.classifyIntent('Why is my belly not reducing?'), KynoAnalysisIntent.bodyComposition);
      expect(s.classifyIntent('How do I lose stubborn belly fat?'), KynoAnalysisIntent.bodyComposition);
      expect(s.classifyIntent('Can I get abs by doing crunches?'), KynoAnalysisIntent.bodyComposition);
      expect(s.classifyIntent('Why is my waist not getting smaller?'), KynoAnalysisIntent.bodyComposition);
    });

    test('Classifies fat loss plateau queries correctly', () {
      final s = KynoHistoricalAnalysisService.instance;
      expect(s.classifyIntent('Why am I not losing weight?'), KynoAnalysisIntent.fatLossPlateau);
      expect(s.classifyIntent('My weight is stuck on the scale'), KynoAnalysisIntent.fatLossPlateau);
      expect(s.classifyIntent('Why is my weight plateauing?'), KynoAnalysisIntent.fatLossPlateau);
    });

    test('Classifies recovery queries correctly', () {
      final s = KynoHistoricalAnalysisService.instance;
      expect(s.classifyIntent('How is my recovery?'), KynoAnalysisIntent.recoveryAssessment);
      expect(s.classifyIntent('Am I recovering well?'), KynoAnalysisIntent.recoveryAssessment);
      expect(s.classifyIntent('Is my sleep and recovery enough?'), KynoAnalysisIntent.recoveryAssessment);
    });

    test('Classifies diet adjustment queries correctly', () {
      final s = KynoHistoricalAnalysisService.instance;
      expect(s.classifyIntent('What should I change in my diet?'), KynoAnalysisIntent.dietAdjustment);
      expect(s.classifyIntent('How can I adjust my meal plan?'), KynoAnalysisIntent.dietAdjustment);
      expect(s.classifyIntent('How can I fix my food intake?'), KynoAnalysisIntent.dietAdjustment);
    });

    test('Answers "Why is my belly not reducing?" with full epistemic structure', () async {
      final response = await KynoAssistantService.instance.processQuery('Why is my belly not reducing?');

      expect(response.structuredInsights, isNotNull);
      expect(response.structuredInsights!, isNotEmpty);

      // Verify direct answering headline
      expect(response.text.toLowerCase(), contains('spot reduction'));
      expect(response.text.toLowerCase(), contains('waist'));

      // Check epistemic categories
      final types = response.structuredInsights!.map((i) => i.type).toSet();
      expect(types, contains(KynoInformationType.fact));
      expect(types, contains(KynoInformationType.calculation));
      expect(types, contains(KynoInformationType.inference));
      expect(types, contains(KynoInformationType.recommendation));
      expect(types, contains(KynoInformationType.unknown));

      // Check explicit mention of untracked measurements
      final unknownInsight = response.structuredInsights!.firstWhere(
        (i) => i.type == KynoInformationType.unknown,
      );
      expect(unknownInsight.detail.toLowerCase(), contains('waist'));
      expect(unknownInsight.detail.toLowerCase(), contains('dexa'));
    });

    test('Answers "Why am I not losing weight?" with epistemic structure', () async {
      final response = await KynoAssistantService.instance.processQuery('Why am I not losing weight?');

      expect(response.structuredInsights, isNotNull);
      expect(response.structuredInsights!, isNotEmpty);
      final types = response.structuredInsights!.map((i) => i.type).toSet();
      expect(types, contains(KynoInformationType.fact));
      expect(types, contains(KynoInformationType.calculation));
      expect(types, contains(KynoInformationType.inference));
      expect(types, contains(KynoInformationType.recommendation));
      expect(types, contains(KynoInformationType.unknown));
    });

    test('Answers "How is my recovery?" with untracked sleep disclaimers', () async {
      final response = await KynoAssistantService.instance.processQuery('How is my recovery?');

      expect(response.structuredInsights, isNotNull);
      expect(response.structuredInsights!, isNotEmpty);
      final unknownInsight = response.structuredInsights!.firstWhere(
        (i) => i.type == KynoInformationType.unknown,
      );
      expect(unknownInsight.detail.toLowerCase(), contains('sleep'));
      expect(unknownInsight.detail.toLowerCase(), contains('hrv'));
    });

    test('Causal calibration: Strength plateau analysis does not claim direct proof', () {
      final response = KynoHistoricalAnalysisService.instance.analyzeQuery('Why am I plateauing on bench press?');

      // Epistemic calibration: Must NOT claim direct proof or direct explanation
      expect(response.headline.toLowerCase(), isNot(contains('directly explained')));
      expect(response.headline.toLowerCase(), isNot(contains('directly proves')));

      for (final insight in response.insights) {
        expect(insight.detail.toLowerCase(), isNot(contains('directly explained')));
        expect(insight.detail.toLowerCase(), isNot(contains('directly proves')));
      }
    });
  });
}
