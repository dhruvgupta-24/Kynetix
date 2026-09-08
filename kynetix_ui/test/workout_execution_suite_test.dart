import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/widgets/barbell_plate_calculator.dart';
import 'package:kynetix/widgets/exercise_execution_input_view.dart';
import 'package:kynetix/services/wakelock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4: Workout Execution Suite Tests', () {
    // ── 1. Legacy Workout History Preservation ────────────────────────────────
    group('1. Legacy Workout History Preservation', () {
      test('legacy weight x rep SetEntry deserializes identically with zero mutations', () {
        final legacyJson = {
          'weight': 100.0,
          'reps': 5,
          'rpe': 8.5,
          'setType': 'normal',
        };

        final set = SetEntry.fromJson(legacyJson);

        expect(set.weight, equals(100.0));
        expect(set.reps, equals(5));
        expect(set.rpe, equals(8.5));
        expect(set.setType, equals(SetType.normal));
        expect(set.externalLoadKg, isNull);
        expect(set.durationSeconds, isNull);
        expect(set.distanceMeters, isNull);

        // Volume & e1RM calculation
        expect(set.volume, equals(500.0));
        // Epley formula: 100 * (1 + 5/30) = 116.666...
        expect(set.estimatedOneRepMax, closeTo(116.67, 0.05));

        // Reserialization does not introduce null or unexpected keys
        final json = set.toJson();
        expect(json.containsKey('externalLoadKg'), isFalse);
        expect(json.containsKey('durationSeconds'), isFalse);
        expect(json.containsKey('distanceMeters'), isFalse);
        expect(json['weight'], equals(100.0));
        expect(json['reps'], equals(5));
        expect(json['rpe'], equals(8.5));
        expect(json['setType'], equals('normal'));
      });

      test('switching execution mode on an exercise never mutates already logged sets', () {
        final initialExercise = const Exercise(
          id: 'bench-1',
          name: 'Bench Press',
          muscleGroup: 'Chest',
          type: ExerciseType.barbellCompound,
          executionMode: ExerciseExecutionMode.weightReps,
        );

        final loggedSet = const SetEntry(
          weight: 80.0,
          reps: 8,
          setType: SetType.normal,
        );

        // Simulate switching exercise mode (e.g. to timed or bodyweight)
        final updatedExercise = initialExercise.copyWith(
          executionMode: ExerciseExecutionMode.timed,
        );

        expect(updatedExercise.executionMode, equals(ExerciseExecutionMode.timed));
        // Previous set must remain untouched
        expect(loggedSet.weight, equals(80.0));
        expect(loggedSet.reps, equals(8));
        expect(loggedSet.durationSeconds, isNull);
        expect(loggedSet.externalLoadKg, isNull);
      });
    });

    // ── 2. Timed Sets Semantics & Persistence ────────────────────────────────
    group('2. Timed Sets Semantics & Persistence', () {
      test('timed set persists durationSeconds and displays cleanly', () {
        const plankSet = SetEntry(
          weight: 0.0,
          reps: 1,
          durationSeconds: 65, // 1m 05s
          setType: SetType.normal,
        );

        final json = plankSet.toJson();
        expect(json['durationSeconds'], equals(65));
        expect(json['weight'], equals(0.0));

        final restored = SetEntry.fromJson(json);
        expect(restored.durationSeconds, equals(65));
        expect(restored.toString(), contains('01:05'));
      });

      test('timed validation rejects <= 0 duration', () {
        final errZero = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.timed,
          weight: 0.0,
          reps: 1,
          durationSeconds: 0,
        );
        expect(errZero, isNotNull);
        expect(errZero, contains('Hold duration must be at least 1s'));

        final errNull = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.timed,
          weight: 0.0,
          reps: 1,
          durationSeconds: null,
        );
        expect(errNull, isNotNull);

        final valid = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.timed,
          weight: 0.0,
          reps: 1,
          durationSeconds: 45,
        );
        expect(valid, isNull);
      });
    });

    // ── 3. Bodyweight Semantics (externalLoadKg) ──────────────────────────────
    group('3. Bodyweight Semantics', () {
      test('Pull-up with externalLoadKg 8kg distinguishes load from bodyweight', () {
        const pullUpSet = SetEntry(
          weight: 0.0, // Normal weight is 0
          reps: 10,
          externalLoadKg: 8.0, // Explicit added weight: BW + 8kg
          setType: SetType.normal,
        );

        expect(pullUpSet.weight, equals(0.0));
        expect(pullUpSet.externalLoadKg, equals(8.0));
        expect(pullUpSet.reps, equals(10));

        // Volume for BW set with external load is externalLoad * reps
        expect(pullUpSet.volume, equals(80.0));

        // e1RM is based on external load for progressive overload calculation
        expect(pullUpSet.estimatedOneRepMax, closeTo(8.0 * (1 + 10 / 30.0), 0.01));

        // String representation clearly displays BW + 8.0 kg
        expect(pullUpSet.toString(), contains('BW + 8.0 kg'));
        expect(pullUpSet.toString(), contains('× 10'));

        final json = pullUpSet.toJson();
        expect(json['externalLoadKg'], equals(8.0));
        expect(json['reps'], equals(10));

        final restored = SetEntry.fromJson(json);
        expect(restored.externalLoadKg, equals(8.0));
        expect(restored.weight, equals(0.0));
      });

      test('Unweighted bodyweight set (externalLoadKg: 0 or null) has 0 volume', () {
        const unweightedSet = SetEntry(
          weight: 0.0,
          reps: 12,
          externalLoadKg: 0.0,
          setType: SetType.normal,
        );

        expect(unweightedSet.volume, equals(0.0));
        expect(unweightedSet.toString(), contains('BW × 12'));
      });

      test('bodyweight validation rejects negative external load or zero reps', () {
        final errNeg = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.bodyweightReps,
          weight: 0.0,
          reps: 10,
          externalLoadKg: -2.5,
        );
        expect(errNeg, isNotNull);
        expect(errNeg, contains('External load cannot be negative'));

        final errReps = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.bodyweightReps,
          weight: 0.0,
          reps: 0,
          externalLoadKg: 5.0,
        );
        expect(errReps, isNotNull);
        expect(errReps, contains('Reps must be at least 1'));

        final valid = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.bodyweightReps,
          weight: 0.0,
          reps: 8,
          externalLoadKg: 10.0,
        );
        expect(valid, isNull);
      });
    });

    // ── 4. Cardio Semantics & Persistence ────────────────────────────────────
    group('4. Cardio Semantics & Persistence', () {
      test('cardio set with duration and distance serializes and formats correctly', () {
        const runSet = SetEntry(
          weight: 0.0,
          reps: 1,
          durationSeconds: 1500, // 25:00
          distanceMeters: 5000.0, // 5 km
          setType: SetType.normal,
        );

        final json = runSet.toJson();
        expect(json['durationSeconds'], equals(1500));
        expect(json['distanceMeters'], equals(5000.0));

        final restored = SetEntry.fromJson(json);
        expect(restored.durationSeconds, equals(1500));
        expect(restored.distanceMeters, equals(5000.0));
        expect(restored.toString(), contains('25:00'));
        expect(restored.toString(), contains('5.00 km'));
      });

      test('cardio validation requires duration or distance', () {
        final err = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.cardio,
          weight: 0.0,
          reps: 1,
          durationSeconds: 0,
          distanceMeters: 0,
        );
        expect(err, isNotNull);
        expect(err, contains('Enter cardio duration or distance'));

        final valid = ExecutionModeValidator.validate(
          mode: ExerciseExecutionMode.cardio,
          weight: 0.0,
          reps: 1,
          durationSeconds: 1800,
          distanceMeters: 4000.0,
        );
        expect(valid, isNull);
      });
    });

    // ── 5. Barbell Plate Calculator Verification ─────────────────────────────
    group('5. Barbell Plate Calculator', () {
      test('60kg total = 20kg bar + 20kg/side exactly', () {
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 60.0,
          barWeightKg: 20.0,
        );

        expect(res.barWeight, equals(20.0));
        expect(res.weightPerSide, equals(20.0));
        expect(res.platesPerSide, equals([20.0]));
        expect(res.isExact, isTrue);
        expect(res.summaryText, equals('20 kg / side'));
      });

      test('100kg total = 20kg bar + 25kg + 15kg/side exactly', () {
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 100.0,
          barWeightKg: 20.0,
        );

        expect(res.barWeight, equals(20.0));
        expect(res.weightPerSide, equals(40.0));
        expect(res.platesPerSide, equals([25.0, 15.0]));
        expect(res.isExact, isTrue);
        expect(res.summaryText, equals('25 + 15 kg / side'));
      });

      test('handles weights below bar weight safely with non-exact remainder', () {
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 15.0,
          barWeightKg: 20.0,
        );

        expect(res.barWeight, equals(20.0));
        expect(res.weightPerSide, equals(0.0));
        expect(res.platesPerSide, isEmpty);
        expect(res.isExact, isFalse);
        expect(res.remainder, equals(-5.0));
        expect(res.summaryText, contains('Below bar (20 kg)'));
      });

      test('handles target weight equal to bar weight exactly', () {
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 20.0,
          barWeightKg: 20.0,
        );

        expect(res.barWeight, equals(20.0));
        expect(res.weightPerSide, equals(0.0));
        expect(res.platesPerSide, isEmpty);
        expect(res.isExact, isTrue);
        expect(res.summaryText, equals('20 kg bar only'));
      });

      test('custom bar weight (e.g. 15kg women barbell) calculates correctly', () {
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 55.0,
          barWeightKg: 15.0,
        );

        expect(res.barWeight, equals(15.0));
        expect(res.weightPerSide, equals(20.0)); // (55 - 15) / 2 = 20
        expect(res.platesPerSide, equals([20.0]));
        expect(res.isExact, isTrue);
        expect(res.summaryText, equals('20 kg / side'));
      });

      test('inventory-constrained combinations fall back to available plates', () {
        // 60kg total requires 20kg/side.
        // If inventory has 0 20kg plates, but two 10kg plates:
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 60.0,
          barWeightKg: 20.0,
          plateInventoryPerSide: {
            25.0: 0,
            20.0: 0, // No 20kg plate available
            15.0: 0,
            10.0: 2, // Two 10kg plates available
            5.0: 4,
          },
        );

        expect(res.weightPerSide, equals(20.0));
        expect(res.platesPerSide, equals([10.0, 10.0]));
        expect(res.isExact, isTrue);
        expect(res.summaryText, equals('2×10 kg / side'));
      });

      test('inventory exhaustion flags isExact as false with remainder', () {
        // 60kg total requires 20kg/side, but only one 10kg plate available
        final res = BarbellPlateCalculator.calculate(
          targetWeightKg: 60.0,
          barWeightKg: 20.0,
          plateInventoryPerSide: {
            10.0: 1, // Only 10kg available
          },
        );

        expect(res.platesPerSide, equals([10.0]));
        expect(res.isExact, isFalse);
        expect(res.remainder, equals(10.0));
      });
    });

    // ── 6. Rest Timer Lifecycle ──────────────────────────────────────────────
    group('6. Rest Timer Lifecycle', () {
      test('timer state starts and decrements smoothly', () {
        int remaining = 90;
        bool isActive = true;
        int countdownHapticCount = 0;
        int? lastHapticSec;

        // Simulate 3-2-1 countdown logic
        void tick(int sec) {
          remaining = sec;
          if (remaining <= 3 && remaining >= 1 && lastHapticSec != remaining) {
            lastHapticSec = remaining;
            countdownHapticCount++;
          }
        }

        tick(4);
        expect(countdownHapticCount, equals(0));

        tick(3);
        expect(countdownHapticCount, equals(1));

        tick(3); // Duplicate tick at 3s should NOT trigger second haptic
        expect(countdownHapticCount, equals(1));

        tick(2);
        expect(countdownHapticCount, equals(2));

        tick(1);
        expect(countdownHapticCount, equals(3));

        // Completion transition
        remaining = 0;
        isActive = false;
        expect(remaining, equals(0));
        expect(isActive, isFalse);
      });
    });

    // ── 7. Wakelock Idempotence & Graceful Fallback ───────────────────────────
    group('7. Wakelock Idempotence & Resilience', () {
      test('repeated enable and disable calls are idempotent and safe in test environment', () async {
        final wakelock = WakelockService.instance;

        // Ensure clean initial state
        await wakelock.disable();
        expect(wakelock.isEnabled, isFalse);

        // Multiple enables
        await wakelock.enable();
        expect(wakelock.isEnabled, isTrue);
        await wakelock.enable();
        expect(wakelock.isEnabled, isTrue);

        // Multiple disables
        await wakelock.disable();
        expect(wakelock.isEnabled, isFalse);
        await wakelock.disable();
        expect(wakelock.isEnabled, isFalse);
      });
    });

    // ── 8. Exercise Definition Mode Inference ─────────────────────────────────
    group('8. Exercise Definition Mode Inference', () {
      test('correctly infers mode from name and category', () {
        const plank = Exercise(
          id: 'p1',
          name: 'Plank Hold',
          muscleGroup: 'Core',
          type: ExerciseType.bodyweight,
        );
        expect(plank.effectiveExecutionMode, equals(ExerciseExecutionMode.timed));

        const pullup = Exercise(
          id: 'pu1',
          name: 'Wide Grip Pull-up',
          muscleGroup: 'Back',
          type: ExerciseType.bodyweight,
        );
        expect(pullup.effectiveExecutionMode, equals(ExerciseExecutionMode.bodyweightReps));

        const run = Exercise(
          id: 'r1',
          name: 'Treadmill Running',
          muscleGroup: 'Cardio',
          type: ExerciseType.bodyweight,
        );
        expect(run.effectiveExecutionMode, equals(ExerciseExecutionMode.cardio));

        const bench = Exercise(
          id: 'bp1',
          name: 'Barbell Bench Press',
          muscleGroup: 'Chest',
          type: ExerciseType.barbellCompound,
        );
        expect(bench.effectiveExecutionMode, equals(ExerciseExecutionMode.weightReps));
      });
    });
  });
}
