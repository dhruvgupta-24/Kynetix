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
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
    await WorkoutService.instance.init();
  });

  final splitDay = SplitDay(
    weekday: 1,
    name: 'Push',
    exercises: [
      const Exercise(
        id: 'bench_press',
        name: 'Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
        notes: 'Maintain alignment, control the eccentric phase.',
      ),
    ],
  );

  final widths = [320.0, 360.0, 411.0];
  final textScales = [1.0, 1.3, 1.5];

  for (final width in widths) {
    for (final scale in textScales) {
      testWidgets('WorkoutSessionScreen layout - width: ${width}dp, textScale: ${scale}x', (WidgetTester tester) async {
        // Configure device size and text scale
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        
        // Use platformDispatcher to override textScaleFactor in newer Flutter versions
        tester.view.platformDispatcher.textScaleFactorTestValue = scale;

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.platformDispatcher.clearTextScaleFactorTestValue();
        });

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
        
        // Assert that the screen and vital components exist
        expect(find.byType(WorkoutSessionScreen), findsOneWidget);
        
        // Check that the finish button and title are rendered
        expect(find.text('Finish'), findsOneWidget);
        expect(find.text('PUSH'), findsOneWidget);
      });
    }
  }
}
