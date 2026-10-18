import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    await WorkoutService.instance.init();
  });

  tearDown(() async {
    await WorkoutService.instance.clearDraftSession();
  });

  final splitDay = SplitDay(
    weekday: 1,
    name: 'Push',
    exercises: const [
      Exercise(
        id: 'scoreboard_bench',
        name: 'Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
        defaultTargetSets: 2,
      ),
    ],
  );

  Future<void> pumpSession(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: WorkoutSessionScreen(splitDay: splitDay, date: DateTime.now()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('form panel shows one specific cue, no generic tip', (tester) async {
    await pumpSession(tester);
    final toggle = find.textContaining('Form and notes').evaluate().isNotEmpty
        ? find.textContaining('Form and notes')
        : find.textContaining('Form, notes and RPE');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form_cue_line')), findsOneWidget);
    expect(find.textContaining('drive the floor away'), findsOneWidget);
    expect(find.textContaining('stretch-mediated'), findsNothing);
    expect(find.text('Execution cues'), findsNothing);
  });

  testWidgets('finishing shows the session scoreboard with real data', (tester) async {
    await pumpSession(tester);
    await tester.tap(find.text('Log set 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish workout'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session_scoreboard')), findsOneWidget);
    expect(find.text('Saved to your log'), findsOneWidget);
    expect(find.text('The work'), findsOneWidget);
    expect(find.text('Bench Press'), findsWidgets);
    expect(find.text('min'), findsOneWidget);
    expect(find.text('score'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const Key('share_workout_button')), findsOneWidget);
    // The old template pieces are gone.
    expect(find.text('Session summary'), findsNothing);
    expect(find.text('Muscles trained'), findsNothing);
    expect(find.textContaining('Solid session'), findsNothing);
  });
}
