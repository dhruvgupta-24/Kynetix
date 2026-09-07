import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/exercise_detail_sheet.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';
import 'package:kynetix/widgets/exercise_picker_sheet.dart';

/// Bounded pump helper that prevents infinite hanging when network images or
/// looped animations are active on real Android devices.
Future<void> pumpBounded(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 100),
  Duration maxDuration = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(maxDuration);
  do {
    await tester.pump(step);
    if (DateTime.now().isAfter(end)) break;
  } while (tester.binding.hasScheduledFrame);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android Real-Runtime Exercise Discovery & Media E2E', () {
    setUpAll(() async {
      await ExerciseLibraryService.instance.initialize();
    });

    testWidgets(
      '1. Catalog loads 1,358+ exercises deterministically on initial presentation',
      (tester) async {
        final count = ExerciseLibraryService.instance.allDefinitions.length;
        expect(count, greaterThanOrEqualTo(1358));
        debugPrint('✓ Android Runtime Catalog Count: $count exercises loaded');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      '2. Picker UI: text input, real-time filtering, clear, and category filter',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExercisePickerSheet(),
            ),
          ),
        );
        await pumpBounded(tester);

        // Verify full catalog shown immediately in the header
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
        expect(find.textContaining('ALL (13'), findsWidgets);

        // Tap search field to focus and open keyboard
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.tap(searchField);
        await pumpBounded(tester);

        // Physically type "bench press"
        await tester.enterText(searchField, 'bench press');
        await pumpBounded(tester);

        // Confirm text entered in TextField
        final textFieldWidget = tester.widget<TextField>(searchField);
        expect(textFieldWidget.controller!.text, equals('bench press'));

        // Confirm results update while typing
        expect(find.text('Barbell Bench Press'), findsOneWidget);
        expect(find.textContaining('BEST MATCH'), findsOneWidget);

        // Clear search
        final clearBtn = find.byIcon(Icons.close_rounded);
        expect(clearBtn, findsWidgets);
        await tester.tap(clearBtn.first);
        await pumpBounded(tester);
        expect(textFieldWidget.controller!.text, isEmpty);

        // Filter by Category chip
        final chestChip = find.widgetWithText(FilterChip, 'Chest');
        if (chestChip.evaluate().isNotEmpty) {
          await tester.tap(chestChip.first);
          await pumpBounded(tester);
          expect(find.byType(ListView), findsOneWidget);
        }
        debugPrint('✓ Search input, filtering, and clearing verified on Android runtime');
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '3. Android Back navigation: first dismisses keyboard, second dismisses picker',
      (tester) async {
        bool pickerDismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    await showExercisePickerSheet(context);
                    pickerDismissed = true;
                  },
                  child: const Text('Launch Picker'),
                ),
              ),
            ),
          ),
        );
        await pumpBounded(tester);

        // Launch picker
        await tester.tap(find.text('Launch Picker'));
        await pumpBounded(tester);
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);

        // Focus search field
        final searchField = find.byType(TextField);
        await tester.tap(searchField);
        await pumpBounded(tester);

        final focusNode = tester.widget<TextField>(searchField).focusNode!;
        expect(focusNode.hasFocus, isTrue);

        // First Android Back event: should unfocus keyboard, but NOT pop picker
        await binding.handlePopRoute();
        await pumpBounded(tester);

        expect(focusNode.hasFocus, isFalse);
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
        expect(pickerDismissed, isFalse);

        // Second Android Back event: should dismiss picker
        await binding.handlePopRoute();
        await pumpBounded(tester);

        expect(pickerDismissed, isTrue);
        expect(find.text('EXERCISE DISCOVERY'), findsNothing);
        debugPrint('✓ Android Back button sequence verified (keyboard -> modal)');
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '4. Repeatedly opening and closing picker does not hang or thrash UI thread',
      (tester) async {
        for (int i = 0; i < 5; i++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showExercisePickerSheet(context),
                    child: Text('Open $i'),
                  ),
                ),
              ),
            ),
          );
          await pumpBounded(tester);

          await tester.tap(find.text('Open $i'));
          await pumpBounded(tester);
          expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);

          // Tap close button
          final closeBtn = find.byIcon(Icons.close_rounded).first;
          await tester.tap(closeBtn);
          await pumpBounded(tester);
          expect(find.text('EXERCISE DISCOVERY'), findsNothing);
        }
        debugPrint('✓ Repeated 5x open/close cycle completed smoothly with 0 hangs');
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '5. Foundational exercises return expected #1 and verify media CDN URLs',
      (tester) async {
        final testCases = [
          ('bench press', 'Barbell Bench Press'),
          ('incline db press', 'Incline Dumbbell Press'),
          ('cable chest fly', 'Cable Fly'),
          ('pec deck', 'Butterfly / Pec Deck'),
          ('t bar row', 'T-Bar Row'),
          ('db row', 'Dumbbell One-Arm Row'),
          ('ohp', 'Barbell Overhead Press'),
          ('rdl', 'Barbell Romanian Deadlift'),
        ];

        for (final testCase in testCases) {
          final query = testCase.$1;
          final expectedDisplayName = testCase.$2;
          final results = ExerciseLibraryService.instance.searchDetailed(query: query);
          expect(results.isNotEmpty, isTrue, reason: 'No results for $query');
          final top = results.first;
          expect(top.definition.displayName, equals(expectedDisplayName),
              reason: 'Query "$query" expected "$expectedDisplayName" but got "${top.definition.displayName}"');

          final thumb = ExerciseMediaService.instance.getThumbnailUrl(top.definition);
          final anim = ExerciseMediaService.instance.getAnimationUrl(top.definition);
          expect(thumb, isNotNull);
          expect(anim, isNotNull);
          expect(thumb, startsWith('https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main/images/'));
          expect(anim, startsWith('https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main/videos/'));
        }
        debugPrint('✓ Foundational exercises ranking & media resolution verified');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      '6. Detail sheet displays media animation, attribution, and instructions',
      (tester) async {
        final benchDef = ExerciseLibraryService.instance.getById('bench_press')!;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExerciseDetailSheet(definition: benchDef),
            ),
          ),
        );
        await pumpBounded(tester);

        // Confirm media widget is rendered with attribution
        expect(find.byType(ExerciseMediaWidget), findsOneWidget);
        expect(find.text(ExerciseMediaService.attribution), findsOneWidget);
        expect(find.text('ANATOMICAL TARGETS'), findsOneWidget);
        expect(find.text('EXECUTION & CUES'), findsOneWidget);
        debugPrint('✓ ExerciseDetailSheet media and attribution verified on Android');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      '7. Offline fallback works gracefully when media is missing or fails',
      (tester) async {
        const dummyDef = ExerciseDefinition(
          id: 'non_existent_exercise_9999',
          canonicalName: 'Imaginary Exercise',
          displayName: 'Imaginary Exercise',
          category: 'Chest',
          bodyPart: 'Chest',
          equipment: 'Bodyweight',
          equipmentGroup: 'Bodyweight',
          targetMuscle: 'Pectorals',
          muscleGroup: 'Chest',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExerciseMediaWidget(
                definition: dummyDef,
                height: 120,
                width: 120,
                showMuscleMapFallback: true,
              ),
            ),
          ),
        );
        await pumpBounded(tester);

        // Confirm fallback renders without unhandled exceptions
        expect(find.byType(ExerciseMediaWidget), findsOneWidget);
        debugPrint('✓ Offline fallback verified without crashing');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      '8. Add Exercise flow: picker adds exercise to active workout session',
      (tester) async {
        final initialSessionExercises = <Exercise>[
          const Exercise(
            id: 'squat',
            name: 'Barbell Back Squat',
            muscleGroup: 'Legs',
            type: ExerciseType.barbellCompound,
          ),
        ];

        Exercise? pickedExercise;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    final picked = await showExercisePickerSheet(
                      context,
                      excludeIds: initialSessionExercises.map((e) => e.id).toSet(),
                    );
                    if (picked != null) {
                      pickedExercise = picked;
                      initialSessionExercises.add(picked);
                    }
                  },
                  child: const Text('Add Exercise Button'),
                ),
              ),
            ),
          ),
        );
        await pumpBounded(tester);

        await tester.tap(find.text('Add Exercise Button'));
        await pumpBounded(tester);

        // Search for "t bar row"
        await tester.enterText(find.byType(TextField), 't bar row');
        await pumpBounded(tester);

        // Tap T-Bar Row
        await tester.tap(find.text('T-Bar Row').first);
        await pumpBounded(tester);

        expect(pickedExercise, isNotNull);
        expect(pickedExercise!.name.toLowerCase().contains('t-bar') || pickedExercise!.name.toLowerCase().contains('t bar'), isTrue);
        expect(initialSessionExercises.length, equals(2));
        expect(initialSessionExercises.any((e) => e.id == pickedExercise!.id), isTrue);
        debugPrint('✓ Add Exercise flow completed successfully on Android');
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '9. Replace Exercise flow: replaces targeted exercise cleanly',
      (tester) async {
        final sessionExercises = <Exercise>[
          const Exercise(
            id: 'bench_press',
            name: 'Barbell Bench Press',
            muscleGroup: 'Chest',
            type: ExerciseType.barbellCompound,
          ),
          const Exercise(
            id: 'squat',
            name: 'Barbell Back Squat',
            muscleGroup: 'Legs',
            type: ExerciseType.barbellCompound,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    final currentIds = sessionExercises.map((e) => e.id).toSet()..remove('bench_press');
                    final picked = await showExercisePickerSheet(
                      context,
                      excludeIds: currentIds,
                    );
                    if (picked != null) {
                      final idx = sessionExercises.indexWhere((e) => e.id == 'bench_press');
                      if (idx != -1) {
                        sessionExercises[idx] = picked;
                      }
                    }
                  },
                  child: const Text('Replace Button'),
                ),
              ),
            ),
          ),
        );
        await pumpBounded(tester);

        await tester.tap(find.text('Replace Button'));
        await pumpBounded(tester);

        // Search and pick Incline Dumbbell Bench Press
        await tester.enterText(find.byType(TextField), 'incline db press');
        await pumpBounded(tester);

        await tester.tap(find.text('Incline Dumbbell Press').first);
        await pumpBounded(tester);

        expect(sessionExercises.length, equals(2));
        expect(sessionExercises[0].name, equals('Incline Dumbbell Press'));
        expect(sessionExercises[1].name, equals('Barbell Back Squat'));
        debugPrint('✓ Replace Exercise flow completed successfully on Android');
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  });
}
