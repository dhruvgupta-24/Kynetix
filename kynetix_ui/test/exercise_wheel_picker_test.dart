import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/widgets/exercise_execution_input_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testExercise = Exercise(
    id: 'test_bench',
    name: 'Barbell Bench Press',
    muscleGroup: 'Chest',
    type: ExerciseType.barbellCompound,
  );

  group('ExerciseExecutionInputView 3D Wheel Pickers', () {
    testWidgets('Renders 3D wheels for weight and reps with quick-adjust buttons', (tester) async {
      double selectedWeight = 60.0;
      int selectedReps = 8;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ExerciseExecutionInputView(
                  exercise: testExercise,
                  selectedWeight: selectedWeight,
                  selectedReps: selectedReps,
                  onWeightChanged: (w) => setState(() => selectedWeight = w),
                  onRepsChanged: (r) => setState(() => selectedReps = r),
                  onExternalLoadChanged: (_) {},
                  onDurationChanged: (_) {},
                  onDistanceChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );

      // Verify header titles
      expect(find.text('WEIGHT (KG)'), findsOneWidget);
      expect(find.text('REPS SELECTOR'), findsOneWidget);

      // Verify quick-adjust buttons
      expect(find.text('-5'), findsNWidgets(2)); // weight and reps
      expect(find.text('-2.5'), findsOneWidget);
      expect(find.text('+2.5'), findsOneWidget);
      expect(find.text('+5'), findsNWidgets(2)); // weight and reps
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);

      // Verify selected values in wheels
      expect(find.text('60.0 kg'), findsOneWidget);
      expect(find.text('8 reps'), findsOneWidget);

      // Tap +2.5 kg button
      await tester.tap(find.text('+2.5'));
      await tester.pumpAndSettle();
      expect(selectedWeight, 62.5);
      expect(find.text('62.5 kg'), findsOneWidget);

      // Tap +1 rep button
      await tester.tap(find.text('+1'));
      await tester.pumpAndSettle();
      expect(selectedReps, 9);
      expect(find.text('9 reps'), findsOneWidget);

      // Tap -5 kg button on weight side
      await tester.tap(find.text('-5').first);
      await tester.pumpAndSettle();
      expect(selectedWeight, 57.5);
      expect(find.text('57.5 kg'), findsOneWidget);

      // Tap -1 rep button
      await tester.tap(find.text('-1'));
      await tester.pumpAndSettle();
      expect(selectedReps, 8);
      expect(find.text('8 reps'), findsOneWidget);
    });

    testWidgets('Dragging weight and reps wheels scrolls and updates selected values', (tester) async {
      double selectedWeight = 50.0;
      int selectedReps = 10;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ExerciseExecutionInputView(
                  exercise: testExercise,
                  selectedWeight: selectedWeight,
                  selectedReps: selectedReps,
                  onWeightChanged: (w) => setState(() => selectedWeight = w),
                  onRepsChanged: (r) => setState(() => selectedReps = r),
                  onExternalLoadChanged: (_) {},
                  onDurationChanged: (_) {},
                  onDistanceChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('50.0 kg'), findsOneWidget);
      expect(find.text('10 reps'), findsOneWidget);

      // Drag weight wheel upwards (to select higher weight)
      final weightWheel = find.byType(ListWheelScrollView).first;
      await tester.drag(weightWheel, const Offset(0, -76)); // ~2 items extent (38 * 2)
      await tester.pumpAndSettle();

      // Weight should have increased
      expect(selectedWeight, greaterThan(50.0));

      // Drag reps wheel downwards (to select lower reps)
      final repsWheel = find.byType(ListWheelScrollView).at(1);
      await tester.drag(repsWheel, const Offset(0, 76)); // ~2 items extent down
      await tester.pumpAndSettle();

      // Reps should have decreased
      expect(selectedReps, lessThan(10));
    });

    testWidgets('3D Wheel Picker enforces size and depth hierarchy on visible items', (tester) async {
      double selectedWeight = 60.0;
      int selectedReps = 10;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseExecutionInputView(
              exercise: testExercise,
              selectedWeight: selectedWeight,
              selectedReps: selectedReps,
              onWeightChanged: (w) => selectedWeight = w,
              onRepsChanged: (r) => selectedReps = r,
              onExternalLoadChanged: (_) {},
              onDurationChanged: (_) {},
              onDistanceChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify visible items in the weight wheel
      expect(find.text('60.0 kg'), findsOneWidget); // Centered
      expect(find.text('59.5 kg'), findsOneWidget); // -1 Adjacent
      expect(find.text('60.5 kg'), findsOneWidget); // +1 Adjacent
      expect(find.text('59.0 kg'), findsOneWidget); // -2 Second adjacent
      expect(find.text('61.0 kg'), findsOneWidget); // +2 Second adjacent

      // Inspect Transform.scale on the items
      final centerTransform = tester.widget<Transform>(
        find.ancestor(of: find.text('60.0 kg'), matching: find.byType(Transform)).first,
      );
      final adjacentTransform = tester.widget<Transform>(
        find.ancestor(of: find.text('60.5 kg'), matching: find.byType(Transform)).first,
      );
      final secondAdjacentTransform = tester.widget<Transform>(
        find.ancestor(of: find.text('61.0 kg'), matching: find.byType(Transform)).first,
      );

      // Centered item scale is ~1.42 (magnified)
      final centerScale = centerTransform.transform.storage[0];
      final adjacentScale = adjacentTransform.transform.storage[0];
      final secondAdjacentScale = secondAdjacentTransform.transform.storage[0];

      expect(centerScale, greaterThan(1.35));
      expect(adjacentScale, lessThan(centerScale));
      expect(secondAdjacentScale, lessThan(adjacentScale));

      // Inspect Opacity falloff
      final centerOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('60.0 kg'), matching: find.byType(Opacity)).first,
      );
      final adjacentOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('60.5 kg'), matching: find.byType(Opacity)).first,
      );
      final secondAdjacentOpacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('61.0 kg'), matching: find.byType(Opacity)).first,
      );

      expect(centerOpacity.opacity, 1.0);
      expect(adjacentOpacity.opacity, lessThan(1.0));
      expect(secondAdjacentOpacity.opacity, lessThan(adjacentOpacity.opacity));
    });

    testWidgets('Flinging the wheel triggers natural inertia and snaps to nearest valid value', (tester) async {
      double selectedWeight = 50.0;
      int selectedReps = 10;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ExerciseExecutionInputView(
                  exercise: testExercise,
                  selectedWeight: selectedWeight,
                  selectedReps: selectedReps,
                  onWeightChanged: (w) => setState(() => selectedWeight = w),
                  onRepsChanged: (r) => setState(() => selectedReps = r),
                  onExternalLoadChanged: (_) {},
                  onDurationChanged: (_) {},
                  onDistanceChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );

      final weightWheel = find.byType(ListWheelScrollView).first;
      // Fling upwards with velocity
      await tester.fling(weightWheel, const Offset(0, -200), 1000.0);
      await tester.pumpAndSettle();

      // Verify that weight has advanced and settled on a clean 0.5 kg increment
      expect(selectedWeight, greaterThan(50.0));
      expect((selectedWeight % 0.5).abs(), lessThan(0.001));
    });
  });
}
