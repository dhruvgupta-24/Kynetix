import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/workout_service.dart';

// A custom exercise made once must be in the picker on every later day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
  });

  const hipThrust = Exercise(id: 'custom_1', name: 'Smith Hip Thrust', muscleGroup: 'Glutes', type: ExerciseType.isolation);
  bool inLibrary(String id) => ExerciseLibraryService.instance.customDefinitions.any((d) => d.id == id);

  test('a new custom exercise is searchable at once', () async {
    await WorkoutService.instance.addCustomExercise(hipThrust);
    expect(inLibrary('custom_1'), isTrue);
    expect(ExerciseLibraryService.instance.getById('custom_1')?.name, 'Smith Hip Thrust');
  });

  test('it is still there after the app restarts', () async {
    final svc = WorkoutService.instance;
    await svc.addCustomExercise(hipThrust);
    await svc.flushPendingWrites();
    svc.clearMemory();
    expect(inLibrary('custom_1'), isFalse);
    await svc.init();
    expect(svc.customExercises.map((e) => e.id), ['custom_1']);
    expect(inLibrary('custom_1'), isTrue);
  });

  test('a custom exercise only found in a logged session joins the library', () async {
    final svc = WorkoutService.instance;
    await svc.saveSession(WorkoutSession(
      id: 'ws_1',
      date: DateTime(2026, 11, 1),
      splitDayName: 'Legs',
      entries: [ExerciseEntry(exercise: hipThrust, sets: [SetEntry(weight: 60, reps: 10)])],
    ));
    expect(svc.customExercises.map((e) => e.id), contains('custom_1'));
    expect(inLibrary('custom_1'), isTrue);
  });

  test('an older cloud copy does not erase one made offline', () async {
    final svc = WorkoutService.instance;
    await svc.addCustomExercise(hipThrust);
    const cloudOnly = Exercise(id: 'custom_2', name: 'Band Pull Apart', muscleGroup: 'Rear Delts', type: ExerciseType.isolation);
    await svc.loadSplitAndCustomExercisesFromCloud(svc.split, [cloudOnly]);
    expect(svc.customExercises.map((e) => e.id).toSet(), {'custom_1', 'custom_2'});
    expect(inLibrary('custom_1') && inLibrary('custom_2'), isTrue);
  });
}
