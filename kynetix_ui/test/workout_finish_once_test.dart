import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/workout_service.dart';

// Finish, close the app on the summary, reopen, Resume, Finish again: one
// workout must stay one session.
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

  const bench = Exercise(id: 'bench', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound);
  final day = DateTime(2026, 10, 21);

  WorkoutSession session(String id, {double kg = 80, int minutes = 60}) => WorkoutSession(
        id: id,
        date: day,
        splitDayName: 'Chest + Triceps',
        entries: [
          ExerciseEntry(exercise: bench, sets: [SetEntry(weight: kg, reps: 8), SetEntry(weight: kg, reps: 6)]),
        ],
        durationMinutes: minutes,
      );

  test('a draft keeps its id when it becomes a session', () {
    expect(WorkoutService.finishedIdFor('ws_draft_1729500000000'), 'ws_1729500000000');
    expect(WorkoutService.finishedIdFor('ws_recovered_5'), 'ws_recovered_5');
  });

  test('a draft written after Finish is ignored', () async {
    final svc = WorkoutService.instance;
    await svc.saveSession(session('ws_100'));
    // The summary screen's lifecycle save lands late.
    await svc.saveDraftSession(session('ws_draft_100'));
    expect(svc.draftSession, isNull);
  });

  test('finishing the same workout twice keeps one session', () async {
    final svc = WorkoutService.instance;
    await svc.saveSession(session('ws_100', minutes: 87));
    await svc.saveSession(session('ws_100', minutes: 109));
    expect(svc.sessions.where((s) => s.splitDayName == 'Chest + Triceps'), hasLength(1));
  });

  test('copies saved by older builds collapse to the first save', () async {
    final svc = WorkoutService.instance;
    await svc.saveSession(session('ws_100', minutes: 87));
    await svc.saveSession(session('ws_200', minutes: 109));
    expect(svc.sessions.map((s) => s.id), ['ws_100']);
    expect(svc.isSessionDeleted('ws_200'), isTrue);
  });

  test('two different workouts on one day both stay', () async {
    final svc = WorkoutService.instance;
    await svc.saveSession(session('ws_100'));
    await svc.saveSession(session('ws_200', kg: 85));
    expect(svc.sessions, hasLength(2));
  });
}
