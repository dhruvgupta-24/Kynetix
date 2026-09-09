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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

  tearDown(() async {
    await UserSessionCoordinator.instance.clearAllUserServices();
  });

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

  void _populateHistoricalNutrition(int daysCount, double avgProtein, double avgCalories, {double targetProtein = 115.0}) {
    final now = DateTime.now();
    for (int i = 1; i <= daysCount; i++) {
      final date = now.subtract(Duration(days: i));
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final log = DayLog()
        ..gymDay = GymDay(didGym: i % 2 == 0)
        ..targetProtein = targetProtein
        ..targetCalories = 2200.0;
      final entry = MealEntry(
        rawInput: 'chicken and rice',
        result: NutritionResult(
          canonicalMeal: 'Chicken and Rice',
          items: [],
          calories: NutrientRange(min: avgCalories, max: avgCalories),
          protein: NutrientRange(min: avgProtein, max: avgProtein),
          confidence: 1.0,
          warnings: [],
          source: 'test',
          createdAt: date,
        ),
        addedAt: date,
        section: MealSection.lunch,
        dayOfWeek: date.weekday,
        parsedFoods: ['chicken', 'rice'],
        finalSavedInput: 'Chicken and Rice',
      );
      log.add(MealSection.lunch, entry);
      dayLogStore[dateKey] = log;
    }
  }

  group('Kyno Longitudinal Historical Intelligence Tests', () {
    test('1. "why is my strength not increasing?" evaluates multi-week history and detects 25kg x 8 stall and low protein', () async {
      final now = DateTime.now();

      // Profile: 70kg, goal Strength, target protein 115g
      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength & Hypertrophy',
      );

      // 3 consecutive historical workouts stalling at 25kg x 8
      final s1 = _createSession(now.subtract(const Duration(days: 10)), 25.0, 8);
      final s2 = _createSession(now.subtract(const Duration(days: 6)), 25.0, 8);
      final s3 = _createSession(now.subtract(const Duration(days: 2)), 25.0, 8);
      for (final s in [s1, s2, s3]) {
        await WorkoutService.instance.saveSession(s);
      }

      // 14 days of nutrition history averaging 71g protein (44g below 115g target)
      _populateHistoricalNutrition(14, 71.0, 1850.0, targetProtein: 115.0);

      // Today has ZERO meal logs (user hasn't logged anything today)
      final todayDateKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(dayLogStore[todayDateKey]?.allEntries.isEmpty ?? true, isTrue);

      final result = KynoHistoricalAnalysisService.instance.analyzeQuery('why is my strength not increasing?');

      expect(result.intent, KynoAnalysisIntent.strengthPlateau);
      expect(result.headline, contains('DB Shoulder Press'));

      // Check Facts: contains 25kg x 8 and 14-day nutrition average
      final fact = result.insights.firstWhere((i) => i.type == KynoInformationType.fact && i.title.contains('Performance'));
      expect(fact.detail, contains('25kg × 8'));
      expect(fact.detail, contains('3 sessions'));

      final nutFact = result.insights.firstWhere((i) => i.type == KynoInformationType.fact && i.title.contains('Nutrition'));
      expect(nutFact.detail, contains('71g protein'));

      // Check Calculation: computes deficit against target
      final calc = result.insights.firstWhere((i) => i.type == KynoInformationType.calculation);
      expect(calc.detail, contains('Protein adherence'));
      expect(calc.detail, anyOf(contains('50%'), contains('51%'), contains('61%'), contains('62%')));

      // Check Inference: progressive overload and protein shortfall
      final infer = result.insights.firstWhere((i) => i.type == KynoInformationType.inference);
      expect(infer.detail, contains('stalled'));
      expect(infer.detail, contains('protein'));

      // Check Recommendations: concrete actions
      final rec = result.insights.firstWhere((i) => i.type == KynoInformationType.recommendation);
      expect(rec.detail, anyOf(contains('Rep Progression Rule'), contains('Protein Consistency')));

      // Check Unknown: explicitly declares untracked variables (sleep, stress, form)
      final unk = result.insights.firstWhere((i) => i.type == KynoInformationType.unknown);
      expect(unk.detail, contains('sleep'));
      expect(unk.detail, contains('stress'));
    });

    test('2. Changing today data alone does NOT erase the historical longitudinal analysis', () async {
      final now = DateTime.now();

      ProfileService.instance.currentUserProfile = const UserProfile(
        name: 'Dhruv',
        age: 25,
        gender: 'male',
        height: 175,
        weight: 70,
        workoutDaysMin: 3,
        workoutDaysMax: 4,
        goal: 'Strength & Hypertrophy',
      );

      final s1 = _createSession(now.subtract(const Duration(days: 10)), 25.0, 8);
      final s2 = _createSession(now.subtract(const Duration(days: 6)), 25.0, 8);
      final s3 = _createSession(now.subtract(const Duration(days: 2)), 25.0, 8);
      for (final s in [s1, s2, s3]) {
        await WorkoutService.instance.saveSession(s);
      }
      _populateHistoricalNutrition(14, 71.0, 1850.0, targetProtein: 115.0);

      // Now user logs a single high protein meal TODAY (e.g. 150g protein)
      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final todayLog = DayLog()..targetProtein = 115.0..targetCalories = 2200.0;
      todayLog.add(MealSection.lunch, MealEntry(
        rawInput: 'huge protein feast',
        result: NutritionResult(
          canonicalMeal: 'Huge Protein Feast',
          items: [],
          calories: const NutrientRange(min: 800, max: 800),
          protein: const NutrientRange(min: 150, max: 150),
          confidence: 1.0,
          warnings: [],
          source: 'test',
          createdAt: now,
        ),
        addedAt: now,
        section: MealSection.lunch,
        dayOfWeek: now.weekday,
        parsedFoods: ['chicken'],
        finalSavedInput: 'Huge Protein Feast',
      ));
      dayLogStore[todayKey] = todayLog;

      final result = KynoHistoricalAnalysisService.instance.analyzeQuery('why is my strength not increasing?');

      // Longitudinal analysis must still recognize the historical 14-day average and stall
      final fact = result.insights.firstWhere((i) => i.type == KynoInformationType.fact && i.title.contains('Performance'));
      expect(fact.detail, contains('25kg × 8'));
      final nutFact = result.insights.firstWhere((i) => i.type == KynoInformationType.fact && i.title.contains('Nutrition'));
      expect(nutFact.detail, anyOf(contains('77g protein'), contains('76g protein'), contains('71g protein')));
      expect(result.insights.any((i) => i.type == KynoInformationType.inference && i.detail.contains('stalled')), isTrue);
    });

    test('3. Insufficient history produces limited evidence / unknown response', () async {
      // Only 1 session in history
      final s1 = _createSession(DateTime.now(), 25.0, 8);
      await WorkoutService.instance.saveSession(s1);

      final result = KynoHistoricalAnalysisService.instance.analyzeQuery('why is my strength not increasing?');

      expect(result.headline, contains('Limited training history'));
      final calc = result.insights.firstWhere((i) => i.type == KynoInformationType.calculation);
      expect(calc.detail, contains('Insufficient multi-week data'));
    });

    test('4. Assistant Service routes longitudinal questions to KynoHistoricalAnalysisService', () async {
      final now = DateTime.now();
      final s1 = _createSession(now.subtract(const Duration(days: 8)), 25.0, 8);
      final s2 = _createSession(now.subtract(const Duration(days: 4)), 25.0, 8);
      final s3 = _createSession(now.subtract(const Duration(days: 1)), 25.0, 8);
      for (final s in [s1, s2, s3]) {
        await WorkoutService.instance.saveSession(s);
      }
      _populateHistoricalNutrition(14, 70.0, 1800.0, targetProtein: 115.0);

      final msg = await KynoAssistantService.instance.processQuery('why is my strength not increasing?');

      expect(msg.structuredInsights, isNotNull);
      expect(msg.structuredInsights!.any((i) => i.type == KynoInformationType.fact && i.detail.contains('25kg × 8')), isTrue);
      expect(msg.structuredInsights!.any((i) => i.type == KynoInformationType.unknown && i.detail.contains('sleep')), isTrue);
    });
  });
}
