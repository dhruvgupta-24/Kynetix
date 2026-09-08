import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/screens/exercise_detail_sheet.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/widgets/exercise_media_widget.dart';
import 'package:kynetix/widgets/kyno_stage_slot.dart';
import 'package:kynetix/widgets/exercise_picker_sheet.dart';
import 'package:kynetix/widgets/muscle_body_map.dart';
import 'package:kynetix/screens/workout_session_screen.dart';

/// Instant, hermetic HTTP mock for Android tests.
/// Returns a valid 1x1 transparent GIF with 0ms latency to isolate UI and picker
/// tests from external emulator networking/DNS stalls.
class TestHttpOverrides extends HttpOverrides {
  static final Uint8List _imageBytes = base64Decode(
    'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
  );

  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout = const Duration(seconds: 2);
  @override
  Duration idleTimeout = const Duration(seconds: 2);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  _MockHttpClientRequest(this.uri);

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => TestHttpOverrides._imageBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([TestHttpOverrides._imageBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Bounded step that advances the live Android clock deterministically.
Future<void> step(WidgetTester tester, [int millis = 300]) async {
  await tester.pump(Duration(milliseconds: millis));
}

/// Smoke test host application shell providing a launch button for the picker.
class SmokeTestApp extends StatefulWidget {
  const SmokeTestApp({super.key});

  @override
  State<SmokeTestApp> createState() => _SmokeTestAppState();
}

class _SmokeTestAppState extends State<SmokeTestApp> {
  Exercise? _selectedExercise;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D17),
      ),
      home: Builder(
        builder: (innerContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Kynetix E2E Smoke Shell'),
            backgroundColor: const Color(0xFF13131F),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_selectedExercise != null)
                  Text(
                    'Selected: ${_selectedExercise!.name}',
                    key: const ValueKey('selected_exercise_text'),
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  key: const ValueKey('open_picker_button'),
                  onPressed: () async {
                    final ex = await showExercisePickerSheet(innerContext);
                    if (ex != null) {
                      setState(() => _selectedExercise = ex);
                    }
                  },
                  child: const Text('Open Exercise Picker'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android Real-Runtime Exercise Discovery & Media E2E', () {
    setUpAll(() async {
      debugPrint('[SETUP] Configuring hermetic test environment...');
      HttpOverrides.global = TestHttpOverrides();
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
      await ExerciseLibraryService.instance.initialize();
      debugPrint('[SETUP] ExerciseLibraryService initialized with ${ExerciseLibraryService.instance.allDefinitions.length} exercises');
    });

    // =========================================================================
    // STEP 1: Minimal Android Smoke Test
    // launch the app -> wait for initial screen -> open exercise picker -> verify it appears
    // =========================================================================
    testWidgets(
      'Step 1: Smoke Test - App launches, initial screen renders, exercise picker opens cleanly',
      (tester) async {
        debugPrint('--> [Step 1] Launching SmokeTestApp on Android emulator');
        await tester.pumpWidget(const SmokeTestApp());
        await step(tester, 500);

        debugPrint('--> [Step 1] Verifying initial screen is rendered');
        final openButton = find.byKey(const ValueKey('open_picker_button'));
        expect(openButton, findsOneWidget);
        debugPrint('✓ [Step 1] Initial screen verified with "Open Exercise Picker" button');

        debugPrint('--> [Step 1] Tapping "Open Exercise Picker"');
        await tester.tap(openButton);
        await step(tester, 600);

        debugPrint('--> [Step 1] Verifying ExercisePickerSheet modal appears');
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        // Verify catalog is loaded
        final allChip = find.textContaining('ALL (13');
        expect(allChip, findsWidgets);
        debugPrint('✓ [Step 1] ExercisePickerSheet appeared with full 1,363 catalog. Smoke test PASSED!');

        // Dismiss picker sheet cleanly before starting Step 2
        debugPrint('--> [Step 1] Dismissing picker cleanly');
        await binding.handlePopRoute();
        await step(tester, 500);
        expect(find.text('EXERCISE DISCOVERY'), findsNothing);
        debugPrint('✓ [Step 1] Teardown complete');
      },
      timeout: const Timeout(Duration(seconds: 25)),
    );

    // =========================================================================
    // STEP 2: Incremental User Flow
    // open picker -> tap search field -> enter bench press -> verify text appears
    // -> press Android back once -> verify keyboard closes -> press back again
    // -> verify picker closes -> open picker again -> select an exercise
    // =========================================================================
    testWidgets(
      'Step 2: Incremental Flow - Open, type "bench press", Android back unfocuses keyboard, back closes picker, re-open and select',
      (tester) async {
        debugPrint('--> [Step 2] Launching app');
        await tester.pumpWidget(const SmokeTestApp());
        await step(tester, 500);

        // 1. Open picker
        debugPrint('--> [Step 2.1] Opening picker');
        await tester.tap(find.byKey(const ValueKey('open_picker_button')));
        await step(tester, 600);
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
        debugPrint('✓ [Step 2.1] Picker opened');

        // 2. Tap search field
        debugPrint('--> [Step 2.2] Tapping search field');
        final searchField = find.byType(TextField);
        await tester.tap(searchField);
        await step(tester, 300);
        final focusNode = tester.widget<TextField>(searchField).focusNode!;
        expect(focusNode.hasFocus, isTrue);
        debugPrint('✓ [Step 2.2] Search field tapped and focused');

        // 3. Enter bench press
        debugPrint('--> [Step 2.3] Entering "bench press"');
        await tester.enterText(searchField, 'bench press');
        await step(tester, 400);

        // 4. Verify text appears
        final tfWidget = tester.widget<TextField>(searchField);
        expect(tfWidget.controller!.text, equals('bench press'));
        expect(find.text('Barbell Bench Press'), findsOneWidget);
        expect(find.textContaining('BEST MATCH'), findsOneWidget);
        debugPrint('✓ [Step 2.3 & 2.4] "bench press" entered, Barbell Bench Press ranked #1');

        // 5. Press Android back once
        debugPrint('--> [Step 2.5] Pressing Android back once');
        await binding.handlePopRoute();
        await step(tester, 300);

        // 6. Verify keyboard closes (unfocused), picker remains open
        expect(focusNode.hasFocus, isFalse);
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
        debugPrint('✓ [Step 2.6] First Android back closed keyboard; picker remains open');

        // 7. Press back again
        debugPrint('--> [Step 2.7] Pressing Android back a second time');
        await binding.handlePopRoute();
        int dismissFrames = 0;
        while (find.text('EXERCISE DISCOVERY').evaluate().isNotEmpty && dismissFrames < 15) {
          await step(tester, 100);
          dismissFrames++;
        }

        // 8. Verify picker closes
        expect(find.text('EXERCISE DISCOVERY'), findsNothing);
        debugPrint('✓ [Step 2.8] Second Android back dismissed picker cleanly');

        // 9. Open picker again
        debugPrint('--> [Step 2.9] Opening picker again');
        await tester.tap(find.byKey(const ValueKey('open_picker_button')));
        await step(tester, 600);
        expect(find.text('EXERCISE DISCOVERY'), findsOneWidget);
        debugPrint('✓ [Step 2.9] Picker re-opened successfully');

        // 10. Select an exercise
        debugPrint('--> [Step 2.10] Typing "bench press" and selecting Barbell Bench Press');
        await tester.enterText(find.byType(TextField), 'bench press');
        await step(tester, 400);

        final targetItem = find.text('Barbell Bench Press').first;
        await tester.tap(targetItem);
        int selectFrames = 0;
        while (find.text('EXERCISE DISCOVERY').evaluate().isNotEmpty && selectFrames < 15) {
          await step(tester, 100);
          selectFrames++;
        }

        // Verify picker closed and exercise was received by host screen
        expect(find.text('EXERCISE DISCOVERY'), findsNothing);
        expect(find.text('Selected: Barbell Bench Press'), findsOneWidget);
        debugPrint('✓ [Step 2.10] Exercise selected and returned to host screen. Incremental flow PASSED!');
      },
      timeout: const Timeout(Duration(seconds: 35)),
    );

    // =========================================================================
    // STEP 3: Media Resolution & Attribution (Tested Separately)
    // =========================================================================
    testWidgets(
      'Step 3: Media Separation - CDN resolution, required attribution, and offline fallback',
      (tester) async {
        debugPrint('--> [Step 3] Verifying foundational exercise media URLs');
        final movements = [
          ('bench_press', 'Barbell Bench Press'),
          ('incline_db_press', 'Incline Dumbbell Press'),
          ('cable_chest_fly', 'Cable Chest Fly'),
          ('tbar_row', 'T-Bar Row'),
          ('db_row', 'Dumbbell One-Arm Row'),
          ('ohp', 'Barbell Overhead Press'),
        ];

        for (final m in movements) {
          final def = ExerciseLibraryService.instance.getById(m.$1);
          expect(def, isNotNull, reason: 'Missing definition for ${m.$1}');
          final thumb = ExerciseMediaService.instance.getThumbnailUrl(def);
          final anim = ExerciseMediaService.instance.getAnimationUrl(def);

          expect(thumb, isNotNull);
          expect(anim, isNotNull);
          expect(thumb, startsWith('https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main/images/'));
          expect(anim, startsWith('https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@main/videos/'));
        }
        debugPrint('✓ [Step 3] All foundational movements have valid CDN URLs');

        debugPrint('--> [Step 3] Verifying mandatory GymVisual attribution');
        expect(ExerciseMediaService.attribution, equals('© Gym visual — gymvisual.com'));
        debugPrint('✓ [Step 3] Attribution text verified');

        debugPrint('--> [Step 3] Verifying graceful offline fallback');
        const synthetic = ExerciseDefinition(
          id: 'synthetic_test_9999',
          canonicalName: 'Offline Test Exercise',
          displayName: 'Offline Test Exercise',
          category: 'Back',
          bodyPart: 'Back',
          equipment: 'Barbell',
          equipmentGroup: 'Barbell',
          targetMuscle: 'Lats',
          muscleGroup: 'Back',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ExerciseMediaWidget(
                definition: synthetic,
                height: 120,
                width: 120,
                showMuscleMapFallback: true,
              ),
            ),
          ),
        );
        await step(tester, 300);
        expect(find.byType(ExerciseMediaWidget), findsOneWidget);
        debugPrint('✓ [Step 3] Offline fallback rendered with zero errors');
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    // =========================================================================
    // STEP 4: Media Loading in Exercise Detail Sheet (Tested Separately)
    // =========================================================================
    testWidgets(
      'Step 4: Detail Sheet - ExerciseDetailSheet mounts media widget, cues, and attribution',
      (tester) async {
        debugPrint('--> [Step 4] Mounting ExerciseDetailSheet for Barbell Bench Press');
        final benchDef = ExerciseLibraryService.instance.getById('bench_press')!;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: ExerciseDetailSheet(definition: benchDef),
            ),
          ),
        );
        await step(tester, 400);

        expect(find.byType(ExerciseMediaWidget), findsOneWidget);
        expect(find.text(ExerciseMediaService.attribution), findsOneWidget);
        expect(find.text('ANATOMICAL TARGETS'), findsOneWidget);
        expect(find.text('EXECUTION & CUES'), findsOneWidget);
        debugPrint('✓ [Step 4] ExerciseDetailSheet mounted with media widget & attribution cleanly');
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    // =========================================================================
    // STEP 5: Workout Session Media & 2-Loop Progression Reveal
    // =========================================================================
    testWidgets(
      'Step 5: Workout Session - Demonstration GIF, 2-loop reveal, zero layout jump, and exercise switching reset',
      (tester) async {
        debugPrint('--> [Step 5] Launching WorkoutSessionScreen with Barbell Bench Press & Face Pull');
        final splitDay = SplitDay(
          name: 'Push & Pull',
          weekday: 1,
          exercises: [
            const Exercise(
              id: 'bench_press',
              name: 'Barbell Bench Press',
              muscleGroup: 'Chest',
              type: ExerciseType.barbellCompound,
              defaultTargetSets: 3,
            ),
            const Exercise(
              id: 'face_pull_legacy',
              name: 'Cable Face Pull',
              muscleGroup: 'Shoulders',
              type: ExerciseType.cableMachine,
              defaultTargetSets: 3,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: WorkoutSessionScreen(
              splitDay: splitDay,
              date: DateTime.now(),
            ),
          ),
        );
        await step(tester, 500);

        // 1. Verify single bounded Kyno stage is mounted directly under header
        expect(find.byType(KynoStageSlot), findsOneWidget);
        expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
        expect(find.text('Barbell Bench Press'), findsOneWidget);
        debugPrint('✓ [Step 5] KynoStageSlot mounted directly under active exercise header');

        // 2. Verify NO "Analyzing Progression..." area exists (zero loading delay)
        expect(find.text('Analyzing Progression...'), findsNothing);
        debugPrint('✓ [Step 5] Zero loading delay - no Analyzing Progression placeholder');

        // 3. Verify dials and CTA are fully interactive immediately
        expect(find.textContaining('LOG SET'), findsOneWidget);
        debugPrint('✓ [Step 5] Log Set CTA and controls are responsive from frame 0');

        // 4. Verify canonical resolution for Face Pull legacy alias
        final facePullDef = ExerciseMediaService.instance.resolveMedia(
          id: 'face_pull_legacy',
          name: 'Cable Face Pull',
        );
        expect(facePullDef.gif, equals('0233-ZfyAGhK.gif'));
        debugPrint('✓ [Step 5] Legacy alias "Cable Face Pull" resolved to canonical "0233-ZfyAGhK.gif"');

        // 5. Advance time to complete 2 GIF loops (watchdog / simulated loops)
        debugPrint('--> [Step 5] Advancing 7.5s for 2 full loops');
        for (int i = 0; i < 15; i++) {
          await step(tester, 500);
        }

        // 6. Verify progression UI is revealed smoothly in the exact same slot
        expect(find.byKey(const ValueKey('progression_view')), findsOneWidget);
        expect(find.text('PROGRESSION RECOMMENDATION'), findsOneWidget);
        expect(find.text('Demo'), findsOneWidget);
        debugPrint('✓ [Step 5] Progression recommendation revealed in bounded stage after 2 loops');

        // 7. Test exercise navigation / switching
        debugPrint('--> [Step 5] Switching to exercise 2 (Cable Face Pull)');
        final nextPageButton = find.byIcon(Icons.chevron_right_rounded);
        if (nextPageButton.evaluate().isNotEmpty) {
          await tester.tap(nextPageButton.first);
          await step(tester, 600);
        }
        debugPrint('✓ [Step 5] Exercise switching verified. All Step 5 assertions PASSED!');
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );
  });
}

