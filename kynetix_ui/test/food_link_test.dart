import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/models/barcode_product.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/screens/nutrition_intelligence_screen.dart';
import 'package:kynetix/services/food_link_service.dart';
import 'package:kynetix/services/meal_memory.dart';
import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/saved_meal_service.dart';
import 'package:kynetix/widgets/barcode_product_sheet.dart';

/// Linking a scanned pack to a food the person already logged under another
/// name: the pack becomes the one source of truth, the old name an alias.
BarcodeProduct phab({String name = 'Phab Mini Chocolate Brownie Bar', String? brand = 'Phab'}) =>
    BarcodeProduct(
      barcode: '8906118380123',
      name: name,
      brand: brand,
      per100g: const BarcodeNutriments(
        calories: 400,
        proteinG: 31.4,
        carbsG: 40,
        fatG: 14,
        fiberG: 5,
        sugarG: 2,
      ),
      servings: const [BarcodeProduct.hundredGrams],
      netQuantity: 35,
    );

const oldName = 'phab 11g chocolate brownie protein bar';

NutritionResult oldResult() => NutritionResult.createCustom(
      canonicalMeal: oldName,
      calories: 150,
      protein: 11,
      source: 'user_override',
    );

MealEntry oldEntry() => MealEntry(
      rawInput: oldName,
      result: oldResult(),
      addedAt: DateTime(2026, 9, 1, 17),
      section: MealSection.eveningSnack,
      dayOfWeek: 2,
      parsedFoods: const [oldName],
      finalSavedInput: oldName,
    );

