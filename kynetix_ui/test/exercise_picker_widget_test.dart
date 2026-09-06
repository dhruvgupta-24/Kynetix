import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/exercise_detail_sheet.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/widgets/exercise_picker_sheet.dart';
import 'package:kynetix/widgets/muscle_body_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ExerciseLibraryService.instance.initialize();
    MuscleBodyMap.setCachedGeometryForTesting({
      'front': {
        'viewBox': '0 0 100 100',
        'paths': {'chest': 'M 0 0 L 10 10 Z'}
      },
      'back': {
        'viewBox': '0 0 100 100',
        'paths': {'lats': 'M 0 0 L 10 10 Z'}
      }
    });
  });

  group('ExercisePickerSheet & ExerciseDetailSheet UI Widget Tests', () {
    testWidgets('ExercisePickerSheet displays search bar, dynamic category & equipment chips, and list',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Header
      expect(find.text('EXERCISE LIBRARY'), findsOneWidget);

      // Check Search bar
      expect(find.byType(TextField), findsOneWidget);

      // Check Category Chips
      expect(find.textContaining('Chest'), findsWidgets);
      expect(find.textContaining('Back'), findsWidgets);
      expect(find.textContaining('Arms'), findsWidgets);

      // Check Equipment Chips
      expect(find.textContaining('Barbell'), findsWidgets);
      expect(find.textContaining('Dumbbell'), findsWidgets);

      // Check Custom exercise bar
      expect(find.text('+ Create Custom Exercise'), findsOneWidget);
    });

    testWidgets('ExercisePickerSheet filters dynamically on search text entry',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), 'incline db');
      await tester.pumpAndSettle();

      // Verify filtered results contain Incline Dumbbell Press / Incline DB
      expect(find.textContaining('Incline'), findsWidgets);
    });

    testWidgets('ExerciseDetailSheet displays anatomical targets and instructions',
        (WidgetTester tester) async {
      const def = ExerciseDefinition(
        id: 'incline_db_press',
        name: 'Incline Dumbbell Press',
        category: 'Chest',
        bodyPart: 'Chest',
        equipment: 'Dumbbell',
        equipmentGroup: 'Dumbbell',
        targetMuscle: 'Chest',
        muscleGroup: 'Chest',
        secondaryMuscles: ['Shoulders', 'Triceps'],
        instructions: [
          'Set an incline bench to roughly 30 degrees.',
          'Press dumbbells vertically with full control.',
          'Lower to upper chest level for deep stretch.',
        ],
        exerciseType: ExerciseType.dumbbell,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseDetailSheet(definition: def),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      expect(find.text('CHEST'), findsWidgets);
      expect(find.text('DUMBBELL'), findsWidgets);

      // Verify Anatomical Section
      expect(find.text('ANATOMICAL TARGETS', skipOffstage: false), findsOneWidget);
      expect(find.text('Primary Agonist:', skipOffstage: false), findsOneWidget);
      expect(find.text('Shoulders, Triceps', skipOffstage: false), findsOneWidget);

      // Verify Instructions
      expect(find.text('EXECUTION & CUES', skipOffstage: false), findsOneWidget);
      expect(find.text('Set an incline bench to roughly 30 degrees.', skipOffstage: false), findsOneWidget);

      // Verify CTA
      expect(find.text('ADD TO WORKOUT', skipOffstage: false), findsOneWidget);
    });
  });
}
