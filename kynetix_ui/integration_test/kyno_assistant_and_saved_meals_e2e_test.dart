import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/screens/add_meal_screen.dart';
import 'package:kynetix/screens/kyno_assistant_screen.dart';
import 'package:kynetix/services/kyno_context_service.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/saved_meal_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/workout_service.dart';

class TestHttpOverrides extends HttpOverrides {
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
  static final List<int> _dummyBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  @override
  int get statusCode => 200;

  @override
  int get contentLength => _dummyBytes.length;

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
    final stream = Stream<List<int>>.fromIterable([_dummyBytes]);
    return stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
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
        final socket = await Socket.connect('10.0.2.2', 9876, timeout: const Duration(seconds: 4));
        final header = utf8.encode('$name:${bytes.length}\n');
        socket.add(header);
        socket.add(bytes);
        await socket.flush();
        await socket.close();
        debugPrint('[SCREENSHOT_STREAMED] $name -> host:9876 (${bytes.length} bytes)');
      } catch (e) {
        debugPrint('[SCREENSHOT_WARN] TCP streaming to host failed: $e');
      }

      // Also backup to system temp
      try {
        final f = File('${Directory.systemTemp.path}/$name.png');
        await f.writeAsBytes(bytes);
      } catch (_) {}
    } catch (e) {
      debugPrint('[SCREENSHOT_ERROR] $name: $e');
    }
  }

  Future<void> pumpStep(WidgetTester tester, [int ms = 400]) async {
    await tester.pump(Duration(milliseconds: ms));
  }

  group('Kynetix Unified Kyno Assistant & Saved Meal Reuse Android Runtime Verification', () {
    setUpAll(() async {
      HttpOverrides.global = TestHttpOverrides();
      NutritionHydrationGuard.instance.markComplete('pixel7_test_user');
      UserNutritionMemory.instance.setOwnerId('pixel7_test_user');
      MealMemory.instance.setOwnerId('pixel7_test_user');
      dayLogStore.clear();
      KynoContextService.instance.invalidate();
    });

    testWidgets('Full Kyno Assistant & Saved Meals End-to-End Suite on Pixel 7', (tester) async {
      // 0. Convert Flutter surface once for all screenshots
      await binding.convertFlutterSurfaceToImage();

      // ───────────────────────────────────────────────────────────────────────
      // PHASE 1 (TEST A) — Saved Meal Local-First Search & 1-Tap Reuse
      // ───────────────────────────────────────────────────────────────────────
      debugPrint('========== RUNNING TEST A: SAVED MEAL REUSE ==========');

      // Seed known remembered meal in dayLogStore
      final customMeal = NutritionResult.createCustom(
        canonicalMeal: 'Chicken and Sweet Potato',
        calories: 450,
        protein: 42,
        source: 'user_override',
      );
      final initialEntry = MealEntry(
        rawInput: 'Chicken and Sweet Potato',
        result: customMeal,
        addedAt: DateTime.now().subtract(const Duration(days: 1)),
        section: MealSection.lunch,
        dayOfWeek: 1,
        parsedFoods: const ['Chicken Breast', 'Sweet Potato'],
        finalSavedInput: 'Chicken and Sweet Potato',
      );
      final yesterdayLog = logFor(DateTime.now().subtract(const Duration(days: 1)));
      yesterdayLog.add(MealSection.lunch, initialEntry);
      await MealMemory.instance.store(
        'Chicken and Sweet Potato',
        customMeal,
        finalSavedInput: 'Chicken and Sweet Potato',
      );

      // Verify SavedMealService indexes it
      final initialSearch = SavedMealService.instance.search('chicken');
      expect(initialSearch.isNotEmpty, isTrue);
      expect(initialSearch.first.title, equals('Chicken and Sweet Potato'));

      // Open AddMealScreen
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: AddMealScreen(
            section: MealSection.lunch,
            date: DateTime.now(),
          ),
        ),
      );
      await pumpStep(tester, 500);

      // Enter partial query
      final inputField = find.byType(TextField).first;
      await tester.enterText(inputField, 'chick');
      await pumpStep(tester, 500);

      // Verify autocomplete suggestion appears with type badge
      expect(find.text('Chicken and Sweet Potato'), findsWidgets);
      expect(find.text('SAVED'), findsWidgets);
      expect(find.textContaining('450 kcal'), findsWidgets);
      expect(find.textContaining('42g protein'), findsWidgets);

      // Tap 1-tap [ USE ] button
      final useButton = find.text('USE');
      expect(useButton, findsWidgets);
      await tester.tap(useButton.first);
      await pumpStep(tester, 500);

      // Verify form is populated with exact remembered macros without AI call
      expect(find.text('Chicken and Sweet Potato'), findsWidgets);
      expect(find.textContaining('450'), findsWidgets);
      expect(find.textContaining('42'), findsWidgets);

      // Save meal to today's log
      final logMealBtn = find.text('Add to Log');
      await tester.tap(logMealBtn);
      await pumpStep(tester, 600);

      // Verify meal persisted in today's dayLog
      final todayLog = logFor(DateTime.now());
      expect(todayLog.entriesFor(MealSection.lunch).length, equals(1));
      final loggedItem = todayLog.entriesFor(MealSection.lunch).first;
      expect(loggedItem.protMid, equals(42.0));
      expect(loggedItem.calMid, equals(450.0));
      debugPrint('✓ [TEST A PASSED] Saved meal reused with exact macros without AI regeneration');

      await saveScreenshot('test_a_saved_meal_reuse');

      // ───────────────────────────────────────────────────────────────────────
      // PHASE 2 (TEST B) — Kyno Nutrition Query from Live Logged Data
      // ───────────────────────────────────────────────────────────────────────
      debugPrint('========== RUNNING TEST B: KYNO NUTRITION ==========');

      // Mount Kyno Assistant Screen
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: ThemeData.dark(),
          home: const KynoAssistantScreen(),
        ),
      );
      await pumpStep(tester, 500);

      // Ask question: "How much protein have I had today?"
      final chatInputB = find.byType(TextField).last;
      await tester.enterText(chatInputB, 'How much protein have I had today?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpStep(tester, 600);

      // Verify response contains verified logged protein: 42.0g
      expect(find.textContaining('42.0g protein'), findsWidgets);
      debugPrint('✓ [TEST B PASSED] Kyno reported exact logged protein (42.0g)');

      await saveScreenshot('test_b_kyno_nutrition');

      // ───────────────────────────────────────────────────────────────────────
      // PHASE 3 (TEST C) — Kyno Training Query from Live WorkoutService Session
      // ───────────────────────────────────────────────────────────────────────
      debugPrint('========== RUNNING TEST C: KYNO TRAINING ==========');

      // Log workout session: Barbell Bench Press (3 sets of 80kg x 8)
      final ex = Exercise(
        id: 'bench_press',
        name: 'Barbell Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
      );
      final session = WorkoutSession(
        id: 'ws_pixel7_test',
        date: DateTime.now(),
        splitDayName: 'Chest & Triceps',
        entries: [
          ExerciseEntry(
            exercise: ex,
            sets: const [
              SetEntry(weight: 80, reps: 8, setType: SetType.normal),
              SetEntry(weight: 80, reps: 8, setType: SetType.normal),
              SetEntry(weight: 80, reps: 7, setType: SetType.normal),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSession(session);
      KynoContextService.instance.invalidate();

      // Remount Kyno Assistant Screen with fresh training context
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: ThemeData.dark(),
          home: const KynoAssistantScreen(),
        ),
      );
      await pumpStep(tester, 500);

      // Ask: "What did I train today?"
      final chatInputC = find.byType(TextField).last;
      await tester.enterText(chatInputC, 'What did I train today?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpStep(tester, 600);

      // Verify answer matches actual workout
      expect(find.textContaining('Chest & Triceps'), findsWidgets);
      expect(find.textContaining('3 sets'), findsWidgets);
      debugPrint('✓ [TEST C PASSED] Kyno reported exact workout (Chest & Triceps, 3 sets)');

      await saveScreenshot('test_c_kyno_training');

      // ───────────────────────────────────────────────────────────────────────
      // PHASE 4 (TEST D) — Cross-Domain Query (Training + Nutrition)
      // ───────────────────────────────────────────────────────────────────────
      debugPrint('========== RUNNING TEST D: CROSS-DOMAIN ==========');

      // Ask: "I trained chest today. Am I eating enough protein to recover?"
      final chatInputD = find.byType(TextField).last;
      await tester.enterText(chatInputD, 'I trained chest today. Am I eating enough protein to recover?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpStep(tester, 600);

      // Verify response combines both training session and protein data
      expect(find.textContaining('Verified Training Today'), findsWidgets);
      expect(find.textContaining('Verified Nutrition Today'), findsWidgets);
      expect(find.textContaining('42.0g protein'), findsWidgets);
      debugPrint('✓ [TEST D PASSED] Cross-domain answer combined verified training and nutrition');

      await saveScreenshot('test_d_cross_domain');

      // ───────────────────────────────────────────────────────────────────────
      // PHASE 5 (TEST E) — Live Invalidation Without App Restart
      // ───────────────────────────────────────────────────────────────────────
      debugPrint('========== RUNNING TEST E: LIVE INVALIDATION ==========');

      // 1. Ask initial protein
      final chatInputE = find.byType(TextField).last;
      await tester.enterText(chatInputE, 'How much protein have I had today?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpStep(tester, 600);
      expect(find.textContaining('42.0g protein'), findsWidgets);

      // 2. Log another meal: Whey Protein Shake (+30g protein = 72g total)
      final liveTodayLog = logFor(DateTime.now());
      liveTodayLog.add(
        MealSection.eveningSnack,
        MealEntry(
          rawInput: 'Whey Protein Shake',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Whey Protein Shake',
            calories: 140,
            protein: 30,
            source: 'user_override',
          ),
          addedAt: DateTime.now(),
          section: MealSection.eveningSnack,
          dayOfWeek: 1,
          parsedFoods: const ['Whey'],
          finalSavedInput: 'Whey Protein Shake',
        ),
      );
      // Immediately invalidate context as done in production AddMealScreen._save()
      KynoContextService.instance.invalidate();

      // 3. Ask exact same question again in the live screen
      await tester.enterText(chatInputE, 'How much protein have I had today?');
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpStep(tester, 800);

      // Verify answer has updated to 72.0g protein immediately
      expect(find.textContaining('72.0g protein'), findsWidgets);
      debugPrint('✓ [TEST E PASSED] Answer updated from 42.0g to 72.0g protein live without restart');

      await saveScreenshot('test_e_live_invalidation');
    });
  });
}
