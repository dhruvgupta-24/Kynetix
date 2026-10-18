import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/data/micronutrient_library.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/screens/nutrients_screen.dart';
import 'package:kynetix/services/fasting_service.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/widgets/fasting_card.dart';
import 'package:kynetix/widgets/nutrients_summary_card.dart';

MealEntry meal(DateTime at) => MealEntry(
      rawInput: 'poha',
      finalSavedInput: 'poha',
      section: MealSection.breakfast,
      addedAt: at,
      dayOfWeek: at.weekday,
      parsedFoods: const ['poha'],
      result: NutritionResult(
        canonicalMeal: 'poha',
        items: const [],
        calories: const NutrientRange(min: 250, max: 250),
        protein: const NutrientRange(min: 5, max: 5),
        confidence: 0.9,
        warnings: const [],
        source: 'test',
        createdAt: at,
      ),
    );

Map<String, DayLog> storeWith(List<DateTime> times) {
  final store = <String, DayLog>{};
  for (final t in times) {
    store.putIfAbsent(dateKey(t), DayLog.new).add(MealSection.breakfast, meal(t));
  }
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FastingService svc;
  late SharedPreferences prefs;
  final t0 = DateTime(2026, 10, 17, 20, 0); // 8 pm

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    svc = FastingService.forTest();
    svc.clock = () => t0;
    await svc.initForUser('user-a', prefsOverride: prefs);
  });

  group('presets', () {
    test('intermittent windows run a fixed number of hours', () {
      expect(presetById('if_16_8')!.plannedEnd(t0), t0.add(const Duration(hours: 16)));
      expect(presetById('if_14_10')!.plannedEnd(t0), t0.add(const Duration(hours: 14)));
      expect(presetById('if_18_6')!.plannedEnd(t0), t0.add(const Duration(hours: 18)));
    });

    test('clock fasts end at the next occurrence of their time', () {
      final dawn = DateTime(2026, 10, 18, 5, 30);
      expect(presetById('roza')!.plannedEnd(dawn), DateTime(2026, 10, 18, 18, 45));
      expect(presetById('karva_chauth')!.plannedEnd(dawn), DateTime(2026, 10, 18, 20, 30));
      // Started after sunset: rolls to tomorrow's sunset.
      expect(presetById('sunrise_sunset')!.plannedEnd(t0), DateTime(2026, 10, 18, 18, 45));
      expect(presetById('ekadashi')!.plannedEnd(dawn), DateTime(2026, 10, 19, 7, 0));
    });

    test('vrat fasts allow phalahar; no-food fasts end on a meal', () {
      expect(presetById('navratri')!.endsOnMeal, isFalse);
      expect(presetById('ekadashi')!.endsOnMeal, isFalse);
      expect(presetById('roza')!.endsOnMeal, isTrue);
      expect(presetById('if_16_8')!.endsOnMeal, isTrue);
      expect(presetById('karva_chauth')!.isReligious, isTrue);
      expect(presetById('if_16_8')!.isReligious, isFalse);
    });
  });

  group('state machine', () {
    test('start → status → stop, recorded in history', () async {
      await svc.start('if_16_8');
      final a = svc.state.value.active!;
      expect(a.plannedEnd, t0.add(const Duration(hours: 16)));

      final mid = svc.status(now: t0.add(const Duration(hours: 4)))!;
      expect(mid.elapsed, const Duration(hours: 4));
      expect(mid.remaining, const Duration(hours: 12));
      expect(mid.progress, closeTo(0.25, 0.001));
      expect(mid.goalReached, isFalse);
      expect(svc.status(now: t0.add(const Duration(hours: 17)))!.goalReached, isTrue);
      expect(svc.status(now: t0.add(const Duration(hours: 17)))!.progress, 1.0);

      await svc.stop(now: t0.add(const Duration(hours: 16, minutes: 5)));
      expect(svc.state.value.active, isNull);
      final h = svc.state.value.history.single;
      expect(h.endReason, FastEndReason.manual);
      expect(h.completed, isTrue);
      expect(svc.state.value.lastPresetId, 'if_16_8');
    });

    test('stopping early is not completed; stop with nothing running is a no-op', () async {
      await svc.stop();
      expect(svc.state.value.history, isEmpty);
      await svc.start('if_18_6');
      await svc.stop(now: t0.add(const Duration(hours: 3)));
      expect(svc.state.value.history.single.completed, isFalse);
    });

    test('starting a new fast closes the running one', () async {
      await svc.start('if_16_8');
      await svc.start('if_14_10', now: t0.add(const Duration(hours: 1)));
      expect(svc.state.value.active!.presetId, 'if_14_10');
      expect(svc.state.value.history.single.presetId, 'if_16_8');
    });

    test('a custom end overrides the preset; setEnd moves it', () async {
      final iftar = DateTime(2026, 10, 18, 18, 20);
      await svc.start('roza', now: DateTime(2026, 10, 18, 5, 0), endAt: iftar);
      expect(svc.state.value.active!.plannedEnd, iftar);
      await svc.setEnd(DateTime(2026, 10, 18, 18, 30));
      expect(svc.state.value.active!.plannedEnd, DateTime(2026, 10, 18, 18, 30));
      await svc.setEnd(DateTime(2026, 10, 18, 4, 0)); // before start: ignored
      expect(svc.state.value.active!.plannedEnd, DateTime(2026, 10, 18, 18, 30));
    });
  });

  group('meal logging', () {
    test('a meal after the start ends a no-food fast at the meal time', () async {
      await svc.start('if_16_8');
      final breakfast = DateTime(2026, 10, 18, 11, 30);
      await svc.onMealsChanged(storeWith([t0.subtract(const Duration(hours: 1)), breakfast]),
          now: breakfast.add(const Duration(minutes: 2)));
      expect(svc.state.value.active, isNull);
      final h = svc.state.value.history.single;
      expect(h.endReason, FastEndReason.meal);
      expect(h.endedAt, breakfast);
      expect(h.completed, isFalse);
    });

    test('meals from before the fast never end it', () async {
      await svc.start('if_16_8');
      await svc.onMealsChanged(storeWith([t0.subtract(const Duration(minutes: 10))]),
          now: t0.add(const Duration(hours: 2)));
      expect(svc.state.value.active, isNotNull);
    });

    test('Navratri and Ekadashi keep running through phalahar', () async {
      await svc.start('navratri', now: DateTime(2026, 10, 18, 6, 0));
      await svc.onMealsChanged(storeWith([DateTime(2026, 10, 18, 11, 0)]), now: DateTime(2026, 10, 18, 11, 1));
      expect(svc.state.value.active!.presetId, 'navratri');
      expect(svc.vratFoodsOnly(), isTrue);
    });

    test('resume puts back a fast a meal ended; the same meal does not end it again', () async {
      await svc.start('if_16_8');
      final late = DateTime(2026, 10, 17, 21, 0); // dinner logged late
      final store = storeWith([late]);
      await svc.onMealsChanged(store, now: late);
      expect(svc.state.value.active, isNull);

      expect(await svc.resumeLast(now: DateTime(2026, 10, 17, 21, 5)), isTrue);
      expect(svc.state.value.active!.startedAt, t0);
      expect(svc.state.value.history, isEmpty);
      await svc.onMealsChanged(store, now: DateTime(2026, 10, 17, 22, 0));
      expect(svc.state.value.active, isNotNull);

      final breakfast = DateTime(2026, 10, 18, 12, 10);
      store.putIfAbsent(dateKey(breakfast), DayLog.new).add(MealSection.breakfast, meal(breakfast));
      await svc.onMealsChanged(store, now: breakfast);
      expect(svc.state.value.history.single.endedAt, breakfast);
      expect(svc.state.value.history.single.completed, isTrue);
    });

    test('resume does nothing after a manual stop', () async {
      await svc.start('if_16_8');
      await svc.stop(now: t0.add(const Duration(hours: 1)));
      expect(await svc.resumeLast(), isFalse);
    });
  });

  group('scheduling', () {
    test('a planned fast starts once its time comes', () async {
      final start = DateTime(2026, 10, 19, 5, 30);
      await svc.schedule('ekadashi', start);
      expect(svc.state.value.scheduled, isNotNull);
      await svc.refresh(now: DateTime(2026, 10, 19, 5, 0));
      expect(svc.state.value.active, isNull);
      await svc.refresh(now: DateTime(2026, 10, 19, 6, 0));
      expect(svc.state.value.active!.presetId, 'ekadashi');
      expect(svc.state.value.active!.startedAt, start);
      expect(svc.state.value.scheduled, isNull);
    });

    test('a window that passed while closed is dropped; cancel works', () async {
      await svc.schedule('if_14_10', DateTime(2026, 10, 18, 20, 0));
      await svc.refresh(now: DateTime(2026, 10, 20, 9, 0));
      expect(svc.state.value.active, isNull);
      expect(svc.state.value.scheduled, isNull);

      await svc.schedule('roza', DateTime(2026, 10, 21, 5, 0));
      await svc.cancelSchedule();
      expect(svc.state.value.scheduled, isNull);
    });
  });

  group('persistence and brief', () {
    test('state is per user and survives a restart', () async {
      await svc.start('if_16_8');
      final again = FastingService.forTest()..clock = () => t0;
      await again.initForUser('user-a', prefsOverride: prefs);
      expect(again.state.value.active!.presetId, 'if_16_8');

      final other = FastingService.forTest()..clock = () => t0;
      await other.initForUser('user-b', prefsOverride: prefs);
      expect(other.state.value.active, isNull);

      svc.clearMemory();
      expect(svc.state.value.active, isNull);
    });

    test('corrupt stored state loads as empty', () async {
      await prefs.setString('fasting_state_v1_user-c', '{not json');
      final c = FastingService.forTest();
      await c.initForUser('user-c', prefsOverride: prefs);
      expect(c.state.value.active, isNull);
    });

    test('brief describes a running fast, nothing when idle', () async {
      expect(svc.briefJson(), isNull);
      await svc.start('navratri', now: DateTime(2026, 10, 18, 6, 0));
      final b = svc.briefJson(now: DateTime(2026, 10, 18, 9, 0))!;
      final a = b['active'] as Map<String, dynamic>;
      expect(a['type'], 'Navratri');
      expect(a['religious'], isTrue);
      expect(a['vrat_foods_only'], isTrue);
      expect(a['logging_a_meal_ends_it'], isFalse);
      expect(a['elapsed_hours'], 3.0);
      expect(a['remaining_hours'], 11.0);
    });
  });

  group('widgets', () {
    Future<void> pump(WidgetTester tester, Widget child, {bool dark = false}) async {
      KThemeController.instance.value = dark ? ThemeMode.dark : ThemeMode.light;
      await tester.pumpWidget(
        KThemeScope(
          builder: (context, palette) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SizedBox(width: 360, child: child)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('fasting card: idle, then running with ring and end button', (tester) async {
      await pump(tester, FastingCard(service: svc, now: () => t0));
      expect(find.text('Fasting'), findsOneWidget);
      expect(find.text('Start fast'), findsOneWidget);

      await tester.runAsync(() => svc.start('if_16_8', now: t0.subtract(const Duration(hours: 2))));
      await tester.pumpAndSettle();
      expect(find.text('16:8 fast'), findsOneWidget);
      expect(find.text('2:00'), findsOneWidget);
      expect(find.text('End fast'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('End fast'));
      await tester.pumpAndSettle();
      expect(find.text('Start fast'), findsOneWidget);
    });

    testWidgets('fasting card offers resume after a meal ended the fast', (tester) async {
      await tester.runAsync(() async {
        await svc.start('if_16_8');
        await svc.onMealsChanged(storeWith([t0.add(const Duration(minutes: 30))]), now: t0.add(const Duration(minutes: 31)));
      });
      await pump(tester, FastingCard(service: svc, now: () => t0.add(const Duration(minutes: 40))), dark: true);
      expect(find.text('Resume fast'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nutrients screen with a tracked week shows bars, the oracle and coverage', (tester) async {
      dayLogStore.clear();
      NutritionItem it(String n, double kcal) => NutritionItem(
            name: n, quantity: 1, unit: 'serving', estimated: false, mode: EstimationMode.directQuantity,
            calories: NutrientRange(min: kcal, max: kcal), protein: const NutrientRange(min: 5, max: 5),
            micros: MicronutrientLibrary.instance.estimate(n, kcal),
          );
      MealEntry m(List<NutritionItem> items, DateTime at) => MealEntry(
            rawInput: 'x', finalSavedInput: items.map((i) => i.name).join(' + '), section: MealSection.lunch,
            addedAt: at, dayOfWeek: at.weekday, parsedFoods: const [],
            result: NutritionResult(
              canonicalMeal: 'x', items: items,
              calories: NutrientRange(min: items.fold(0.0, (a, i) => a + i.calories.mid), max: items.fold(0.0, (a, i) => a + i.calories.mid)),
              protein: const NutrientRange(min: 10, max: 10), confidence: 0.9, warnings: const [], source: 'test', createdAt: at,
            ),
          );
      for (var i = 0; i <= 4; i++) {
        final d = DateTime(2026, 10, 17 - i, 13);
        dayLogStore[dateKey(d)] = DayLog()..add(MealSection.lunch, m([it('roti', 300), it('dal', 120), it('curd', 90)], d));
      }
      KThemeController.instance.value = ThemeMode.dark;
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(KThemeScope(
        builder: (context, palette) => MaterialApp(home: NutrientsScreen(now: DateTime(2026, 10, 17, 20))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Lowest right now'), findsOneWidget);
      expect(find.textContaining('Tracked for 1 of 1 meal today'), findsOneWidget);
      expect(find.text('Vitamin D'), findsWidgets);
      expect(find.textContaining('Food barely moves vitamin D'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.textContaining('ICMR-NIN 2020'), findsOneWidget);
      expect(tester.takeException(), isNull);
      dayLogStore.clear();
    });

    testWidgets('nutrients summary and screen render with no data', (tester) async {
      dayLogStore.clear();
      await pump(tester, NutrientsSummaryCard(now: t0));
      expect(find.text('Nutrients'), findsOneWidget);
      expect(find.textContaining('show up for meals you log'), findsOneWidget);

      await tester.pumpWidget(KThemeScope(
        builder: (context, palette) => MaterialApp(home: NutrientsScreen(now: t0)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Not tracked today'), findsWidgets);
      expect(find.text('0 mg'), findsNothing, reason: 'untracked never reads as zero');
      expect(tester.takeException(), isNull);
    });
  });
}
