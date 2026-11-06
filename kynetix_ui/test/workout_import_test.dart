import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/data_export_service.dart';
import 'package:kynetix/services/workout_import_service.dart';
import 'package:kynetix/services/workout_service.dart';

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

  const strong = 'Workout #,Date,Workout Name,Duration (sec),Exercise Name,Set Order,Weight (kg),Reps,RPE,Distance (meters),Seconds,Notes,Workout Notes\n'
      '1,2026-10-01 07:30:00,Push,3600,Bench Press (Barbell),W,40,10,,,,,\n'
      '1,2026-10-01 07:30:00,Push,3600,Bench Press (Barbell),1,80,8,8,,,,\n'
      '1,2026-10-01 07:30:00,Push,3600,Bench Press (Barbell),2,80,6,9,,,,\n'
      '1,2026-10-01 07:30:00,Push,3600,"Zottman Curl, Seated",1,12.5,10,,,,,\n'
      '1,2026-10-01 07:30:00,Push,3600,Rest Timer,1,0,0,,,,,\n'
      '2,2026-10-03 18:00:00,Legs,2700,Squat (Barbell),1,100,5,,,,,\n';

  const hevy = 'title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_lbs,reps,distance_km,duration_seconds,rpe\n'
      '"Pull Day","5 Oct 2026, 09:00","5 Oct 2026, 10:10","",Lat Pulldown (Cable),,,0,warmup,50,12,,,\n'
      '"Pull Day","5 Oct 2026, 09:00","5 Oct 2026, 10:10","",Lat Pulldown (Cable),,,1,normal,100,10,,,8\n';

  test('reads a Strong export: workouts, set types, quoted names, rest rows skipped', () {
    final p = WorkoutImportService.parse(strong);
    expect(p.source, 'Strong');
    expect(p.workouts, hasLength(2));
    final push = p.workouts.first;
    expect(push.title, 'Push');
    expect(push.minutes, 60);
    expect(push.exercises.keys, ['Bench Press (Barbell)', 'Zottman Curl, Seated']);
    expect(push.exercises['Bench Press (Barbell)']!.first.type, SetType.warmUp);
    expect(push.exercises['Bench Press (Barbell)']![1].rpe, 8);
    expect(p.skippedRows, 1);
  });

  test('reads a Hevy export in pounds', () {
    final p = WorkoutImportService.parse(hevy);
    expect(p.source, 'Hevy');
    final w = p.workouts.single;
    expect(w.start, DateTime(2026, 10, 5, 9));
    expect(w.minutes, 70);
    final sets = w.exercises['Lat Pulldown (Cable)']!;
    expect(sets.first.type, SetType.warmUp);
    expect(sets[1].weightKg, closeTo(45.4, 0.05));
  });

  test('a file that is not a workout export is refused', () {
    expect(() => WorkoutImportService.parse('name,age\nA,3\n'), throwsFormatException);
  });

  test('importing the same file twice adds nothing the second time', () async {
    final p = WorkoutImportService.parse(strong);
    final first = await WorkoutImportService.instance.import(p);
    expect(first.added, 2);
    final second = await WorkoutImportService.instance.import(WorkoutImportService.parse(strong));
    expect(second.added, 0);
    expect(second.alreadyHere, 2);
    expect(WorkoutService.instance.sessions, hasLength(2));
  });

  test('Kynetix export reads back in', () async {
    await WorkoutService.instance.saveSession(WorkoutSession(
      id: 'ws_1',
      date: DateTime(2026, 10, 9, 7),
      splitDayName: 'Upper',
      durationMinutes: 50,
      entries: [
        ExerciseEntry(
          exercise: const Exercise(id: 'bench', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound),
          sets: [SetEntry(weight: 80, reps: 8)],
        ),
      ],
    ));
    final csv = DataExportService.workoutsCsv(WorkoutService.instance.sessions);
    final p = WorkoutImportService.parse(csv);
    expect(p.workouts.single.exercises['Bench Press']!.single.weightKg, 80);
    expect(p.workouts.single.minutes, 50);
  });
}
