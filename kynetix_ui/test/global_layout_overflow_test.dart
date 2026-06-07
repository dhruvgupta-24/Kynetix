import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/workout_setup_screen.dart';
import 'package:kynetix/screens/add_meal_screen.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/models/day_log.dart';
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

  final widths = [320.0, 360.0, 411.0];
  final textScales = [1.0, 1.3, 1.5];

  for (final width in widths) {
    for (final scale in textScales) {
      testWidgets('Global layout audit - width: ${width}dp, textScale: ${scale}x', (WidgetTester tester) async {
        // Setup device size and scale
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        tester.view.platformDispatcher.textScaleFactorTestValue = scale;

        // Intercept RenderFlex overflows and fail the test
        final originalOnError = FlutterError.onError;
        String? overflowError;
        
        FlutterError.onError = (FlutterErrorDetails details) {
          final msg = details.exception.toString();
          if (msg.contains('overflowed') || msg.contains('RenderFlex')) {
            overflowError = msg;
          }
          originalOnError?.call(details);
        };

        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.platformDispatcher.clearTextScaleFactorTestValue();
          FlutterError.onError = originalOnError;
        });

        // 1. Audit WorkoutSetupScreen (Step 0)
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const WorkoutSetupScreen(editMode: false),
          ),
        );
        await tester.pumpAndSettle();
        if (overflowError != null) {
          fail('RenderFlex overflow detected in WorkoutSetupScreen: $overflowError');
        }

        // 2. Audit WorkoutSetupScreen (Step 4 / Customize Mode)
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const WorkoutSetupScreen(editMode: true),
          ),
        );
        await tester.pumpAndSettle();
        if (overflowError != null) {
          fail('RenderFlex overflow detected in WorkoutSetupScreen (Edit Mode): $overflowError');
        }

        // 3. Audit AddMealScreen
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: AddMealScreen(
              section: MealSection.breakfast,
              date: DateTime.now(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (overflowError != null) {
          fail('RenderFlex overflow detected in AddMealScreen: $overflowError');
        }

        // 3b. Audit Custom / Empty Workout Session
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: WorkoutSessionScreen(
              splitDay: const SplitDay(
                name: 'Custom Workout',
                weekday: 0,
                exercises: [],
              ),
              date: DateTime.now(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (overflowError != null) {
          fail('RenderFlex overflow detected in WorkoutSessionScreen (Custom/Empty): $overflowError');
        }

        // 4. Audit KButton & KChip with long labels
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Column(
                children: [
                  KButton(
                    label: 'Very long button text label that will definitely cause overflow in standard row without flexibility',
                    onTap: () {},
                  ),
                  const SizedBox(height: 10),
                  const KChip('Very long chip text label that will definitely cause overflow in standard row without flexibility'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (overflowError != null) {
          fail('RenderFlex overflow detected in KButton/KChip: $overflowError');
        }
      });
    }
  }
}
