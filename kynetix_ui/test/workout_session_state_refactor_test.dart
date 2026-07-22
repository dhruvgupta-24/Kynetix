import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
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
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await WorkoutService.instance.clearAll();
    WorkoutService.instance.resetReadyForTesting();
    await WorkoutService.instance.init();
  });

  testWidgets('Verify SetType options are simplified to Working, Warm-up, and Drop', (WidgetTester tester) async {
    expect(SetType.values.length, equals(3));
    expect(SetType.normal.label, equals('Working'));
    expect(SetType.warmUp.label, equals('Warm-up'));
    expect(SetType.dropSet.label, equals('Drop'));
  });

  testWidgets('Verify logging extra sets remains unlocked after exercise completion', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final ex1 = const Exercise(
      id: 'ex_bench',
      name: 'Bench Press',
      muscleGroup: 'Chest',
      type: ExerciseType.barbellCompound,
      defaultTargetSets: 3,
    );

    final splitDay = SplitDay(
      weekday: 1,
      name: 'Push Day',
      exercises: [ex1],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: splitDay,
          date: DateTime.now(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(WorkoutSessionScreen)) as dynamic;

    // Log 3 working sets
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('LOG SET ${i + 1}'));
      await tester.pumpAndSettle();
    }

    final entry3 = state.buildEntry(ex1);
    expect(entry3.isCompleted, isTrue);

    // Verify button to log set 4 is STILL enabled and visible!
    expect(find.text('LOG SET 4'), findsOneWidget);

    // Tap to log set 4 (extra set)
    await tester.tap(find.text('LOG SET 4'));
    await tester.pumpAndSettle();

    final entry4 = state.buildEntry(ex1);
    expect(entry4.sets.length, equals(4));
    expect(entry4.isCompleted, isTrue);

    await tester.pump(const Duration(seconds: 5));
  });
}
