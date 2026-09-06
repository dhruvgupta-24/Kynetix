import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';

void main() {
  group('Exercise Execution Modes and SetEntry Tests', () {
    test('ExerciseExecutionMode parses and serializes correctly', () {
      const ex = Exercise(
        id: 'plank-1',
        name: 'Plank',
        muscleGroup: 'Core',
        type: ExerciseType.bodyweight,
        executionMode: ExerciseExecutionMode.timed,
      );

      final json = ex.toJson();
      expect(json['executionMode'], equals('timed'));

      final restored = Exercise.fromJson(json);
      expect(restored.executionMode, equals(ExerciseExecutionMode.timed));
    });

    test('SetEntry with timed hold serializes durationSeconds correctly', () {
      const set = SetEntry(
        weight: 0,
        reps: 1,
        durationSeconds: 90, // 1 min 30 sec
      );

      final json = set.toJson();
      expect(json['durationSeconds'], equals(90));

      final restored = SetEntry.fromJson(json);
      expect(restored.durationSeconds, equals(90));
      expect(restored.toString(), contains('01:30'));
    });

    test('SetEntry with cardio distance and duration serializes cleanly', () {
      const set = SetEntry(
        weight: 0,
        reps: 1,
        durationSeconds: 1200, // 20 mins
        distanceMeters: 3200.0, // 3.2 km
      );

      final json = set.toJson();
      expect(json['distanceMeters'], equals(3200.0));
      expect(json['durationSeconds'], equals(1200));

      final restored = SetEntry.fromJson(json);
      expect(restored.distanceMeters, equals(3200.0));
      expect(restored.durationSeconds, equals(1200));
    });

    test('Backward compatibility: legacy SetEntry json without duration deserializes safely', () {
      final legacyJson = {
        'weight': 80.0,
        'reps': 8,
        'setType': 'normal',
      };

      final restored = SetEntry.fromJson(legacyJson);
      expect(restored.weight, equals(80.0));
      expect(restored.reps, equals(8));
      expect(restored.durationSeconds, isNull);
      expect(restored.distanceMeters, isNull);
    });
  });
}
