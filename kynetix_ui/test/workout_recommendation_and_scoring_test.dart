import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
    await WorkoutService.instance.init();
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await WorkoutService.instance.clearAll();
  });

  final mockExercise = Exercise(
    id: 'ex_bench_press',
    name: 'Bench Press',
    muscleGroup: 'Chest',
    type: ExerciseType.barbellCompound,
    defaultTargetSets: 3,
    defaultRepMin: 8,
    defaultRepMax: 12,
  );

  group('1. Volume Splits Test', () {
    test('primaryWorkingVolume vs totalStimulusVolume', () {
      final entry = ExerciseEntry(
        exercise: mockExercise,
        sets: const [
          SetEntry(weight: 40, reps: 10, setType: SetType.warmUp), // Excluded from both
          SetEntry(weight: 80, reps: 8, setType: SetType.normal), // Primary working
          SetEntry(weight: 80, reps: 7, setType: SetType.normal), // Primary working
          SetEntry(weight: 60, reps: 10, setType: SetType.dropSet), // Total stimulus only
          SetEntry(weight: 50, reps: 12, setType: SetType.dropSet), // Total stimulus only
        ],
      );

      // Primary working sets: normal.
      // 80*8 + 80*7 = 640 + 560 = 1200
      expect(entry.primaryWorkingVolume, 1200.0);
      expect(entry.workingVolume, 1200.0); // backwards-compatible

      // Total stimulus volume: everything except warmUp.
      // 80*8 + 80*7 + 60*10 + 50*12 = 1200 + 600 + 600 = 2400
      expect(entry.totalStimulusVolume, 2400.0);
    });
  });

  group('2. Progression Style Detection', () {
    test('Low confidence when history is too short (<3 sessions)', () async {
      final service = WorkoutService.instance;
      
      final session = WorkoutSession(
        id: 's1',
        date: DateTime.now().subtract(const Duration(days: 7)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 80, reps: 8, setType: SetType.normal),
              SetEntry(weight: 80, reps: 8, setType: SetType.normal),
            ],
          ),
        ],
      );
      await service.saveSession(session);

      final analysis = service.detectProgressionStyle(mockExercise.id);
      expect(analysis.confidence, lessThan(0.50));
    });

    test('Strength Low Rep style detection (sets <= 5 reps)', () async {
      final service = WorkoutService.instance;

      for (int i = 0; i < 3; i++) {
        await service.saveSession(WorkoutSession(
          id: 'session_$i',
          date: DateTime.now().subtract(Duration(days: (3 - i) * 7)),
          splitDayName: 'Push',
          entries: [
            ExerciseEntry(
              exercise: mockExercise,
              sets: const [
                SetEntry(weight: 100, reps: 4, setType: SetType.normal),
                SetEntry(weight: 100, reps: 4, setType: SetType.normal),
              ],
            ),
          ],
        ));
      }

      final analysis = service.detectProgressionStyle(mockExercise.id);
      expect(analysis.style, ProgressionStyle.strengthLowRep);
      expect(analysis.confidence, greaterThanOrEqualTo(0.80));
    });

    test('Ascending Weight style detection', () async {
      final service = WorkoutService.instance;

      for (int i = 0; i < 3; i++) {
        await service.saveSession(WorkoutSession(
          id: 'session_$i',
          date: DateTime.now().subtract(Duration(days: (3 - i) * 7)),
          splitDayName: 'Push',
          entries: [
            ExerciseEntry(
              exercise: mockExercise,
              sets: const [
                SetEntry(weight: 70, reps: 8, setType: SetType.normal),
                SetEntry(weight: 75, reps: 8, setType: SetType.normal),
                SetEntry(weight: 80, reps: 8, setType: SetType.normal),
              ],
            ),
          ],
        ));
      }

      final analysis = service.detectProgressionStyle(mockExercise.id);
      expect(analysis.style, ProgressionStyle.ascendingWeight);
    });

    test('Reverse Pyramid style detection', () async {
      final service = WorkoutService.instance;

      for (int i = 0; i < 3; i++) {
        await service.saveSession(WorkoutSession(
          id: 'session_$i',
          date: DateTime.now().subtract(Duration(days: (3 - i) * 7)),
          splitDayName: 'Push',
          entries: [
            ExerciseEntry(
              exercise: mockExercise,
              sets: const [
                SetEntry(weight: 90, reps: 6, setType: SetType.normal),
                SetEntry(weight: 80, reps: 8, setType: SetType.normal),
                SetEntry(weight: 70, reps: 10, setType: SetType.normal),
              ],
            ),
          ],
        ));
      }

      final analysis = service.detectProgressionStyle(mockExercise.id);
      expect(analysis.style, ProgressionStyle.reversePyramid);
    });
  });

  group('3. Fatigue & Deload Detection', () {
    test('Triggers fatigue deload when e1RM declines 3 sessions in a row', () async {
      final service = WorkoutService.instance;

      // Session 1: 100 kg x 10 reps (e1RM = 100 * (1 + 10/30) = 133.3)
      await service.saveSession(WorkoutSession(
        id: 'fatigue_1',
        date: DateTime.now().subtract(const Duration(days: 21)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 100, reps: 10, setType: SetType.normal),
            ],
          ),
        ],
      ));

      // Session 2: 90 kg x 10 reps (e1RM = 90 * (1 + 10/30) = 120.0)
      await service.saveSession(WorkoutSession(
        id: 'fatigue_2',
        date: DateTime.now().subtract(const Duration(days: 14)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 90, reps: 10, setType: SetType.normal),
            ],
          ),
        ],
      ));

      // Session 3: 80 kg x 10 reps (e1RM = 80 * (1 + 10/30) = 106.6)
      await service.saveSession(WorkoutSession(
        id: 'fatigue_3',
        date: DateTime.now().subtract(const Duration(days: 7)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 80, reps: 10, setType: SetType.normal),
            ],
          ),
        ],
      ));

      expect(service.detectFatigueDecline(mockExercise.id), isTrue);

      final rec = service.getPersonalizedRecommendation(mockExercise.id, 'Push');
      expect(rec.isDeload, isTrue);
      expect(rec.recommendation, contains('Fatigue accumulation detected'));
    });
  });

  group('4. Safety Checks', () {
    test('Triggered by RPE 10 failure at low reps', () async {
      final service = WorkoutService.instance;

      await service.saveSession(WorkoutSession(
        id: 'safety_rpe10',
        date: DateTime.now().subtract(const Duration(days: 7)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 100, reps: 2, rpe: 10.0, setType: SetType.normal),
            ],
          ),
        ],
      ));

      final rec = service.getPersonalizedRecommendation(mockExercise.id, 'Push');
      expect(rec.style, isNull); // style recommendation bypassed
      expect(rec.recommendation, contains('Safety threshold triggered'));
    });

    test('Triggered by low reps on compound movement (<4 reps)', () async {
      final service = WorkoutService.instance;

      await service.saveSession(WorkoutSession(
        id: 'safety_low_reps',
        date: DateTime.now().subtract(const Duration(days: 7)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 100, reps: 3, setType: SetType.normal),
            ],
          ),
        ],
      ));

      final rec = service.getPersonalizedRecommendation(mockExercise.id, 'Push');
      expect(rec.style, isNull);
      expect(rec.recommendation, contains('Safety threshold triggered'));
    });

    test('Triggered by >10% e1RM regression', () async {
      final service = WorkoutService.instance;

      // History baseline average e1RM = 100
      await service.saveSession(WorkoutSession(
        id: 'bl_1',
        date: DateTime.now().subtract(const Duration(days: 21)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 100, reps: 0, setType: SetType.normal), // weight 100, reps 0 -> e1RM = 100
            ],
          ),
        ],
      ));

      await service.saveSession(WorkoutSession(
        id: 'bl_2',
        date: DateTime.now().subtract(const Duration(days: 14)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 100, reps: 0, setType: SetType.normal), // e1RM = 100
            ],
          ),
        ],
      ));

      // Latest session: e1RM drops to 80 kg
      await service.saveSession(WorkoutSession(
        id: 'bl_latest',
        date: DateTime.now().subtract(const Duration(days: 7)),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(
            exercise: mockExercise,
            sets: const [
              SetEntry(weight: 80, reps: 0, setType: SetType.normal), // e1RM = 80 (< 100 * 0.90)
            ],
          ),
        ],
      ));

      final rec = service.getPersonalizedRecommendation(mockExercise.id, 'Push');
      expect(rec.style, isNull);
      expect(rec.recommendation, contains('Safety threshold triggered'));
    });
  });
}