Future<void> signIn(String userId) async {
  NutritionHydrationGuard.instance.currentUserIdOverride = userId;
  NutritionHydrationGuard.instance.markComplete(userId);
  await MealMemory.instance.initForUser(userId);
  await FoodLinkService.instance.initForUser(userId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dayLogStore.clear();
    MealMemory.instance.clearMemory();
    FoodLinkService.instance.clearMemory();
    await signIn('user-a');
  });

  tearDown(() {
    dayLogStore.clear();
    MealMemory.instance.clearMemory();
    FoodLinkService.instance.clearMemory();
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = null;
  });

  group('matching', () {
    test('the Phab example matches', () {
      expect(FoodLinkMatcher.score(phab(), oldName),
          greaterThanOrEqualTo(FoodLinkMatcher.strongScore));
    });

    test('matches without a brand field, sizes in either name', () {
      final p = phab(name: '35 g phab mini chocolate brownie bar', brand: null);
      expect(FoodLinkMatcher.score(p, oldName), greaterThanOrEqualTo(FoodLinkMatcher.strongScore));
      expect(FoodLinkMatcher.score(p, 'Phab 35g Choco Brownie'),
          greaterThanOrEqualTo(FoodLinkMatcher.strongScore));
    });

    test('a different brand never matches', () {
      final p = phab(name: 'Phab chocolate bar');
      expect(FoodLinkMatcher.score(p, 'Amul chocolate bar'), 0);
    });

    test('same brand, different flavour does not match', () {
      expect(FoodLinkMatcher.score(phab(), 'phab peanut butter protein bar'), 0);
    });

    test('brand alone is too weak to offer', () {
      expect(FoodLinkMatcher.score(phab(), 'phab protein bar'), 0);
    });

    test('keys ignore leading amounts and punctuation, keep inner sizes', () {
      expect(FoodLinkMatcher.key('2 Phab 11g Chocolate-Brownie Protein Bar'),
          'phab 11g chocolate brownie protein bar');
      expect(FoodLinkMatcher.key('35 g Phab mini chocolate brownie bar'),
          'phab mini chocolate brownie bar');
    });
  });

  group('suggestion', () {
    test('offers the old food from day logs and memory, once', () async {
      logFor(DateTime(2026, 9, 1)).add(MealSection.eveningSnack, oldEntry());
      await MealMemory.instance.store(oldName, oldResult());

      final offer = FoodLinkService.instance.suggestionFor(phab());
      expect(offer, isNotNull);
      expect(offer!.name, oldName);
      expect(FoodLinkService.instance.candidatesFor(phab()), hasLength(1));
    });

    test('the pack\'s own scanner entries are not offered', () async {
      final p = phab();
      final scanned = p.resultForAmount(35);
      await MealMemory.instance.store(p.entryText(35), scanned, canonicalMeal: p.name);
      expect(FoodLinkService.instance.suggestionFor(p), isNull);
    });

    test('"Not the same" is remembered for that pair', () async {
      await MealMemory.instance.store(oldName, oldResult());
      await FoodLinkService.instance.decline(phab(), oldName);
      expect(FoodLinkService.instance.suggestionFor(phab()), isNull);

      // Still remembered after a reload.
      FoodLinkService.instance.clearMemory();
      await FoodLinkService.instance.initForUser('user-a');
      expect(FoodLinkService.instance.isDeclined(phab().barcode, oldName), isTrue);
      expect(FoodLinkService.instance.suggestionFor(phab()), isNull);
    });
  });

  group('linking', () {
    test('both names resolve to the pack\'s label numbers', () async {
      await MealMemory.instance.store(oldName, oldResult());
      await FoodLinkService.instance.link(phab(), oldName);

      final viaOld = await NutritionPipeline.instance.estimateMeal(oldName);
      expect(viaOld.source, 'barcode');
      expect(viaOld.calories.mid, closeTo(140, 0.5)); // 35 g at 400 kcal/100 g
      expect(viaOld.items.single.name, 'Phab Mini Chocolate Brownie Bar');

      final two = await NutritionPipeline.instance.estimateMeal('2 $oldName');
      expect(two.calories.mid, closeTo(280, 0.5));

      final grams = await NutritionPipeline.instance.estimateMeal('50 g $oldName');
      expect(grams.calories.mid, closeTo(200, 0.5));

      final viaNew = NutritionPipeline.instance.fastMemoryLookupSync('phab mini chocolate brownie bar');
      expect(viaNew, isNotNull);
      expect(viaNew!.calories.mid, closeTo(140, 0.5));

      // Quick Add and the meal editor go through the same resolution.
      expect(FoodLinkService.instance.resolveMeal(oldName)!.calories.mid, closeTo(140, 0.5));
      final item = FoodLinkService.instance.resolveItem(oldName, 1, 'serving');
      expect(item!.calories.mid, closeTo(140, 0.5));
    });

    test('search shows one item and hides the duplicate', () async {
      logFor(DateTime(2026, 9, 1)).add(MealSection.eveningSnack, oldEntry());
      await MealMemory.instance.store(oldName, oldResult());

      final before = SavedMealService.instance.search('phab');
      expect(before.map((m) => m.title.toLowerCase()), contains(oldName));

      await FoodLinkService.instance.link(phab(), oldName);
      final after = SavedMealService.instance.search('phab');
      expect(after.map((m) => m.title), contains('Phab Mini Chocolate Brownie Bar'));
      expect(after.map((m) => m.title.toLowerCase()), isNot(contains(oldName)));
      // Typing the old name finds the pack.
      final byOld = SavedMealService.instance.search(oldName);
      expect(byOld.first.title, 'Phab Mini Chocolate Brownie Bar');
      expect(byOld.first.calories, closeTo(140, 0.5));
    });

    test('hidden from recurring meals (Kyno) but never deleted', () async {
      await MealMemory.instance.store(oldName, oldResult());
      MealMemory.instance.lookup(oldName); // second use: recurring
      expect(MealMemory.instance.recurringMeals.map((e) => e.rawInput), contains(oldName));

      await FoodLinkService.instance.link(phab(), oldName);
      expect(MealMemory.instance.recurringMeals.map((e) => e.rawInput), isNot(contains(oldName)));
      expect(MealMemory.instance.allEntries.map((e) => e.rawInput), contains(oldName));

      await FoodLinkService.instance.unlink(phab().barcode);
      expect(MealMemory.instance.recurringMeals.map((e) => e.rawInput), contains(oldName));
    });

    test('unlinking restores the old behaviour', () async {
      await MealMemory.instance.store(oldName, oldResult());
      await FoodLinkService.instance.link(phab(), oldName);
      expect(FoodLinkService.instance.linkFor(oldName), isNotNull);

      await FoodLinkService.instance.unlink(phab().barcode, alias: oldName);
      expect(FoodLinkService.instance.links, isEmpty);
      expect(FoodLinkService.instance.linkFor(oldName), isNull);
      expect(FoodLinkService.instance.isHidden(oldName), isFalse);
      final r = await NutritionPipeline.instance.estimateMeal(oldName);
      expect(r.source, isNot('barcode'));
      expect(r.calories.mid, closeTo(150, 0.5));
    });

    test('links are per user and stored under a per-user key', () async {
      await FoodLinkService.instance.link(phab(), oldName);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FoodLinkService.keyFor('user-a')), isNotNull);

      await signIn('user-b');
      expect(FoodLinkService.instance.links, isEmpty);
      expect(FoodLinkService.instance.linkFor(oldName), isNull);

      await signIn('user-a');
      expect(FoodLinkService.instance.links, hasLength(1));
      expect(FoodLinkService.instance.links.single.aliases, [oldName]);
    });

    test('nothing resolves before the session is hydrated', () async {
      await FoodLinkService.instance.link(phab(), oldName);
      NutritionHydrationGuard.instance.reset();
      expect(FoodLinkService.instance.linkFor(oldName), isNull);
      expect(FoodLinkService.instance.resolveMeal(oldName), isNull);
    });

    test('past day-log meals stay byte-identical', () async {
      final day = DateTime(2026, 9, 1);
      logFor(day).add(MealSection.eveningSnack, oldEntry());
      await MealMemory.instance.store(oldName, oldResult());
      final before = jsonEncode(logFor(day).toJson());

      await FoodLinkService.instance.link(phab(), oldName);
      SavedMealService.instance.search('phab');
      await NutritionPipeline.instance.estimateMeal(oldName);
      FoodLinkService.instance.candidatesFor(phab());
      await FoodLinkService.instance.unlink(phab().barcode);

      expect(jsonEncode(logFor(day).toJson()), before);
    });
  });

  group('scan result prompt', () {
    Future<void> openSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showBarcodeProductSheet(
                  context,
                  product: phab(),
                  date: DateTime(2026, 9, 7),
                  section: MealSection.eveningSnack,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('Link makes the pack the source of truth', (tester) async {
      await tester.runAsync(() => MealMemory.instance.store(oldName, oldResult()));
      await openSheet(tester);

      expect(find.text('Same as your "Phab 11g chocolate brownie protein bar"?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Link'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Linked to "Phab 11g chocolate brownie protein bar"'), findsOneWidget);
      expect(FoodLinkService.instance.linkFor(oldName)?.barcode, phab().barcode);
    });

    testWidgets('Not the same hides the prompt and remembers', (tester) async {
      await tester.runAsync(() => MealMemory.instance.store(oldName, oldResult()));
      await openSheet(tester);

      await tester.runAsync(() async {
        await tester.tap(find.text('Not the same'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Same as your'), findsNothing);
      expect(FoodLinkService.instance.isDeclined(phab().barcode, oldName), isTrue);
      expect(FoodLinkService.instance.links, isEmpty);
    });

    testWidgets('no prompt when nothing looks like the pack', (tester) async {
      await openSheet(tester);
      expect(find.textContaining('Same as your'), findsNothing);
    });
  });

  group('food library', () {
    testWidgets('lists the link and unlinks it', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => FoodLinkService.instance.link(phab(), oldName));

      await tester.pumpWidget(const MaterialApp(home: NutritionIntelligenceScreen()));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Linked foods'), findsOneWidget);
      expect(find.text('Phab Mini Chocolate Brownie Bar'), findsOneWidget);
      expect(find.text('Also logged as: $oldName'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Unlink'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(FoodLinkService.instance.links, isEmpty);
      expect(find.text('Linked foods'), findsNothing);
      expect(find.text('Unlinked. Both names are separate again.'), findsOneWidget);
    });
  });
}
