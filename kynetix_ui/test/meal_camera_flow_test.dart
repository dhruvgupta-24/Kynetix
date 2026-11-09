import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/screens/add_meal_screen.dart';
import 'package:kynetix/screens/meal_camera_screen.dart';
import 'package:kynetix/services/meal_photo_service.dart';

/// Snap a meal, end to end, without a camera: the gallery path lands on the
/// same read as the shutter. Kyno's answer is canned; the pipeline is real.
void main() {
  // A valid 1x1 PNG, so Image.memory decodes in tests.
  final png = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='));
  final date = DateTime(2026, 11, 9);

  String answer({double confidence = 0.85}) => jsonEncode({
        'is_food': true,
        'title': 'bhaji plate',
        'items': [
          {
            'name': 'zqx bhaji special',
            'count': null,
            'unit': 'g',
            'grams': 140,
            'kcal': 210,
            'protein_g': 6,
            'carbs_g': 22,
            'fat_g': 11,
            'fiber_g': 3,
            'confidence': confidence,
          },
        ],
      });

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MealCameraScreen.debugCameraEnabled = false;
    MealCameraScreen.debugPickPhoto = () async => png;
    dayLogStore.remove(dateKey(date));
  });

  tearDown(() {
    MealCameraScreen.debugCameraEnabled = true;
    MealCameraScreen.debugPickPhoto = null;
    MealPhotoService.instance.invokeOverride = null;
  });

  Future<void> frames(WidgetTester tester, [int n = 14]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<MealPhotoOutcome?> Function() host(WidgetTester tester) {
    MealPhotoOutcome? outcome;
    var done = false;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return () async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  outcome = await openMealPhotoFlow(context, date: date, section: MealSection.lunch);
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await frames(tester, 6);
      return done ? outcome : null;
    };
  }

  testWidgets('gallery photo, Kyno reads it, one tap logs it', (tester) async {
    MealPhotoService.instance.invokeOverride = (_) async => {'success': true, 'response': answer()};
    await host(tester)();

    // No camera in tests: the screen offers the gallery.
    expect(find.text("Couldn't start the camera"), findsOneWidget);
    await tester.tap(find.text('Pick from gallery'));
    await frames(tester);

    expect(find.text('Bhaji plate'), findsOneWidget);
    expect(find.text('Zqx bhaji special'), findsOneWidget);
    expect(find.text('Log meal'), findsOneWidget);
    expect(logFor(date).entriesFor(MealSection.lunch), isEmpty, reason: 'nothing logged before the tap');

    await tester.tap(find.text('Log meal'));
    await frames(tester);

    final logged = logFor(date).entriesFor(MealSection.lunch);
    expect(logged, hasLength(1));
    expect(logged.single.calMid, closeTo(210, 0.5));
    expect(logged.single.finalSavedInput, '140 g zqx bhaji special');
    // The toast offers Undo.
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('an unsure food makes Review the main action', (tester) async {
    MealPhotoService.instance.invokeOverride = (_) async => {'success': true, 'response': answer(confidence: 0.3)};
    await host(tester)();
    await tester.tap(find.text('Pick from gallery'));
    await frames(tester);

    expect(find.textContaining('less sure about the marked ones'), findsOneWidget);
    expect(find.text('Log as is'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await frames(tester);

    // The editor opens with the photo and the rows, nothing logged yet.
    expect(find.byType(AddMealScreen), findsOneWidget);
    expect(find.text('Read from your photo'), findsOneWidget);
    expect(logFor(date).entriesFor(MealSection.lunch), isEmpty);
  });

  testWidgets('not food says so and offers a retake', (tester) async {
    MealPhotoService.instance.invokeOverride = (_) async => {'success': false, 'error': 'not_food'};
    await host(tester)();
    await tester.tap(find.text('Pick from gallery'));
    await frames(tester);

    expect(find.text('No food in that one'), findsOneWidget);
    expect(find.widgetWithText(KButton, 'Retake'), findsOneWidget);
    expect(find.text('Describe it instead'), findsOneWidget);
  });
}
