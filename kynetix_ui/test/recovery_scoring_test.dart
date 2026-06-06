import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/recovery_service.dart';

void main() {
  group('Recovery Service Configurable Sleep scoring', () {
    test('Sleep score is 1.0 within range 7.5 to 9.0 hours', () {
      const target = SleepTarget();
      expect(target.calculateScore(7.5), 1.0);
      expect(target.calculateScore(8.0), 1.0);
      expect(target.calculateScore(9.0), 1.0);
    });

    test('Sleep score declines linearly below minHours', () {
      const target = SleepTarget(minHours: 7.5, decayRate: 0.2);
      // diff = 7.5 - 6.5 = 1.0. Score = 1.0 - 1.0 * 0.2 = 0.8
      expect(target.calculateScore(6.5), closeTo(0.8, 0.001));
      // diff = 7.5 - 5.0 = 2.5. Score = 1.0 - 2.5 * 0.2 = 0.5
      expect(target.calculateScore(5.0), closeTo(0.5, 0.001));
    });

    test('Sleep score declines linearly above maxHours', () {
      const target = SleepTarget(maxHours: 9.0, decayRate: 0.2);
      // diff = 10.0 - 9.0 = 1.0. Score = 1.0 - 1.0 * 0.2 = 0.8
      expect(target.calculateScore(10.0), closeTo(0.8, 0.001));
    });

    test('Can configure custom SleepTarget ranges', () {
      const target = SleepTarget(minHours: 8.0, maxHours: 10.0, decayRate: 0.1);
      expect(target.calculateScore(9.0), 1.0);
      // diff = 8.0 - 6.0 = 2.0. Score = 1.0 - 2.0 * 0.1 = 0.8
      expect(target.calculateScore(6.0), closeTo(0.8, 0.001));
    });
  });

  group('Recovery Service HRV baseline scoring', () {
    test('HRV score is 1.0 when equal to or above baseline', () {
      const scorer = HrvScorer();
      expect(scorer.calculateScore(65.0, 60.0), 1.0);
      expect(scorer.calculateScore(60.0, 60.0), 1.0);
    });

    test('HRV score decreases proportionally when below baseline', () {
      const scorer = HrvScorer();
      expect(scorer.calculateScore(45.0, 60.0), closeTo(0.75, 0.001));
      expect(scorer.calculateScore(30.0, 60.0), closeTo(0.50, 0.001));
    });
  });

  group('Recovery Service Weight Redistribution', () {
    test('Overall readiness with muscle only (default fallback when sleep/HRV missing)', () {
      final input = RecoveryInput(
        sessions: [], // muscleScore defaults to 1.0
      );
      final report = RecoveryService.compute(input);
      expect(report.overallReadiness, 1.0);
      expect(report.sleepScore, isNull);
      expect(report.hrvScore, isNull);
    });

    test('Overall readiness with muscle and sleep, but no HRV', () {
      final input = RecoveryInput(
        sessions: [], // muscleScore = 1.0 (weight 0.4)
        sleepData: const SleepData(durationHours: 6.5), // score 0.8 (weight 0.3)
      );
      final report = RecoveryService.compute(input);
      // Weighted score = (1.0 * 0.4 + 0.8 * 0.3) / 0.7 = (0.4 + 0.24) / 0.7 = 0.64 / 0.7 = 0.91428...
      expect(report.overallReadiness, closeTo(0.914, 0.001));
      expect(report.sleepScore, closeTo(0.8, 0.001));
      expect(report.hrvScore, isNull);
    });

    test('Overall readiness with muscle, sleep, and HRV', () {
      final input = RecoveryInput(
        sessions: [], // muscleScore = 1.0 (weight 0.4)
        sleepData: const SleepData(durationHours: 6.5), // score 0.8 (weight 0.3)
        hrvData: const HrvData(rmssd: 45.0, baselineRmssd: 60.0), // score 0.75 (weight 0.3)
      );
      final report = RecoveryService.compute(input);
      // Weighted score = (1.0 * 0.4 + 0.8 * 0.3 + 0.75 * 0.3) / 1.0 = 0.4 + 0.24 + 0.225 = 0.865
      expect(report.overallReadiness, closeTo(0.865, 0.001));
      expect(report.sleepScore, closeTo(0.8, 0.001));
      expect(report.hrvScore, closeTo(0.75, 0.001));
    });
  });
}
