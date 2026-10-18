import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/models/coach_insight.dart';
import 'package:kynetix/services/kyno_assistant_service.dart';
import 'package:kynetix/services/kyno_context_service.dart';
import 'package:kynetix/services/kyno_historical_analysis_service.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/coach_service.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/saved_meal_service.dart';

import 'package:kynetix/services/nutrition_hydration_guard.dart';
import 'package:kynetix/services/mock_estimation_service.dart' show NutrientRange;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUserId = 'test-user-remediation';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    dayLogStore.clear();
    KynoContextService.instance.invalidate();
    KynoHistoricalAnalysisService.instance.invalidate();
    SavedMealService.instance.clearCache();
    
    NutritionHydrationGuard.instance.reset();
    NutritionHydrationGuard.instance.currentUserIdOverride = testUserId;
    NutritionHydrationGuard.instance.markComplete(testUserId);
    await UserNutritionMemory.instance.initForUser(testUserId);
  });


  group('TARGETED REMEDIATION: Kyno Targeted Runtime Suite', () {
    test('1. FACT: Kyno returns exact verified facts for logged workouts and meals', () async {
      // Setup deterministic workout
      final ex = Exercise(
        id: 'bench_press',
        name: 'Barbell Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
      );
      final workout = WorkoutSession(
        id: 'ws_det_01',
        date: DateTime.now(),
        splitDayName: 'Push / Chest Day',
        entries: [
          ExerciseEntry(
            exercise: ex,
            sets: const [
              SetEntry(weight: 100, reps: 5, setType: SetType.normal),
              SetEntry(weight: 100, reps: 5, setType: SetType.normal),
              SetEntry(weight: 100, reps: 5, setType: SetType.normal),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSession(workout);

      // Setup deterministic meal
      final meal = NutritionResult.createCustom(
        canonicalMeal: 'Chicken and Rice Bowl',
        calories: 650,
        protein: 52.5,
        source: 'user_override',
      );
      final today = DateTime.now();
      final log = logFor(today);
      log.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'Chicken and Rice Bowl',
          result: meal,
          addedAt: today,
          section: MealSection.lunch,
          dayOfWeek: today.weekday,
          parsedFoods: const ['Chicken', 'Rice'],
          finalSavedInput: 'Chicken and Rice Bowl',
        ),
      );

      // Query 1: Fact on training
      final trainReply = await KynoAssistantService.instance.processQuery('What did I train today?');
      expect(trainReply.structuredInsights, isNotNull);
      final trainFacts = trainReply.structuredInsights!.where((i) => i.type == KynoInformationType.fact).toList();
      expect(trainFacts, isNotEmpty);
      expect(trainFacts.any((f) => f.title.contains('Push / Chest Day')), isTrue, reason: 'Ground truth split day name must match');
      expect(trainFacts.any((f) => f.detail.contains('3 sets') && f.detail.contains('1500 kg')), isTrue, reason: 'Ground truth sets & volume (3 * 500kg = 1500kg) must match');

      // Query 2: Fact on nutrition
      final nutReply = await KynoAssistantService.instance.processQuery('How much protein have I had today?');
      final nutFacts = nutReply.structuredInsights!.where((i) => i.type == KynoInformationType.fact).toList();
      expect(nutFacts, isNotEmpty);
      expect(nutFacts.any((f) => f.detail.contains('52.5g protein')), isTrue, reason: 'Ground truth protein (52.5g) must match');
    });

    test('2. CALCULATION: Kyno computes mathematical deficit and average workload deterministically', () async {
      final today = DateTime.now();
      final log = logFor(today);
      log.targetCalories = 2400.0;
      log.targetProtein = 160.0;

      final meal = NutritionResult.createCustom(
        canonicalMeal: 'Salmon Fillet',
        calories: 500,
        protein: 40.0,
        source: 'verified_db',
      );
      log.add(
        MealSection.dinner,
        MealEntry(
          rawInput: 'Salmon Fillet',
          result: meal,
          addedAt: today,
          section: MealSection.dinner,
          dayOfWeek: today.weekday,
          parsedFoods: const ['Salmon'],
          finalSavedInput: 'Salmon Fillet',
        ),
      );

      final reply = await KynoAssistantService.instance.processQuery('How many calories do I have left?');
      final calculations = reply.structuredInsights!.where((i) => i.type == KynoInformationType.calculation).toList();
      expect(calculations, isNotEmpty);
      
      // Ground truth calculations:
      // Remaining calories = 2400 - 500 = 1900
      // Remaining protein = 160 - 40 = 120
      final hasCalOrProCalc = calculations.any((c) => c.detail.contains('1900') || c.detail.contains('120'));
      expect(hasCalOrProCalc, isTrue, reason: 'Deterministic mathematical calculation must equal exact target minus consumed');
    });

    test('3. INFERENCE / KYNO-TARGETED-03: Defensible 4-part structure and scientific language boundary', () async {
      final ex = Exercise(
        id: 'squat',
        name: 'Barbell Squat',
        muscleGroup: 'Legs',
        type: ExerciseType.barbellCompound,
      );
      final workout = WorkoutSession(
        id: 'ws_det_inf',
        date: DateTime.now(),
        splitDayName: 'Leg Day Heavy',
        entries: [
          ExerciseEntry(
            exercise: ex,
            sets: const [
              SetEntry(weight: 140, reps: 5, setType: SetType.normal),
              SetEntry(weight: 140, reps: 5, setType: SetType.normal),
              SetEntry(weight: 140, reps: 5, setType: SetType.normal),
              SetEntry(weight: 140, reps: 5, setType: SetType.normal),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSession(workout);

      final reply = await KynoAssistantService.instance.processQuery('I trained today. Am I eating enough protein to recover?');
      expect(reply.structuredInsights, isNotNull);

      // 1. FACT: The user completed the observed training volume.
      final facts = reply.structuredInsights!.where((i) => i.type == KynoInformationType.fact).toList();
      expect(facts, isNotEmpty, reason: 'FACT: Ground truth requires verified statement of observed activity');
      expect(
        facts.any((f) => f.detail.contains('protein consumed') && f.detail.contains('daily target')),
        isTrue,
        reason: 'FACT: Must state protein consumed against daily target',
      );

      // 2. CALCULATION: Protein consumed and protein remaining against the configured target.
      final calculations = reply.structuredInsights!.where((i) => i.type == KynoInformationType.calculation).toList();
      expect(calculations, isNotEmpty, reason: 'CALCULATION: Ground truth requires mathematical remaining deficit');
      expect(
        calculations.any((c) => c.title.toLowerCase().contains('target balance') && c.detail.contains('remaining to reach')),
        isTrue,
        reason: 'CALCULATION: Must compute protein remaining against configured target',
      );

      // 3. INFERENCE: The training session provides context for the recommendation to meet the user's configured protein target.
      // The system must NOT claim that the observed volume directly proves or quantifies muscle protein synthesis or physiological recovery requirements.
      final inferences = reply.structuredInsights!.where((i) => i.type == KynoInformationType.inference).toList();
      expect(inferences, isNotEmpty, reason: 'INFERENCE: Ground truth requires session contextualization');
      final inferenceItem = inferences.firstWhere((inf) => inf.title.toLowerCase().contains('recovery demand'));
      expect(
        inferenceItem.detail.contains('2800 kg volume across 4 working sets') &&
        inferenceItem.detail.contains('raising the importance of meeting your daily protein target'),
        isTrue,
        reason: 'INFERENCE: The training session provides context for the recommendation to meet the user\'s configured protein target',
      );

      // 4. RECOMMENDATION: Advisory action based on the configured target.
      final recommendations = reply.structuredInsights!.where((i) => i.type == KynoInformationType.recommendation).toList();
      expect(recommendations, isNotEmpty, reason: 'RECOMMENDATION: Ground truth requires actionable nutrition advisory');
      expect(
        recommendations.any((r) => r.detail.contains('Distribute your remaining')),
        isTrue,
        reason: 'RECOMMENDATION: Actionable distribution advice based on remaining deficit',
      );

      // 5. SCIENTIFIC LANGUAGE BOUNDARY CHECK:
      // Must NOT introduce claims about:
      // - muscle protein synthesis rate
      // - nitrogen balance
      // - CNS fatigue
      // - neuromuscular recovery
      // - guaranteed recovery effects
      // - causal physiological mechanisms not established by the available data
      final allText = [
        reply.text,
        ...reply.structuredInsights!.map((i) => '${i.title} ${i.detail}'),
      ].join(' ').toLowerCase();

      expect(allText.contains('rate of protein synthesis') || allText.contains('synthesis rate') || allText.contains('fractional synthetic'), isFalse,
          reason: 'Scientific Boundary: Must not quantify muscle protein synthesis rate');
      expect(allText.contains('nitrogen balance'), isFalse,
          reason: 'Scientific Boundary: Must not claim nitrogen balance without laboratory biomarker data');
      expect(allText.contains('cns fatigue') || allText.contains('central nervous'), isFalse,
          reason: 'Scientific Boundary: Must not diagnose CNS fatigue without neurophysiological testing');
      expect(allText.contains('neuromuscular recovery') || allText.contains('neuromuscular fatigue'), isFalse,
          reason: 'Scientific Boundary: Must not make unmeasured neuromuscular claims');
      expect(allText.contains('guaranteed recovery') || allText.contains('guarantee recovery'), isFalse,
          reason: 'Scientific Boundary: Must not guarantee physiological recovery outcomes');
    });

    test('4. RECOMMENDATION: Kyno provides actionable nutrition strategy matching real deficit', () async {
      final today = DateTime.now();
      final log = logFor(today);
      log.targetCalories = 2200.0;
      log.targetProtein = 150.0;

      final reply = await KynoAssistantService.instance.processQuery('What should I eat tonight?');
      final recs = reply.structuredInsights!.where((i) => i.type == KynoInformationType.recommendation).toList();
      expect(recs, isNotEmpty);
      expect(recs.first.detail, isNotEmpty);
    });

    test('5. UNKNOWN: Untracked metrics are acknowledged without hallucination', () async {
      final analysis = KynoHistoricalAnalysisService.instance.analyzeQuery('What was my VO2 max and sleep quality yesterday?');
      expect(analysis.insights, isNotEmpty);
      final untrackedNotice = analysis.insights.any((i) => i.detail.toLowerCase().contains('untracked') || i.detail.toLowerCase().contains('sleep') || i.detail.toLowerCase().contains('stress'));
      expect(untrackedNotice, isTrue, reason: 'Engine must explicitly inform user that untracked metrics are untracked');
    });

    test('6. CROSS-DOMAIN: Cross-domain query unifies workout session and daily protein deficit', () async {
      final ex = Exercise(
        id: 'incline_bench',
        name: 'Incline Barbell Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
      );
      final workout = WorkoutSession(
        id: 'ws_cross_01',
        date: DateTime.now(),
        splitDayName: 'Upper Body',
        entries: [
          ExerciseEntry(
            exercise: ex,
            sets: const [
              SetEntry(weight: 80, reps: 10, setType: SetType.normal),
              SetEntry(weight: 80, reps: 10, setType: SetType.normal),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSession(workout);

      final today = DateTime.now();
      final log = logFor(today);
      log.targetProtein = 160.0;
      log.targetCalories = 2500.0;
      log.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Greek Yogurt + Whey',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Greek Yogurt + Whey',
            calories: 200,
            protein: 30.0,
            source: 'test',
          ),
          addedAt: today,
          section: MealSection.breakfast,
          dayOfWeek: today.weekday,
          parsedFoods: const ['Greek Yogurt', 'Whey'],
          finalSavedInput: 'Greek Yogurt + Whey',
        ),
      );

      final reply = await KynoAssistantService.instance.processQuery('I trained chest today. Am I eating enough protein to recover?');
      expect(reply.structuredInsights, isNotNull);
      final types = reply.structuredInsights!.map((i) => i.type).toSet();
      expect(types.contains(KynoInformationType.fact), isTrue);
      expect(types.contains(KynoInformationType.calculation), isTrue);
      expect(types.contains(KynoInformationType.inference), isTrue);
      expect(types.contains(KynoInformationType.recommendation), isTrue);
    });
  });

  group('TARGETED REMEDIATION: Nutrition Target Engine Dynamic Live Suite', () {
    test('No Gym -> Gym and Gym -> No Gym dynamic target adjustment without restart', () {
      final engine = NutritionTargetEngine();
      const testProfile = UserProfile(
        name: 'Targeted Tester',
        gender: 'Male',
        age: 25,
        height: 180,
        weight: 75,
        workoutDaysMin: 3,
        workoutDaysMax: 5,
        goal: kLeanBulk,
      );

      final today = DateTime.now();

      // 1. Rest Day (didGym = false) - REST BEFORE
      final restTarget = engine.dayTarget(
        testProfile,
        isGymDay: false,
        date: today,
      );
      expect(restTarget.calories, equals(2482.5), reason: 'REST BEFORE calorie target must equal calculated rest baseline');
      expect(restTarget.protein, equals(127.5), reason: 'REST BEFORE protein target must equal 75kg * 1.70 rest baseline');
      print('[NUTRITION_EVIDENCE] REST BEFORE: calorie target = ${restTarget.calories} kcal, protein target = ${restTarget.protein} g');

      // 2. Training Day (didGym = true) - GYM
      final trainingTarget = engine.dayTarget(
        testProfile,
        isGymDay: true,
        workoutTypeName: 'Leg Day',
        date: today,
      );
      expect(trainingTarget.calories, equals(2682.5), reason: 'GYM calorie target must equal training target (200 kcal spread, weighted for 4 training days)');
      expect(trainingTarget.protein, equals(142.5), reason: 'GYM protein target must equal 75kg * 1.90 training target');
      print('[NUTRITION_EVIDENCE] GYM: calorie target = ${trainingTarget.calories} kcal, protein target = ${trainingTarget.protein} g');

      // Assert training day calories > rest day calories
      expect(trainingTarget.calories, greaterThan(restTarget.calories),
          reason: 'Training day must include workout energy expenditure delta');
      final delta = trainingTarget.calories - restTarget.calories;
      expect(delta, equals(200.0),
          reason: 'Workout expenditure delta must be exactly the 200 kcal training/rest spread');

      // 3. Revert back to No Gym - REST AFTER
      final revertedTarget = engine.dayTarget(
        testProfile,
        isGymDay: false,
        date: today,
      );
      expect(revertedTarget.calories, equals(2482.5), reason: 'REST AFTER calorie target must revert immediately');
      expect(revertedTarget.protein, equals(127.5), reason: 'REST AFTER protein target must revert immediately');
      print('[NUTRITION_EVIDENCE] REST AFTER: calorie target = ${revertedTarget.calories} kcal, protein target = ${revertedTarget.protein} g');
      expect(revertedTarget.calories, equals(restTarget.calories),
          reason: 'Toggling back to No Gym must revert target immediately without restart');

      // 4. Recommendation Cards via CoachService
      final log = DayLog();
      log.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'Healthy Balanced Meal',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Balanced Meal',
            calories: 700,
            protein: 50,
            source: 'test',
          ),
          addedAt: today,
          section: MealSection.lunch,
          dayOfWeek: today.weekday,
          parsedFoods: const ['Chicken', 'Veggies', 'Rice'],
          finalSavedInput: 'Healthy Balanced Meal',
        ),
      );

      final coachService = CoachService();
      final insights = coachService.insightsForDay(log, trainingTarget, profile: testProfile);
      expect(insights, isNotEmpty);
      expect(insights.any((ins) => ins.type == CoachInsightType.protein || ins.type == CoachInsightType.underEaten || ins.type == CoachInsightType.balance), isTrue);

      // 5. Daily Nutrition Quality Score
      final qualityScore = log.dailyNutritionScore;
      expect(qualityScore, isNotNull);
      expect(qualityScore!, inInclusiveRange(0, 100));
    });
  });

  group('TARGETED REMEDIATION: Historical Immutability Suite', () {
    test('Historical meal snapshot preserved exactly across global default and personal override changes', () async {
      final pastDate = DateTime(2026, 8, 15);
      final historicalLog = DayLog()
        ..targetCalories = 2350.0
        ..targetProtein = 155.0
        ..gymDay = const GymDay(didGym: true, splitDayName: 'Historical Push');

      // Snapshot food item logged on historical date
      final historicalResult = NutritionResult(
        canonicalMeal: 'Oatmeal with Almond Milk',
        calories: NutrientRange(min: 320, max: 320),
        protein: NutrientRange(min: 12, max: 12),
        confidence: 1.0,
        warnings: const [],
        source: 'historical_snapshot_v1',
        createdAt: pastDate,
        items: const [], // Snapshot macro record
      );

      final historicalEntry = MealEntry(
        rawInput: '1 bowl Oatmeal with Almond Milk',
        result: historicalResult,
        addedAt: pastDate,
        section: MealSection.breakfast,
        dayOfWeek: pastDate.weekday,
        parsedFoods: const ['Oatmeal', 'Almond Milk'],
        finalSavedInput: '1 bowl Oatmeal with Almond Milk',
      );

      historicalLog.add(MealSection.breakfast, historicalEntry);
      
      // Serialize to persistent JSON storage
      final serializedHistoricalJson = historicalLog.toJson();
      dayLogStore[dateKey(pastDate)] = historicalLog;

      // STEP 1: Verify exact historical snapshot
      expect(historicalLog.totalCaloriesMid, equals(320.0));
      expect(historicalLog.totalProteinMid, equals(12.0));
      expect(historicalLog.targetCalories, equals(2350.0));

      // STEP 2: Save personal override for Oatmeal to higher values
      await UserNutritionMemory.instance.saveOverride(
        'Oatmeal with Almond Milk',
        450.0, // Changed from 320 -> 450
        20.0,  // Changed from 12 -> 20
      );

      // STEP 3: Restart simulation — clear in-memory cache and reload from serialized storage
      dayLogStore.clear();
      final reloadedHistorical = DayLog.fromJson(serializedHistoricalJson);
      dayLogStore[dateKey(pastDate)] = reloadedHistorical;

      // Assert exact historical values MUST remain unchanged!
      expect(reloadedHistorical.totalCaloriesMid, equals(320.0),
          reason: 'Historical meal calories must be immutable and drift-protected against later overrides');
      expect(reloadedHistorical.totalProteinMid, equals(12.0),
          reason: 'Historical meal protein must remain exactly 12.0g as originally recorded');
      expect(reloadedHistorical.targetCalories, equals(2350.0),
          reason: 'Historical daily calorie target must remain 2350.0 kcal');

      // STEP 4: Log same food TODAY — new resolution MUST use the current updated override!
      final today = DateTime.now();
      final todayLog = logFor(today);
      final overrideLookup = UserNutritionMemory.instance.lookup('Oatmeal with Almond Milk');
      expect(overrideLookup, isNotNull);

      final todayResolvedResult = NutritionResult.createCustom(
        canonicalMeal: 'Oatmeal with Almond Milk',
        calories: overrideLookup!.calories.mid,
        protein: overrideLookup.protein.mid,
        source: 'user_override_active',
      );

      final todayEntry = MealEntry(
        rawInput: '1 bowl Oatmeal with Almond Milk',
        result: todayResolvedResult,
        addedAt: today,
        section: MealSection.breakfast,
        dayOfWeek: today.weekday,
        parsedFoods: const ['Oatmeal', 'Almond Milk'],
        finalSavedInput: '1 bowl Oatmeal with Almond Milk',
      );
      todayLog.add(MealSection.breakfast, todayEntry);

      expect(todayLog.totalCaloriesMid, equals(450.0),
          reason: 'New meal logged today must resolve with updated current values (450 kcal)');
      expect(todayLog.totalProteinMid, equals(20.0),
          reason: 'New meal logged today must resolve with updated current values (20g protein)');
      expect(reloadedHistorical.totalCaloriesMid, equals(320.0),
          reason: 'Historical day remains strictly unchanged at 320 kcal after today is logged');
    });
  });

  group('TARGETED REMEDIATION: Saved Meal Service & Search Suite', () {
    test('Saved meal can be created, searched, and reused with exact nutritional preservation', () {
      final dummyResult = NutritionResult.createCustom(
        canonicalMeal: 'Pre-Workout Oats and Whey Shake',
        calories: 480,
        protein: 38,
        source: 'user_saved',
      );

      final entry = MealEntry(
        rawInput: 'Pre-Workout Oats and Whey Shake',
        result: dummyResult,
        addedAt: DateTime.now(),
        section: MealSection.breakfast,
        dayOfWeek: 1,
        parsedFoods: const ['Oats', 'Whey'],
        finalSavedInput: 'Pre-Workout Oats and Whey Shake',
      );

      final log = logFor(DateTime.now());
      log.add(MealSection.breakfast, entry);

      // Search "oats and whey"
      final results = SavedMealService.instance.search('oats whey');
      expect(results, isNotEmpty);
      expect(results.first.title, contains('Oats'));
      expect(results.first.calories, closeTo(480, 1));
      expect(results.first.protein, closeTo(38, 1));
    });
  });
}
