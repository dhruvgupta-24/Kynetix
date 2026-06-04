import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  setUp(() async {
    // Clear SharedPreferences between tests
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await WorkoutService.instance.clearAll();
  });

  group('WorkoutService Split and Cloud Sync Integration Tests', () {
    test('saveSplit updates split config and isSetupDone', () async {
      final service = WorkoutService.instance;
      expect(service.isSetupDone, isFalse);

      final customSplit = WorkoutSplit(
        id: 'test_split_123',
        name: 'Hypertrophy Split',
        days: const [
          SplitDay(weekday: 1, name: 'Chest Day', exercises: []),
        ],
      );

      await service.saveSplit(customSplit);

      expect(service.isSetupDone, isTrue);
      expect(service.split.id, 'test_split_123');
      expect(service.split.name, 'Hypertrophy Split');
    });

    test('addCustomExercise adds exercise to custom list', () async {
      final service = WorkoutService.instance;
      expect(service.customExercises, isEmpty);

      const exercise = Exercise(
        id: 'custom_pushup',
        name: 'Incline Pushups',
        muscleGroup: 'Chest',
        type: ExerciseType.bodyweight,
      );

      await service.addCustomExercise(exercise);

      expect(service.customExercises, hasLength(1));
      expect(service.customExercises.first.id, 'custom_pushup');
      expect(service.customExercises.first.name, 'Incline Pushups');
    });

    test('removeCustomExercise removes exercise from custom list', () async {
      final service = WorkoutService.instance;
      const exercise = Exercise(
        id: 'custom_pullup',
        name: 'Weighted Pullups',
        muscleGroup: 'Back',
        type: ExerciseType.bodyweight,
      );

      await service.addCustomExercise(exercise);
      expect(service.customExercises, hasLength(1));

      await service.removeCustomExercise('custom_pullup');
      expect(service.customExercises, isEmpty);
    });

    test('loadSplitAndCustomExercisesFromCloud correctly hydrates state from cloud data', () async {
      final service = WorkoutService.instance;
      expect(service.isSetupDone, isFalse);

      final cloudSplit = WorkoutSplit(
        id: 'cloud_split_999',
        name: 'Cloud PPL',
        days: const [
          SplitDay(weekday: 2, name: 'Pull Day', exercises: []),
        ],
      );

      final cloudCustom = [
        const Exercise(
          id: 'cloud_ex_1',
          name: 'Cloud Lat Raise',
          muscleGroup: 'Shoulders',
          type: ExerciseType.dumbbell,
        ),
      ];

      await service.loadSplitAndCustomExercisesFromCloud(cloudSplit, cloudCustom);

      expect(service.isSetupDone, isTrue);
      expect(service.split.id, 'cloud_split_999');
      expect(service.split.name, 'Cloud PPL');
      expect(service.customExercises, hasLength(1));
      expect(service.customExercises.first.id, 'cloud_ex_1');
    });

    test('loadSplitAndCustomExercisesFromCloud updates splitUpdatedAt', () async {
      final service = WorkoutService.instance;
      final time = DateTime(2026, 6, 4, 12, 0, 0);

      final cloudSplit = WorkoutSplit(
        id: 'cloud_split_999',
        name: 'Cloud PPL',
        days: const [],
      );

      await service.loadSplitAndCustomExercisesFromCloud(
        cloudSplit,
        [],
        cloudUpdatedAt: time,
      );

      expect(service.splitUpdatedAt, time);
    });
  });
}
