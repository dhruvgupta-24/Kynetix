import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// A plank or a run used to be saved with the hidden weight dial's 40 kg x 10,
// so a 60 s hold added "400 kg" to the session and could show up as a "new
// best". Holds and cardio carry no kilos.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await WorkoutService.instance.init();
  });

  tearDown(() async {
    await WorkoutService.instance.clearDraftSession();
  });

  Future<void> pump(WidgetTester tester, SplitDay day) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: WorkoutSessionScreen(splitDay: day, date: DateTime.now()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a plank set logs no kilos and completes the exercise', (tester) async {
    await pump(
      tester,
      SplitDay(
        weekday: 2,
        name: 'Core test',
        exercises: const [
          Exercise(
            id: 'timed_test_plank',
            name: 'Plank',
            muscleGroup: 'Core',
            type: ExerciseType.bodyweight,
            defaultTargetSets: 1,
            executionMode: ExerciseExecutionMode.timed,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Log set 1'));
    await tester.pumpAndSettle();

    // One set of one: the bar is full and the header moved no kilos.
    expect(find.text('100%'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('workout_progress_bar')));
    expect(bar.value, 1.0);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    final saved = WorkoutService.instance.lastSessionFor('Core test')!;
    final set = saved.entries.single.sets.single;
    expect(set.weight, 0);
    expect(set.durationSeconds, 60);
    expect(saved.totalVolume, 0);
    // The scoreboard leads with the sets, not "0 kg" or "1 reps".
    expect(find.text('Holds and cardio today'), findsOneWidget);
    // The receipt shows the hold's time.
    expect(find.text('1:00'), findsOneWidget);
  });

  testWidgets('cardio logs the distance and time the console shows', (tester) async {
    await pump(
      tester,
      SplitDay(
        weekday: 3,
        name: 'Cardio test',
        exercises: const [
          Exercise(
            id: 'cardio_test_run',
            name: 'Treadmill Run',
            muscleGroup: 'Cardio',
            type: ExerciseType.bodyweight,
            defaultTargetSets: 1,
            executionMode: ExerciseExecutionMode.cardio,
          ),
        ],
      ),
    );
    // The untouched console reads 15 min and 2 km; tapping Log saves those.
    await tester.tap(find.text('Log set 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    final set = WorkoutService.instance.lastSessionFor('Cardio test')!.entries.single.sets.single;
    expect(set.distanceMeters, 2000);
    expect(set.durationSeconds, 900);
    expect(set.weight, 0);
    expect(set.volume, 0);
  });
}
