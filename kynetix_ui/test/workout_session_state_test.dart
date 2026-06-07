import 'dart:convert';
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
    await WorkoutService.instance.init();
  });

  tearDown(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await WorkoutService.instance.clearDraftSession();
  });

  final emptySplitDay = SplitDay(
    weekday: 1,
    name: 'Custom Workout',
    exercises: const [],
  );

  testWidgets('Flow 1: Empty Workout Session State (Initial State)', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: emptySplitDay,
          date: DateTime.now(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify empty state is displayed properly and no crash has occurred
    expect(find.byType(WorkoutSessionScreen), findsOneWidget);
    expect(find.text('Empty Workout Session'), findsOneWidget);
    expect(find.text('Add your first exercise to start tracking your sets, weight, reps, and RPE.'), findsOneWidget);

    // Verify "Add Exercise" CTA buttons exist
    expect(find.byKey(const Key('center_add_exercise_button')), findsOneWidget);
    expect(find.byKey(const Key('bottom_add_exercise_button')), findsOneWidget);

    // Verify no RangeError or ArgumentError
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flow 2: Start Custom Workout -> Add Exercise -> Log Set -> Finish Workout', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: emptySplitDay,
          date: DateTime.now(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Click center "Add Exercise" button
    await tester.tap(find.byKey(const Key('center_add_exercise_button')));
    await tester.pumpAndSettle();

    // 2. Select the first exercise (e.g. Bench Press) in list
    expect(find.text('Bench Press'), findsOneWidget);
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    // Verify Bench Press is added to the session
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Empty Workout Session'), findsNothing);

    // 3. Log a Set
    expect(find.text('LOG SET 1'), findsOneWidget);
    await tester.tap(find.text('LOG SET 1'));
    await tester.pumpAndSettle();

    // Verify set is logged (button updates to LOG SET 2)
    expect(find.text('LOG SET 2'), findsOneWidget);

    // 4. Click Finish
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    // Dialog pops up: choose "Finish Workout"
    expect(find.text('End Workout Session'), findsOneWidget);
    await tester.tap(find.text('Finish Workout'));
    await tester.pumpAndSettle();

    // Verify no exception occurred
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flow 3: Start Custom Workout -> Add Exercise -> Remove Exercise -> Back to Empty State', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: emptySplitDay,
          date: DateTime.now(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Add Exercise
    await tester.tap(find.byKey(const Key('center_add_exercise_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    // Verify exercise is present
    expect(find.text('Bench Press'), findsOneWidget);

    // 2. Remove Exercise
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    // Verify we are back to empty state since no sets were logged (removed immediately)
    expect(find.text('Empty Workout Session'), findsOneWidget);
    expect(find.byKey(const Key('center_add_exercise_button')), findsOneWidget);

    // Verify no exceptions
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flow 4: Start Custom Workout -> Exit -> Resume Draft', (WidgetTester tester) async {
    // Stage 1: Open session, add exercise, log set, and save draft on exit
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: emptySplitDay,
          date: DateTime.now(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Add exercise
    await tester.tap(find.byKey(const Key('center_add_exercise_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    // Log set
    await tester.tap(find.text('LOG SET 1'));
    await tester.pumpAndSettle();

    // Exit workout via Close button
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Pause Dialog shows up, select "Save & Leave"
    expect(find.text('Pause Workout?'), findsOneWidget);
    await tester.tap(find.text('Save & Leave'));
    await tester.pumpAndSettle();

    // Ensure we exited without exceptions
    expect(tester.takeException(), isNull);

    // Stage 2: Resume from draft
    final draft = WorkoutService.instance.draftSession;
    expect(draft, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: ThemeData.dark(),
        home: WorkoutSessionScreen(
          splitDay: emptySplitDay,
          date: DateTime.now(),
          draftSession: draft,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify draft was restored correctly: Bench Press is present and set counts are retrieved
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('LOG SET 2'), findsOneWidget); // since set 1 was logged

    // Ensure we exited without exceptions
    expect(tester.takeException(), isNull);
  });
}
