import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';
import 'package:kynetix/services/kyno_context_service.dart';
import 'package:kynetix/services/kyno_historical_analysis_service.dart';
import 'package:kynetix/services/kyno_assistant_service.dart';
import 'package:kynetix/services/kyno_meal_drilldown_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  tearDown(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  MealEntry _createMeal({
    required String name,
    required DateTime time,
    required MealSection section,
    required double calories,
    required double protein,
    double carbs = 40.0,
    double fat = 15.0,
    List<String> parsedFoods = const ['food'],
  }) {
    return MealEntry(
      rawInput: name,
      finalSavedInput: name,
      addedAt: time,
      section: section,
      dayOfWeek: time.weekday,
      parsedFoods: parsedFoods,
      result: NutritionResult(
        canonicalMeal: name,
        items: [],
        calories: NutrientRange(min: calories, max: calories),
        protein: NutrientRange(min: protein, max: protein),
        carbohydrates: NutrientRange(min: carbs, max: carbs),
        fat: NutrientRange(min: fat, max: fat),
        confidence: 1.0,
        warnings: [],
        source: 'user_logged',
        createdAt: time,
      ),
    );
  }

  const shoulderPress = Exercise(
    id: 'db_shoulder_press',
    name: 'DB Shoulder Press',
    muscleGroup: 'Shoulders',
    type: ExerciseType.dumbbell,
    defaultTargetSets: 3,
    defaultRepMin: 8,
    defaultRepMax: 10,
  );

  WorkoutSession _createSession(DateTime date, double weight, int reps) {
    return WorkoutSession(
      id: 'session_${date.millisecondsSinceEpoch}',
      date: date,
      splitDayName: 'Shoulder Day',
      durationMinutes: 50,
      entries: [
        ExerciseEntry(
          exercise: shoulderPress,
          sets: [
            SetEntry(weight: weight, reps: reps, setType: SetType.normal),
            SetEntry(weight: weight, reps: reps, setType: SetType.normal),
            SetEntry(weight: weight, reps: reps, setType: SetType.normal),
          ],
        ),
      ],
    );
  }

  group('Part 1: Date-Window Consistency Contract Tests (14 vs 15 days)', () {
    test('1. Explicit date-window contract: 14 completed days + today partial meal does NOT alter 14-day average', () async {
      final now = DateTime.now();

      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dev Tester',
        age: 26,
        gender: 'male',
        height: 180,
        weight: 75,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Muscle Building & Strength',
      );

      // Save 3 workout sessions
      await WorkoutService.instance.saveSession(_createSession(now.subtract(const Duration(days: 10)), 25.0, 8));
      await WorkoutService.instance.saveSession(_createSession(now.subtract(const Duration(days: 6)), 25.0, 8));
      await WorkoutService.instance.saveSession(_createSession(now.subtract(const Duration(days: 2)), 25.0, 8));

      // Seed exactly 14 completed historical days (days 1 to 14 ago)
      // Averaging 72g protein, 1850 kcal
      for (int i = 1; i <= 14; i++) {
        final d = now.subtract(Duration(days: i));
        final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final dLog = DayLog()
          ..targetProtein = 150.0
          ..targetCalories = 2300.0
          ..gymDay = GymDay(didGym: i % 2 == 0);

        final pro = i == 1 ? 62.0 : 72.0; // yesterday: 62g, rest: 72g
        dLog.add(
          MealSection.lunch,
          _createMeal(
            name: 'Chicken Rice Bowl',
            time: DateTime(d.year, d.month, d.day, 13, 15),
            section: MealSection.lunch,
            calories: 750,
            protein: pro,
          ),
        );
        dayLogStore[dKey] = dLog;
      }

      // Pre-check snapshot with 14 completed days
      var snapshot = KynoHistoricalAnalysisService.instance.getFitnessSnapshot(forceRefresh: true);
      expect(snapshot.nutritionDaysIn14DayWindow, equals(14));
      expect(snapshot.totalDaysWithMealsLogged, equals(14));
      // Average protein = (62 + 13 * 72) / 14 = 998 / 14 = 71.285g (~71g)
      expect(snapshot.avgProteinLast14Days, closeTo(71.28, 0.1));
      expect(snapshot.avgCaloriesLast14Days, closeTo(750.0, 0.1));

      // Now log a partial meal TODAY (e.g. 1 scoop whey, 120 kcal, 24g protein)
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final todayLog = DayLog()
        ..targetProtein = 150.0
        ..targetCalories = 2300.0;
      todayLog.add(
        MealSection.breakfast,
        _createMeal(
          name: '1 Scoop Whey Protein',
          time: DateTime(now.year, now.month, now.day, 10, 30),
          section: MealSection.breakfast,
          calories: 120,
          protein: 24,
        ),
      );
      dayLogStore[todayKey] = todayLog;

      // Re-evaluate snapshot after today meal was logged
      snapshot = KynoHistoricalAnalysisService.instance.getFitnessSnapshot(forceRefresh: true);

      // 1. Total lifetime logged days in account is now 15 (14 historical + 1 today)
      expect(snapshot.totalDaysWithMealsLogged, equals(15));

      // 2. The 14-day longitudinal evaluation window evaluates exactly 14 completed days
      expect(snapshot.nutritionDaysIn14DayWindow, equals(14));

      // 3. 14-day average protein and calories remain mathematically uncorrupted by today's partial meal
      expect(snapshot.avgProteinLast14Days, closeTo(71.28, 0.1),
          reason: 'Today partial data (24g) must not drag 14-day average down to 68g');
      expect(snapshot.avgCaloriesLast14Days, closeTo(750.0, 0.1),
          reason: 'Today partial calories (120 kcal) must not drag 14-day average down to 705 kcal');

      // 4. Low protein days count in the 14-day window is exactly 14 of 14
      expect(snapshot.lowProteinDaysLast14Days, equals(14));

      // 5. Strength plateau text harmonization
      final result = KynoHistoricalAnalysisService.instance.analyzeQuery('why is my strength not increasing?');
      final factItem = result.insights.firstWhere((i) => i.title.contains('Nutrition Record'));
      final calcItem = result.insights.firstWhere((i) => i.title.contains('Nutrition Adherence Math'));

      // Both must refer to the same 14 logged days window
      expect(factItem.detail, contains('across 14 logged days'));
      expect(calcItem.detail, contains('14 of last 14 logged days'));
    });
  });

  group('Part 2: Historical Meal Drill-Down Tests', () {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    setUp(() {
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength & Muscle Building',
      );
    });

    test('1. "Why were my calories high yesterday?" identifies exact highest-contributing meals, timestamps, and macros', () async {
      final yLog = DayLog()
        ..targetCalories = 2200.0
        ..targetProtein = 140.0;

      // 3 meals yesterday: breakfast (500), lunch (1200 - highest), dinner (800) -> total 2500 kcal
      yLog.add(
        MealSection.breakfast,
        _createMeal(
          name: 'Oatmeal with Peanut Butter',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 8, 30),
          section: MealSection.breakfast,
          calories: 500,
          protein: 20,
          carbs: 65,
          fat: 15,
        ),
      );
      yLog.add(
        MealSection.lunch,
        _createMeal(
          name: 'Double Cheeseburger & Fries',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 13, 15),
          section: MealSection.lunch,
          calories: 1200,
          protein: 45,
          carbs: 110,
          fat: 60,
        ),
      );
      yLog.add(
        MealSection.dinner,
        _createMeal(
          name: 'Salmon with Quinoa',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 19, 45),
          section: MealSection.dinner,
          calories: 800,
          protein: 50,
          carbs: 60,
          fat: 30,
        ),
      );
      dayLogStore[yesterdayKey] = yLog;

      final msg = await KynoAssistantService.instance.processQuery('Why were my calories high yesterday?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // FACT: Must identify the exact meal name and timestamp
      expect(allText, contains('Double Cheeseburger & Fries'));
      expect(allText, contains('1:15 PM'));
      expect(allText, contains('1200 kcal'));

      // CALCULATION: Contribution math and surplus
      expect(allText, contains('48% of yesterday\'s total intake'));
      expect(allText, contains('exceeded your configured target'));

      // Zero food moralizing
      expect(allText.toLowerCase(), isNot(contains('bad food')));
      expect(allText.toLowerCase(), isNot(contains('junk')));
      expect(allText.toLowerCase(), isNot(contains('shouldn\'t have been eaten')));
      expect(allText.toLowerCase(), isNot(contains('cheating')));
    });

    test('2. "Why am I not hitting protein?" identifies low-protein meals (<15g) and missed opportunities', () async {
      final yLog = DayLog()
        ..targetCalories = 2200.0
        ..targetProtein = 150.0;

      // 1 high protein meal (Chicken Bowl: 50g) and 2 low protein meals (Salad: 8g, Granola Snack: 5g) -> total 63g vs 150g target
      yLog.add(
        MealSection.lunch,
        _createMeal(
          name: 'Chicken Rice Bowl',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 12, 30),
          section: MealSection.lunch,
          calories: 650,
          protein: 50,
        ),
      );
      yLog.add(
        MealSection.eveningSnack,
        _createMeal(
          name: 'Granola Energy Bar',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 16, 0),
          section: MealSection.eveningSnack,
          calories: 280,
          protein: 5,
        ),
      );
      yLog.add(
        MealSection.dinner,
        _createMeal(
          name: 'Garden Veggie Salad',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 19, 15),
          section: MealSection.dinner,
          calories: 320,
          protein: 8,
        ),
      );
      dayLogStore[yesterdayKey] = yLog;

      final msg = await KynoAssistantService.instance.processQuery('Why am I not hitting protein?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // FACT: Cites exact historical meals with protein counts
      expect(allText, contains('Chicken Rice Bowl'));
      expect(allText, contains('50g protein'));
      expect(allText, contains('Granola Energy Bar'));
      expect(allText, contains('5g protein'));
      expect(allText, contains('Garden Veggie Salad'));
      expect(allText, contains('8g protein'));

      // CALCULATION & INFERENCE: Identifies low-protein meals and missed opportunity
      expect(allText, contains('Low-protein meals (<15g): 2 of 3 meals'));
      expect(allText, contains('Granola Energy Bar'));
      expect(allText, contains('30–40g of protein'));
    });

    test('3. "Did I eat anything late last night?" gives exact meal name + timestamp if late meals exist', () async {
      final yLog = DayLog()..targetCalories = 2200.0;

      // Meal at 9:45 PM (21:45)
      yLog.add(
        MealSection.lateNight,
        _createMeal(
          name: 'Greek Yogurt with Blueberries',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 21, 45),
          section: MealSection.lateNight,
          calories: 220,
          protein: 22,
          carbs: 18,
          fat: 2,
        ),
      );
      dayLogStore[yesterdayKey] = yLog;

      final msg = await KynoAssistantService.instance.processQuery('Did I eat anything late last night?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // FACT: Exact meal name and timestamp
      expect(allText, contains('Greek Yogurt with Blueberries'));
      expect(allText, contains('9:45 PM'));
      expect(allText, contains('220 kcal'));

      // Non-moralizing explanation
      expect(allText.toLowerCase(), contains('eating late is neither inherently beneficial nor harmful'));
      expect(allText.toLowerCase(), isNot(contains('should not have')));
    });

    test('4. "Did I eat anything late last night?" accurately states none logged when no late meals exist', () async {
      final yLog = DayLog()..targetCalories = 2200.0;

      // Only lunch at 1:15 PM and dinner at 6:30 PM (no meals after 8:00 PM)
      yLog.add(
        MealSection.dinner,
        _createMeal(
          name: 'Steak with Sweet Potato',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 18, 30),
          section: MealSection.dinner,
          calories: 750,
          protein: 55,
        ),
      );
      dayLogStore[yesterdayKey] = yLog;

      final msg = await KynoAssistantService.instance.processQuery('Did I eat anything late last night?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // FACT: States none logged after 8:00 PM and cites last meal
      expect(allText, contains('No meals were logged after 8:00 PM'));
      expect(allText, contains('Steak with Sweet Potato'));
      expect(allText, contains('6:30 PM'));
    });

    test('5. "What did I eat yesterday?" gives chronological list with exact names, times, sections, macros', () async {
      final yLog = DayLog()..targetCalories = 2200.0;

      yLog.add(
        MealSection.breakfast,
        _createMeal(
          name: 'Eggs and Toast',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 8, 15),
          section: MealSection.breakfast,
          calories: 420,
          protein: 26,
          carbs: 35,
          fat: 18,
        ),
      );
      yLog.add(
        MealSection.lunch,
        _createMeal(
          name: 'Chicken Rice Bowl',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 13, 0),
          section: MealSection.lunch,
          calories: 750,
          protein: 60,
          carbs: 85,
          fat: 15,
        ),
      );
      dayLogStore[yesterdayKey] = yLog;

      final msg = await KynoAssistantService.instance.processQuery('What did I eat yesterday?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // Chronological entries
      expect(allText, contains('8:15 AM [BREAKFAST]: "Eggs and Toast" – 420 kcal | 26g P | 35g C | 18g F'));
      expect(allText, contains('1:00 PM [LUNCH]: "Chicken Rice Bowl" – 750 kcal | 60g P | 85g C | 15g F'));
      expect(allText, contains('Total Calories: 1170 kcal'));
      expect(allText, contains('Protein: 86g'));
    });

    test('6. "Why am I gaining weight?" combines multi-day calorie pattern with individual meals without moralizing', () async {
      // Seed 14 days with surplus: target 2200, average 2600 (+400 surplus)
      for (int i = 1; i <= 14; i++) {
        final d = now.subtract(Duration(days: i));
        final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final dLog = DayLog()
          ..targetProtein = 140.0
          ..targetCalories = 2200.0;
        dLog.add(
          MealSection.dinner,
          _createMeal(
            name: 'Ribeye Steak Dinner',
            time: DateTime(d.year, d.month, d.day, 20, 0),
            section: MealSection.dinner,
            calories: 1400,
            protein: 70,
            carbs: 50,
            fat: 80,
          ),
        );
        dayLogStore[dKey] = dLog;
      }

      final msg = await KynoAssistantService.instance.processQuery('Why am I gaining weight?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // FACT: 14-day average calorie pattern and drill down to high energy meal
      expect(allText, contains('14-Day Average'));
      expect(allText, contains('Ribeye Steak Dinner'));
      expect(allText, contains('1400 kcal'));

      // CALCULATION: Energy surplus math
      expect(allText, contains('Energy Balance Math'));

      // Non-moralizing
      expect(allText.toLowerCase(), isNot(contains('bad food')));
      expect(allText.toLowerCase(), isNot(contains('junk')));
    });

    test('7. "How was my nutrition yesterday?" summarizes day and cites specific meals explaining result', () async {
      final yLog = DayLog()
        ..targetCalories = 2200.0
        ..targetProtein = 140.0;

      yLog.add(
        MealSection.breakfast,
        _createMeal(
          name: 'Protein Shake',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 9, 0),
          section: MealSection.breakfast,
          calories: 300,
          protein: 40,
        ),
      );
      yLog.add(
        MealSection.lunch,
        _createMeal(
          name: 'Turkey Sandwich',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 13, 30),
          section: MealSection.lunch,
          calories: 550,
          protein: 35,
        ),
      );
      dayLogStore[yesterdayKey] = yLog;

      final msg = await KynoAssistantService.instance.processQuery('How was my nutrition yesterday?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      expect(allText, contains('Yesterday Intake Summary'));
      expect(allText, contains('Protein Shake'));
      expect(allText, contains('Turkey Sandwich'));
      expect(allText, contains('Totals: 850 kcal, 75g P'));
    });

    test('8. Non-fabrication guarantee: when no records exist, Kyno states no meals logged and does not invent details', () async {
      // Empty dayLogStore for yesterday
      dayLogStore.remove(yesterdayKey);

      final msg = await KynoAssistantService.instance.processQuery('What did I eat yesterday?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');

      // FACT must state no meals were logged
      expect(allText, contains('No meals were logged in your DayLog for yesterday'));

      // UNKNOWN must clarify intake is untracked
      final unk = msg.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.unknown);
      expect(unk.detail, contains('not recorded'));

      // Must NOT fabricate any meal names or timestamps
      expect(allText, isNot(contains('Chicken')));
      expect(allText, isNot(contains('Rice')));
      expect(allText, isNot(contains('Shake')));
      expect(allText, isNot(contains('AM')));
      expect(allText, isNot(contains('PM')));
    });
  });

  group('Part 3: Multi-Meal Deterministic Fixture & Contextual Reasoning Tests', () {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    setUp(() async {
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dev Tester',
        age: 26,
        gender: 'male',
        height: 180,
        weight: 75,
        workoutDaysMin: 4,
        workoutDaysMax: 6,
        goal: 'muscle_gain',
      );

      // Seed 3 stalled shoulder press sessions
      await WorkoutService.instance.saveSession(_createSession(now.subtract(const Duration(days: 9)), 25.0, 8));
      await WorkoutService.instance.saveSession(_createSession(now.subtract(const Duration(days: 5)), 25.0, 8));
      await WorkoutService.instance.saveSession(_createSession(now.subtract(const Duration(days: 2)), 25.0, 8));

      // Seed 13 days of baseline low protein (72g / 750 kcal)
      for (int i = 2; i <= 14; i++) {
        final d = now.subtract(Duration(days: i));
        final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final dLog = DayLog()
          ..targetProtein = 150.0
          ..targetCalories = 2300.0
          ..gymDay = GymDay(didGym: i % 2 == 0);
        dLog.add(
          MealSection.lunch,
          _createMeal(
            name: 'Chicken Rice Bowl',
            time: DateTime(d.year, d.month, d.day, 12, 30),
            section: MealSection.lunch,
            calories: 750,
            protein: 72,
          ),
        );
        dayLogStore[dKey] = dLog;
      }

      // Seed Day 1 (yesterday) with deterministic 5-meal test fixture
      final yLog = DayLog()
        ..targetProtein = 150.0
        ..targetCalories = 2300.0
        ..gymDay = const GymDay(didGym: true);

      // Meal 1: Breakfast at 8:15 AM
      yLog.add(
        MealSection.breakfast,
        _createMeal(
          name: 'Oatmeal with Blueberries & Honey',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 8, 15),
          section: MealSection.breakfast,
          calories: 420,
          protein: 8,
          carbs: 78,
          fat: 6,
        ),
      );
      // Meal 2: Lunch at 1:15 PM (High protein anchor)
      yLog.add(
        MealSection.lunch,
        _createMeal(
          name: 'Grilled Chicken Breast with Jasmine Rice',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 13, 15),
          section: MealSection.lunch,
          calories: 680,
          protein: 52,
          carbs: 65,
          fat: 14,
        ),
      );
      // Meal 3: Evening snack at 5:30 PM
      yLog.add(
        MealSection.eveningSnack,
        _createMeal(
          name: 'Salted Pretzels & Iced Latte',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 17, 30),
          section: MealSection.eveningSnack,
          calories: 310,
          protein: 4,
          carbs: 56,
          fat: 6,
        ),
      );
      // Meal 4: Dinner at 8:15 PM (after 8 PM, low protein)
      yLog.add(
        MealSection.dinner,
        _createMeal(
          name: 'Vegetable Stir-Fry with Tofu',
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 20, 15),
          section: MealSection.dinner,
          calories: 650,
          protein: 16,
          carbs: 85,
          fat: 22,
        ),
      );
      // Meal 5: Late-night snack at 10:45 PM (Calorie-dense, low protein)
      yLog.add(
        MealSection.lateNight,
        _createMeal(
          name: "Ben & Jerry's Half Baked Ice Cream",
          time: DateTime(yesterday.year, yesterday.month, yesterday.day, 22, 45),
          section: MealSection.lateNight,
          calories: 540,
          protein: 6,
          carbs: 66,
          fat: 28,
        ),
      );

      dayLogStore[yesterdayKey] = yLog;
    });

    test('1. "What did I eat yesterday?" returns chronological exact meal names, times, and sections', () async {
      final msg = await KynoAssistantService.instance.processQuery('What did I eat yesterday?');
      expect(msg.structuredInsights, isNotNull);

      final fact = msg.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.fact);
      expect(fact.detail, contains('8:15 AM [BREAKFAST]: "Oatmeal with Blueberries & Honey"'));
      expect(fact.detail, contains('1:15 PM [LUNCH]: "Grilled Chicken Breast with Jasmine Rice"'));
      expect(fact.detail, contains('5:30 PM [EVENINGSNACK]: "Salted Pretzels & Iced Latte"'));
      expect(fact.detail, contains('8:15 PM [DINNER]: "Vegetable Stir-Fry with Tofu"'));
      expect(fact.detail, contains('10:45 PM [LATENIGHT]: "Ben & Jerry\'s Half Baked Ice Cream"'));

      // Chronological order verification
      final bPos = fact.detail.indexOf('Oatmeal with Blueberries & Honey');
      final lPos = fact.detail.indexOf('Grilled Chicken Breast with Jasmine Rice');
      final sPos = fact.detail.indexOf('Salted Pretzels & Iced Latte');
      final dPos = fact.detail.indexOf('Vegetable Stir-Fry with Tofu');
      final lnPos = fact.detail.indexOf('Ben & Jerry\'s Half Baked Ice Cream');
      expect(bPos < lPos && lPos < sPos && sPos < dPos && dPos < lnPos, isTrue);
    });

    test('2. "Did I eat anything late last night?" identifies exact late-night items with timestamps', () async {
      final msg = await KynoAssistantService.instance.processQuery('Did I eat anything late last night?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');
      expect(allText, contains('Logged Late-Night Meals'));
      expect(allText, contains('"Ben & Jerry\'s Half Baked Ice Cream" at 10:45 PM [LATENIGHT]'));
      expect(allText, contains('"Vegetable Stir-Fry with Tofu" at 8:15 PM [DINNER]'));
      expect(allText, contains('1190 kcal')); // 650 + 540 = 1190 kcal
    });

    test('3. "Why were my calories high yesterday?" identifies major contributors and surplus math', () async {
      final msg = await KynoAssistantService.instance.processQuery('Why were my calories high yesterday?');
      expect(msg.structuredInsights, isNotNull);

      final calc = msg.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.calculation);
      // Highest contributor: Grilled Chicken Breast (680 kcal)
      expect(calc.detail, contains('Highest contributor: "Grilled Chicken Breast with Jasmine Rice"'));
      expect(calc.detail, contains('680 kcal'));
      // Second highest: Vegetable Stir-Fry (650 kcal)
      expect(calc.detail, contains('Second highest contributor: "Vegetable Stir-Fry with Tofu"'));
      expect(calc.detail, contains('650 kcal'));
      // Delta: 2600 - 2400 = 200 kcal exceeded
      expect(calc.detail, contains('exceeded your configured target of 2400 kcal by 200 kcal'));
    });

    test('4. "Why am I not hitting protein?" identifies specific low-protein meals contributing to shortfall', () async {
      final msg = await KynoAssistantService.instance.processQuery('Why am I not hitting protein?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');
      // Identifies anchor vs low-protein count
      expect(allText, contains('High-protein anchor meals (≥30g): 1 logged'));
      expect(allText, contains('Low-protein meals (<15g): 3 of 5 meals'));
      // Contextual inference cites specific low-protein meals
      expect(allText, contains('Oatmeal with Blueberries & Honey'));
      expect(allText, contains('Salted Pretzels & Iced Latte'));
      expect(allText, contains('Ben & Jerry\'s Half Baked Ice Cream'));
    });

    test('5. "Why is my strength not increasing?" contextually integrates meal-level evidence with training plateau', () async {
      final msg = await KynoAssistantService.instance.processQuery('Why is my strength not increasing?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');
      // Longitudinal training plateau
      expect(allText, contains('DB Shoulder Press'));
      expect(allText, contains('25kg'));
      // Longitudinal nutrition math
      expect(allText, contains('Nutrition Record (14-Day Average)'));
      // Contextual recent meal evidence
      expect(allText, contains('Recent meal evidence'));
      expect(allText, contains('5 logged meals'));
      expect(allText, contains('1 anchor meal ≥30g, 3 low-protein selections <15g'));
      // Contextual inference mentions specific meal selections
      expect(allText, contains('multi-day protein shortfall'));
      expect(allText, contains('Oatmeal with Blueberries & Honey'));
    });

    test('6. "What is hurting my progress?" broad audit cites longitudinal plateau and meal-level bottleneck', () async {
      final msg = await KynoAssistantService.instance.processQuery('What is hurting my progress?');
      expect(msg.structuredInsights, isNotNull);

      final allText = msg.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join('\n');
      expect(allText, contains('Longitudinal Overview'));
      expect(allText, contains('Adherence Audit'));
      expect(allText, contains('Meal-Level Bottleneck'));
      expect(allText, contains('low-protein density across 3 of 5 logged meals'));
    });

    test('7. 14-Day nutrition math reconciliation contract (exact dates, numerators, denominators, and averages)', () async {
      // 1. Inspect actual stored records across the 14-day historical window
      final now = DateTime.now();
      double proteinSum = 0;
      double calorieSum = 0;
      int daysCount = 0;

      final inspectedDates = <String>[];

      for (int i = 1; i <= 14; i++) {
        final d = now.subtract(Duration(days: i));
        final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final log = dayLogStore[dKey];
        expect(log, isNotNull, reason: 'Expected DayLog for date $dKey in 14-day window');
        inspectedDates.add(dKey);

        final p = log!.totalProteinMid;
        final c = log.totalCaloriesMid;

        if (i == 1) {
          // Yesterday's multi-meal fixture: 86g protein, 2600 kcal
          expect(p, equals(86.0));
          expect(c, equals(2600.0));
        } else {
          // Baseline historical days (i = 2..14): 72g protein, 750 kcal
          expect(p, equals(72.0));
          expect(c, equals(750.0));
        }

        proteinSum += p;
        calorieSum += c;
        daysCount++;
      }

      expect(daysCount, equals(14));
      expect(proteinSum, equals(1022.0)); // 86 + (13 * 72) = 1022
      expect(calorieSum, equals(12350.0)); // 2600 + (13 * 750) = 12350

      final expectedAvgProtein = proteinSum / daysCount; // 73.0
      final expectedAvgCalories = calorieSum / daysCount; // 882.14...

      expect(expectedAvgProtein, equals(73.0));
      expect(expectedAvgCalories.round(), equals(882));

      // 2. Query live Kyno service and verify exact matching
      final msg = await KynoAssistantService.instance.processQuery('Why is my strength not increasing?');
      expect(msg.structuredInsights, isNotNull);

      final nutFact = msg.structuredInsights!.firstWhere(
        (i) => i.type == KynoInformationType.fact && i.title.contains('Nutrition Record'),
      );

      // Verify the live Kyno response exactly contains the reconciled 73g and 882 kcal values
      expect(nutFact.detail, contains('73g protein and 882 kcal/day across 14 logged days'));

      // Also verify calculation section matches the exact math
      final calcMath = msg.structuredInsights!.firstWhere(
        (i) => i.type == KynoInformationType.calculation && i.title.contains('Nutrition Adherence Math'),
      );
      expect(calcMath.detail, contains('Average protein intake was 48% of configured target (77g below daily 150g target on average).'));
      expect(calcMath.detail, contains('14 of last 14 logged days'));
    });
  });
}

