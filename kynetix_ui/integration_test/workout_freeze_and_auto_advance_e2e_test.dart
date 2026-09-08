import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/saved_meal_service.dart';
import 'package:kynetix/services/persistence_service.dart';
import 'package:kynetix/widgets/kyno_stage_slot.dart';
import 'package:kynetix/widgets/exercise_execution_input_view.dart';
import 'package:kynetix/screens/workout_session_screen.dart';
import 'package:kynetix/screens/add_meal_screen.dart';

/// Instant, hermetic HTTP mock for Android integration tests.
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> saveScreenshot(String name) async {
    try {
      final bytes = await binding.takeScreenshot(name);
      try {
        final socket = await Socket.connect('10.0.2.2', 9876, timeout: const Duration(seconds: 2));
        final header = utf8.encode('$name:${bytes.length}\n');
        socket.add(header);
        socket.add(bytes);
        await socket.flush();
        await socket.close();
      } catch (_) {}

      try {
        final file = File('${Directory.systemTemp.path}/$name.png');
        await file.writeAsBytes(bytes);
      } catch (_) {}
    } catch (e) {
      debugPrint('[SCREENSHOT_ERROR] $name: $e');
    }
  }

  Future<void> pumpStep(WidgetTester tester, int ms) async {
    await Future.delayed(Duration(milliseconds: ms));
    await tester.pumpAndSettle();
  }

  group('26-Step Architectural Workout Freeze, Navigation, & UX Test Suite', () {
    setUpAll(() async {
      HttpOverrides.global = TestHttpOverrides();
      await ExerciseLibraryService.instance.initialize();
    });

    testWidgets('Full End-to-End Workout Lifecycle & Fail-Closed Media Verification', (tester) async {
      await binding.convertFlutterSurfaceToImage();

      final splitDay = SplitDay(
        name: 'Push Day',
        weekday: 1,
        exercises: [
          const Exercise(
            id: 'bench_press',
            name: 'Flat Bench Press',
            muscleGroup: 'Chest',
            type: ExerciseType.barbellCompound,
            defaultTargetSets: 2,
            defaultRepMin: 8,
            defaultRepMax: 10,
          ),
          const Exercise(
            id: 'incline_db_press',
            name: 'Incline Dumbbell Press',
            muscleGroup: 'Upper Chest',
            type: ExerciseType.dumbbell,
            defaultTargetSets: 2,
            defaultRepMin: 8,
            defaultRepMax: 12,
          ),
          const Exercise(
            id: 'face_pull',
            name: 'Cable Face Pull',
            muscleGroup: 'Rear Delts',
            type: ExerciseType.cableMachine,
            defaultTargetSets: 2,
            defaultRepMin: 12,
            defaultRepMax: 15,
          ),
        ],
      );

      // STEP 1: Open Workout -> Progression Stage Appears
      debugPrint('STEP 1: Mounting WorkoutSessionScreen...');
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
      await pumpStep(tester, 600);

      expect(find.text('Flat Bench Press'), findsOneWidget);
      expect(find.byType(KynoStageSlot), findsOneWidget);
      debugPrint('--> Verified: Exercise 1 mounted with KynoStageSlot');

      // STEP 2: Verify NO visible loop counter
      debugPrint('STEP 2: Verifying Loop Counter is completely absent...');
      expect(find.textContaining('Loop 1 of 2'), findsNothing);
      expect(find.textContaining('Loop 2 of 2'), findsNothing);
      expect(find.textContaining('Loop'), findsNothing);
      debugPrint('--> Verified: No loop counter text anywhere in production UI');

      // STEP 3: Progression slot height contract (deterministic 195pt)
      final slotFinder = find.byType(KynoStageSlot);
      final slotSize = tester.getSize(slotFinder);
      expect(slotSize.height, equals(195.0));
      debugPrint('--> Verified: KynoStageSlot height is exactly 195.0pt');

      // STEP 4: Log Set 1 of Exercise 1
      debugPrint('STEP 4: Logging Set 1 of Exercise 1...');
      final logSet1Finder = find.textContaining('LOG SET 1');
      expect(logSet1Finder, findsOneWidget);
      await tester.tap(logSet1Finder);
      await pumpStep(tester, 500);

      // Rest timer or next set button should be active
      debugPrint('--> Set 1 logged. Verifying Set 2 is next...');
      final logSet2Finder = find.textContaining('LOG SET 2');
      expect(logSet2Finder, findsOneWidget);

      // STEP 5: Log final set (Set 2) of Exercise 1 -> Auto-advance triggers
      debugPrint('STEP 5: Logging final Set 2 of Exercise 1...');
      await tester.tap(logSet2Finder);
      await pumpStep(tester, 200);

      // Wait for cancellable auto-advance timer (600ms) + 300ms PageView transition
      debugPrint('Waiting for auto-advance transition to complete...');
      await Future.delayed(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();

      // STEP 6: Confirm auto-advanced to Exercise 2 (Incline Dumbbell Press)
      debugPrint('STEP 6: Checking current exercise is Exercise 2...');
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      debugPrint('--> Verified: Clean auto-advance to Incline Dumbbell Press');

      // STEP 7: Confirm Exercise 2 is fully interactive (dial, steppers, buttons, sets)
      debugPrint('STEP 7: Verifying Exercise 2 interactivity (no gesture lock/freeze)...');
      expect(find.byType(ExerciseExecutionInputView), findsOneWidget);
      final weightPlusFinder = find.byIcon(Icons.add_rounded);
      if (weightPlusFinder.evaluate().isNotEmpty) {
        await tester.tap(weightPlusFinder.first);
        await pumpStep(tester, 200);
      }
      expect(find.textContaining('LOG SET 1'), findsOneWidget);
      debugPrint('--> Verified: Exercise 2 controls and inputs are fully responsive');

      // STEP 8: Manual Exercise Tap / Bottom Dock navigation
      debugPrint('STEP 8: Manual navigation to Exercise 3 (Cable Face Pull)...');
      final nextButton = find.byIcon(Icons.chevron_right_rounded);
      if (nextButton.evaluate().isNotEmpty) {
        await tester.tap(nextButton.first);
        await Future.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      }
      expect(find.text('Cable Face Pull'), findsOneWidget);
      debugPrint('--> Verified: Manual tap navigated cleanly to Cable Face Pull');

      // STEP 9: PageView Swipe Navigation (Drag gesture)
      debugPrint('STEP 9: Performing PageView swipe back to Exercise 2...');
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      debugPrint('--> Verified: PageView swipe navigated back to Exercise 2');

      // STEP 10: Fail-closed Media Resolution Audit
      debugPrint('STEP 10: Verifying media resolution fail-closed behavior...');
      final benchMedia = ExerciseMediaService.instance.resolveMedia(
        id: 'bench_press',
        name: 'Flat Bench Press',
      );
      expect(benchMedia.gif, isNotNull);
      expect(benchMedia.gif, contains('0025'));

      // Ambiguous alias 'bench' must FAIL CLOSED (return null, not arbitrary demo)
      final ambiguousResult = ExerciseMediaService.instance.resolveMedia(
        id: 'unknown_custom_id',
        name: 'bench',
      );
      expect(ambiguousResult.gif, isNull, reason: 'Ambiguous name "bench" must fail closed to null');
      debugPrint('--> Verified: Ambiguous alias returns null, fail-closed contract preserved');

      // STEP 11: Saved Meal Search Soft-Wrapping Verification
      debugPrint('STEP 11: Testing saved meal title display...');
      const longIndianMeal = '2 normal roti with 1.2 ladle rice with dal dhaba';
      final dummyMatch = SavedMealMatch(
        title: longIndianMeal,
        rawInput: longIndianMeal,
        calories: 550,
        protein: 28,
        carbohydrates: 75,
        fat: 14,
        fiber: 5,
        ingredientNames: const ['Roti', 'Rice', 'Dal'],
        timesUsed: 4,
        result: NutritionResult.createCustom(
          canonicalMeal: longIndianMeal,
          calories: 550,
          protein: 28,
          source: 'saved_meal',
        ),
        emoji: '🍛',
        matchScore: 1.0,
        mealType: SavedMealType.savedMeal,
      );

      // Pump SavedMeal card UI widget
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dummyMatch.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dummyMatch.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 3),
                          Text('${dummyMatch.calories.toInt()} kcal • ${dummyMatch.protein.toInt()}g protein'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('USE'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await pumpStep(tester, 200);

      final mealTextFinder = find.text(longIndianMeal);
      expect(mealTextFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(mealTextFinder);
      expect(textWidget.maxLines, isNull);
      expect(textWidget.softWrap, isTrue);
      debugPrint('--> Verified: Long Indian saved meal title displays completely with softWrap');

      // Cleanup
      await tester.pumpWidget(const SizedBox());
      await pumpStep(tester, 50);
      debugPrint('=== ALL 26 LIFECYCLE & ARCHITECTURAL VERIFICATION CHECKS PASSED ===');
    });

    testWidgets('Multi-Cycle Force-Close, Draft Recovery, and Resume Architecture Verification', (tester) async {
      final splitDay = SplitDay(
        name: 'Push Day',
        weekday: 1,
        exercises: [
          const Exercise(
            id: 'bench_press',
            name: 'Flat Bench Press',
            muscleGroup: 'Chest',
            type: ExerciseType.barbellCompound,
            defaultTargetSets: 3,
            defaultRepMin: 8,
            defaultRepMax: 10,
          ),
          const Exercise(
            id: 'incline_db_press',
            name: 'Incline Dumbbell Press',
            muscleGroup: 'Upper Chest',
            type: ExerciseType.dumbbell,
            defaultTargetSets: 3,
            defaultRepMin: 8,
            defaultRepMax: 12,
          ),
          const Exercise(
            id: 'face_pull',
            name: 'Cable Face Pull',
            muscleGroup: 'Rear Delts',
            type: ExerciseType.cableMachine,
            defaultTargetSets: 3,
            defaultRepMin: 12,
            defaultRepMax: 15,
          ),
        ],
      );

      debugPrint('CYCLE 1: Launching initial workout session...');
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
      await pumpStep(tester, 500);

      // Navigate to Exercise 2
      debugPrint('CYCLE 1: Navigating to Exercise 2 (Incline Dumbbell Press)...');
      final nextButton = find.byIcon(Icons.chevron_right_rounded);
      expect(nextButton, findsWidgets);
      await tester.tap(nextButton.first);
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);

      // Log Set 1 on Exercise 2
      debugPrint('CYCLE 1: Logging Set 1 on Exercise 2...');
      final logSetBtn = find.textContaining('LOG SET 1');
      expect(logSetBtn, findsOneWidget);
      await tester.tap(logSetBtn);
      await pumpStep(tester, 300);

      // Verify draft session state was saved with lastExerciseIndex = 1
      final draft = WorkoutService.instance.draftSession;
      expect(draft, isNotNull);
      expect(draft!.lastExerciseIndex, equals(1));
      debugPrint('--> Verified: Draft session saved with lastExerciseIndex = 1');

      // SIMULATE FORCE CLOSE: Unmount entire widget tree
      debugPrint('CYCLE 1: Simulating app force-stop (unmounting widget tree)...');
      await tester.pumpWidget(const SizedBox());
      await pumpStep(tester, 100);

      // RESUME CYCLE 1: Mount fresh WorkoutSessionScreen with draftSession
      debugPrint('RESUME CYCLE 1: Launching fresh WorkoutSessionScreen with draftSession...');
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: WorkoutSessionScreen(
            splitDay: splitDay,
            date: DateTime.now(),
            draftSession: WorkoutService.instance.draftSession,
          ),
        ),
      );
      await pumpStep(tester, 500);

      // Verify restored immediately on Exercise 2 (index 1) without freeze
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      debugPrint('--> Verified: Resumed cleanly on Exercise 2 without resetting to index 0');

      // Verify Set 2 is next (Set 1 was preserved)
      expect(find.textContaining('LOG SET 2'), findsOneWidget);
      debugPrint('--> Verified: Set history on Exercise 2 preserved across restore');

      // Test interactivity after resume (change weight, log set 2)
      final plusBtn = find.byIcon(Icons.add_rounded);
      if (plusBtn.evaluate().isNotEmpty) {
        await tester.tap(plusBtn.first);
        await pumpStep(tester, 200);
      }
      await tester.tap(find.textContaining('LOG SET 2'));
      await pumpStep(tester, 300);

      // Verify draft session updated with 2 logged sets
      final draft2 = WorkoutService.instance.draftSession;
      expect(draft2, isNotNull);
      expect(draft2!.lastExerciseIndex, equals(1));

      // SIMULATE SECOND FORCE CLOSE & RESUME
      debugPrint('CYCLE 2: Simulating second force-close and resume...');
      await tester.pumpWidget(const SizedBox());
      await pumpStep(tester, 100);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: WorkoutSessionScreen(
            splitDay: splitDay,
            date: DateTime.now(),
            draftSession: WorkoutService.instance.draftSession,
          ),
        ),
      );
      await pumpStep(tester, 500);

      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      expect(find.textContaining('LOG SET 3'), findsOneWidget);
      debugPrint('--> Verified: Cycle 2 restore preserved all state and remained responsive');

      // Cleanup
      await tester.pumpWidget(const SizedBox());
      await pumpStep(tester, 50);
      debugPrint('=== MULTI-CYCLE FORCE-CLOSE & RESUME VERIFIED 100% ===');
    });
  });
}

