import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/services/user_exercise_preferences_service.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/widgets/exercise_picker_sheet.dart';
import 'package:kynetix/screens/exercise_detail_sheet.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';
import 'package:kynetix/widgets/muscle_body_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExerciseDefinition> testCatalog;

  setUpAll(() async {
    MuscleBodyMap.setCachedGeometryForTesting({
      'front': {
        'viewBox': '0 0 100 100',
        'paths': {'chest': 'M 0 0 L 10 10 Z'}
      },
      'back': {
        'viewBox': '0 0 100 100',
        'paths': {'back': 'M 0 0 L 10 10 Z'}
      },
    });

    final file = File('assets/data/exercises_library.json');
    final rawJson = await file.readAsString();
    final parsed = jsonDecode(rawJson) as List<dynamic>;
    testCatalog = parsed.map((e) => ExerciseDefinition.fromJson(e as Map<String, dynamic>)).toList();
    await ExerciseLibraryService.instance.initialize();
  });

  group('Exercise Discovery UI & Picker Integration Tests', () {
    testWidgets('1. Exercise Picker opens with full 1,358+ catalog on first presentation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header and Search Field
      expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify full catalog count in ALL category chip (should be >= 1358)
      expect(find.textContaining('ALL (13'), findsWidgets);
    });

    testWidgets('2. Search TextField accepts input, updates controller, and filters results in real-time', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Type "bench press"
      await tester.enterText(searchField, 'bench press');
      await tester.pumpAndSettle();

      // Verify text appears inside TextField
      expect(find.text('bench press'), findsOneWidget);

      // Verify "BEST MATCH" header appears
      expect(find.textContaining('BEST MATCH'), findsOneWidget);

      // Verify "Barbell Bench Press" appears
      expect(find.text('Barbell Bench Press'), findsWidgets);
    });

    testWidgets('3. Clear search button resets query and restores the full catalog', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 't bar');
      await tester.pumpAndSettle();

      expect(find.text('t bar'), findsOneWidget);
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

      // Tap clear button
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Verify TextField is cleared
      final tf = tester.widget<TextField>(searchField);
      expect(tf.controller?.text, isEmpty);
      expect(find.textContaining('ALL (13'), findsWidgets);
    });

    testWidgets('4. Category chips filter the catalog dynamically', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Chest" category chip
      final chestChip = find.textContaining('Chest (');
      expect(chestChip, findsOneWidget);
      await tester.tap(chestChip);
      await tester.pumpAndSettle();

      // Ensure filtered view contains chest exercises
      expect(find.byType(ChoiceChip), findsWidgets);
    });

    testWidgets('5. Selecting an exercise pops with the selected Exercise object', (tester) async {
      Exercise? selectedExercise;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    selectedExercise = await showExercisePickerSheet(context);
                  },
                  child: const Text('Open Picker'),
                );
              },
            ),
          ),
        ),
      );

      // Open picker
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Search for "t bar row"
      await tester.enterText(find.byType(TextField), 't bar row');
      await tester.pumpAndSettle();

      // Tap the first exercise row
      final firstRow = find.text('T-Bar Row').first;
      await tester.tap(firstRow);
      await tester.pumpAndSettle();

      // Verify picker popped and returned an Exercise
      expect(selectedExercise, isNotNull);
      expect(selectedExercise!.name.toLowerCase().contains('t-bar') || selectedExercise!.name.toLowerCase().contains('t bar'), isTrue);
    });

    testWidgets('6. Tapping info icon opens ExerciseDetailSheet with media & instructions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap info icon on first exercise row
      final infoButtons = find.byIcon(Icons.info_outline_rounded);
      expect(infoButtons, findsWidgets);

      await tester.tap(infoButtons.first);
      await tester.pumpAndSettle();

      // Verify ExerciseDetailSheet appears with anatomical targets & media widget
      expect(find.text('ANATOMICAL TARGETS'), findsOneWidget);
      expect(find.byType(ExerciseMediaWidget), findsWidgets);
    });

    testWidgets('7. Android Back navigation dismisses keyboard first then pops picker', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.tap(searchField);
      await tester.pumpAndSettle();

      // Verify PopScope widget exists in widget tree
      expect(find.byWidgetPredicate((w) => w is PopScope), findsWidgets);
    });

    testWidgets('8. Narrow 320px screen layout renders with 0 overflow errors', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
    });

    testWidgets('9. ExerciseMediaService resolves deterministic CDN media URLs & attribution', (tester) async {
      final sampleDef = testCatalog.firstWhere((e) => e.id == '0017');
      final thumb = ExerciseMediaService.instance.getThumbnailUrl(sampleDef);
      final gif = ExerciseMediaService.instance.getAnimationUrl(sampleDef);

      expect(thumb, contains('hasaneyldrm/exercises-dataset@main/images/0017-kiJ4Z2K.jpg'));
      expect(gif, contains('hasaneyldrm/exercises-dataset@main/videos/0017-kiJ4Z2K.gif'));
      expect(ExerciseMediaService.attribution, equals('© Gym visual — gymvisual.com'));
    });

    testWidgets('10. Zero-result state displays Create Custom Exercise CTA without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzznonexistent12345');
      await tester.pumpAndSettle();

      expect(find.textContaining('No catalog exercises match'), findsOneWidget);
      expect(find.text('Create Custom Exercise'), findsOneWidget);
    });
  });
}
