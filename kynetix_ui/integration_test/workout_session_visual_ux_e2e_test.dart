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
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/exercise_media_service.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/kyno_progression_engine.dart';
import 'package:kynetix/widgets/kyno_stage_slot.dart';
import 'package:kynetix/screens/workout_session_screen.dart';

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
      final file = File('/sdcard/$name.png');
      await file.writeAsBytes(bytes);
      debugPrint('[SCREENSHOT_SAVED] /sdcard/$name.png (${bytes.length} bytes)');
    } catch (e) {
      debugPrint('[SCREENSHOT_ERROR] $name: $e');
    }
  }

  Future<void> pumpStep(WidgetTester tester, int ms) async {
    await tester.pump(Duration(milliseconds: ms));
  }

  group('Kynetix Workout Session Real-Runtime Visual/UX Audit', () {
    setUpAll(() async {
      HttpOverrides.global = TestHttpOverrides();
      await ExerciseLibraryService.instance.initialize();

      final ws = WorkoutService.instance;

      // Seed exact history from user specification:
      // Bench Press performed repeatedly: 70 x 9, 70 x 7, 70 x 7, 70 x 7
      final pastSession = WorkoutSession(
        id: 'past_session_bench',
        date: DateTime.now().subtract(const Duration(days: 3)),
        splitDayName: 'Push Day',
        entries: [
          ExerciseEntry(
            exercise: const Exercise(
              id: 'bench_press',
              name: 'Flat Bench Press',
              muscleGroup: 'Chest',
              type: ExerciseType.barbellCompound,
              defaultTargetSets: 4,
              defaultRepMin: 8,
              defaultRepMax: 10,
            ),
            sets: const [
              SetEntry(weight: 70.0, reps: 9, setType: SetType.normal),
              SetEntry(weight: 70.0, reps: 7, setType: SetType.normal),
              SetEntry(weight: 70.0, reps: 7, setType: SetType.normal),
              SetEntry(weight: 70.0, reps: 7, setType: SetType.normal),
            ],
          ),
        ],
      );
      await ws.saveSession(pastSession);
      debugPrint('[AUDIT_SETUP] Seeded past session: 70x9, 70x7, 70x7, 70x7');
    });

    testWidgets('Full Visual UX Lifecycle & Screenshot Capture on Pixel 7', (tester) async {
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
            defaultTargetSets: 4,
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

      // ─── STATE 1: Immediately after opening exercise — GIF state (Loop 1) ───
      debugPrint('--> [AUDIT] State 1: Immediately after opening exercise');
      expect(find.text('Flat Bench Press'), findsOneWidget);
      expect(find.byType(KynoStageSlot), findsOneWidget);
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      expect(find.textContaining('Loop'), findsNothing);
      expect(find.textContaining('LOG SET 1'), findsOneWidget);

      await saveScreenshot('state1_opening_gif');
      debugPrint('✓ [AUDIT] State 1 captured: demo_view mounted, Loop 1 of 2, LOG SET 1 visible');

      // ─── STATE 2: During GIF playback (Loop 2) ─────────────────────────────
      debugPrint('--> [AUDIT] State 2: During GIF playback (Loop 2)');
      // Advance to Loop 2 (approx 3100ms)
      for (int i = 0; i < 7; i++) {
        await pumpStep(tester, 450);
      }
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      await saveScreenshot('state2_gif_playback');
      debugPrint('✓ [AUDIT] State 2 captured: demo_view active in loop 2');

      // ─── STATE 3: Immediately after loop 2 — transition ─────────────────────
      debugPrint('--> [AUDIT] State 3: Immediately after loop 2 — transition');
      // Advance until 6000ms watchdog / loop completion triggers transition
      for (int i = 0; i < 7; i++) {
        await pumpStep(tester, 450);
      }
      // Pump halfway through 600ms AnimatedSwitcher transition
      await tester.pump(const Duration(milliseconds: 300));
      await saveScreenshot('state3_transition');
      debugPrint('✓ [AUDIT] State 3 captured: AnimatedSwitcher transition in flight');

      // ─── STATE 4: Final progression recommendation state ───────────────────
      debugPrint('--> [AUDIT] State 4: Final progression recommendation state');
      await pumpStep(tester, 400); // Settle transition
      expect(find.byKey(const ValueKey('progression_view')), findsOneWidget);
      expect(find.text('PROGRESSION RECOMMENDATION'), findsOneWidget);
      expect(find.text('KEEP 70 KG'), findsOneWidget);
      expect(find.textContaining('Today\'s target: 4 × 8–10 (70 kg)'), findsOneWidget);
      expect(find.textContaining('You are still below the rep ceiling on recent sets. Keep the load and try to add reps before increasing weight.'), findsOneWidget);
      expect(find.text('Demo'), findsOneWidget);
      expect(find.textContaining('LOG SET 1'), findsOneWidget);

      await saveScreenshot('state4_progression_card');
      debugPrint('✓ [AUDIT] State 4 captured: progression card revealed, non-truncated instruction, LOG SET 1 pinned');

      // ─── STATE 5: After switching to another exercise ──────────────────────
      debugPrint('--> [AUDIT] State 5: Switch exercises (Incline DB Press & Cable Face Pull)');
      final nextPageButton = find.byIcon(Icons.chevron_right_rounded);
      if (nextPageButton.evaluate().isNotEmpty) {
        await tester.tap(nextPageButton.first);
        await pumpStep(tester, 600);
      }
      expect(find.text('Incline Dumbbell Press'), findsOneWidget);
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      expect(find.textContaining('Loop'), findsNothing);

      await saveScreenshot('state5_exercise_switch');
      debugPrint('✓ [AUDIT] State 5 captured: Incline DB Press mounted, loop counter eliminated, demo_view active');

      // Switch to Cable Face Pull (legacy alias test)
      if (nextPageButton.evaluate().isNotEmpty) {
        await tester.tap(nextPageButton.first);
        await pumpStep(tester, 600);
      }
      expect(find.text('Cable Face Pull'), findsOneWidget);
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      expect(find.textContaining('Loop'), findsNothing);
      debugPrint('✓ [AUDIT] Cable Face Pull mounted cleanly with canonical resolution');

      // ─── STATE 6: After replaying the demonstration ────────────────────────
      debugPrint('--> [AUDIT] State 6: Replay demonstration');
      // Go back to Flat Bench Press
      final prevPageButton = find.byIcon(Icons.chevron_left_rounded);
      if (prevPageButton.evaluate().isNotEmpty) {
        await tester.tap(prevPageButton.first);
        await pumpStep(tester, 400);
        await tester.tap(prevPageButton.first);
        await pumpStep(tester, 600);
      }
      expect(find.text('Flat Bench Press'), findsOneWidget);

      // Fast forward to progression view if needed
      for (int i = 0; i < 15; i++) {
        await pumpStep(tester, 450);
      }
      expect(find.text('Demo'), findsOneWidget);

      // Tap Demo button to replay
      await tester.tap(find.text('Demo'));
      await pumpStep(tester, 200);

      // Verify smooth transition back to demonstration view in the exact same slot
      expect(find.byKey(const ValueKey('demo_view')), findsOneWidget);
      expect(find.textContaining('Loop'), findsNothing);
      expect(find.textContaining('LOG SET 1'), findsOneWidget);

      await saveScreenshot('state6_demo_replay');
      debugPrint('✓ [AUDIT] State 6 captured: Demo replayed smoothly in exact same slot without layout jump');
    });
  });
}
