import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/auth_gate.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/ui/k_loaders.dart';
import 'package:kynetix/widgets/body_log_widgets.dart';
import 'package:kynetix/widgets/workout_session_sheets.dart';
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

  const testExercise = Exercise(
    id: 'cable_lateral_raise',
    name: 'Cable Lateral Raise',
    muscleGroup: 'Shoulders',
    type: ExerciseType.isolation,
  );

  group('Bottom Sheet Overflow Resilience Tests', () {
    testWidgets('Rest timer sheet renders without overflow on small screens and large text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.4;

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showRestPickerSheet(
                    context,
                    exerciseName: testExercise.name,
                    currentSeconds: 60,
                  ),
                  child: const Text('Open Rest Timer'),
                ),
              ),
            ),
          ),
        ),
      );

      // Tap button to open sheet
      await tester.tap(find.text('Open Rest Timer'));
      await tester.pumpAndSettle();

      // Assert sheet is open and text is displayed
      expect(find.text('Rest timer'), findsOneWidget);
      expect(find.text('1 min'), findsOneWidget);

      // Verify no exceptions / overflow errors occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('Warm up sheet renders without overflow on small screens', (tester) async {
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showWarmUpSheet(
                    context,
                    exercise: testExercise,
                    suggestedWorkingWeight: 50.0,
                  ),
                  child: const Text('Open Warm Up'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Warm Up'));
      await tester.pumpAndSettle();

      expect(find.text('Add warm-up sets'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Weight log sheet renders without overflow under simulated keyboard inset', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      // Simulate 280px keyboard height
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showWeightLogSheet(
                    context,
                    date: DateTime.now(),
                    startKg: 75.0,
                    trendKg: 74.8,
                    weeklyRateKg: -0.2,
                  ),
                  child: const Text('Open Weight Log'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Weight Log'));
      await tester.pumpAndSettle();

      expect(find.text('Log your weight'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('BrandLoader Underline Regression Test', () {
    testWidgets('AuthGate loader has Material ancestor with no yellow underlines', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            color: const Color(0xFF141414),
            child: KLoadingLabel(
              messages: const ['Getting your plan ready...'],
              style: const TextStyle(decoration: TextDecoration.none),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.text('Getting your plan ready...'));
      expect(textWidget.style?.decoration, equals(TextDecoration.none));
      expect(tester.takeException(), isNull);
    });
  });
}
