import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/kyno_context_service.dart';
import 'package:kynetix/services/kyno_progression_engine.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KynoProgressionEngine & KynoContextService Tests', () {
    test('KynoContextService returns a well-formed structured snapshot', () {
      final snapshot = KynoContextService.instance.getSnapshot(forceRefresh: true);

      expect(snapshot.profile, isNotNull);
      expect(snapshot.training, isNotNull);
      expect(snapshot.nutrition, isNotNull);
      expect(snapshot.crossDomain, isNotNull);
      expect(snapshot.structuredInsights, isNotEmpty);

      // Verify separation of concerns
      final types = snapshot.structuredInsights.map((i) => i.type).toSet();
      expect(types, contains(KynoInformationType.fact));
      expect(types, contains(KynoInformationType.calculation));
      expect(types, contains(KynoInformationType.inference));
      expect(types, contains(KynoInformationType.recommendation));
    });

    test('Progression Advice keeps load when ceiling has not been hit across all sets', () async {
      final ex = Exercise(
        id: 'bench_press',
        name: 'Flat Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
        defaultRepMin: 8,
        defaultRepMax: 10,
        defaultTargetSets: 4,
      );

      final entry = ExerciseEntry(
        exercise: ex,
        sets: const [
          SetEntry(weight: 70, reps: 9, setType: SetType.normal),
          SetEntry(weight: 70, reps: 7, setType: SetType.normal),
          SetEntry(weight: 70, reps: 7, setType: SetType.normal),
        ],
      );
      final session = WorkoutSession(
        id: 'ws_test_bench',
        date: DateTime.now().subtract(const Duration(days: 2)),
        splitDayName: 'Chest + Triceps',
        entries: [entry],
      );
      await WorkoutService.instance.saveSession(session);

      // Evaluate advice
      final advice = KynoProgressionEngine.instance.computeAdvice(
        exercise: ex,
        splitDayName: 'Chest + Triceps',
      );

      expect(advice.action, contains('KEEP'));
      expect(advice.styleLabel, equals('Double Progression'));
      expect(advice.todayTarget, isNotEmpty);
      expect(advice.summary, isNotEmpty);
      expect(advice.summary, isNot(contains('...')));
      expect(advice.nextMilestone, contains('10'));
      expect(advice.evidence, isNotEmpty);
    });
  });
}
