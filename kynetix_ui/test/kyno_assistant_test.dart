import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_log.dart';
import 'package:kynetix/models/nutrition_result.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/kyno_assistant_service.dart';
import 'package:kynetix/services/kyno_context_service.dart';
import 'package:kynetix/services/workout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dayLogStore.clear();
    KynoContextService.instance.invalidate();
  });

  group('KynoAssistantService Tests', () {
    test('Dynamic prompt suggestions reflect context', () {
      final chips = KynoAssistantService.instance.getContextualPromptSuggestions();
      expect(chips, isNotEmpty);
      expect(chips.any((c) => c.contains('protein') || c.contains('train') || c.contains('bench')), isTrue);
    });

    test('Query: What did I train today? returns verified workout session facts', () async {
      // 1. When no workout is logged
      final replyEmpty = await KynoAssistantService.instance.processQuery('What did I train today?');
      expect(replyEmpty.structuredInsights, isNotNull);
      final emptyFact = replyEmpty.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.fact);
      expect(emptyFact.detail, contains('not logged any workout'));

      // 2. When workout is logged
      final ex = Exercise(
        id: 'bench_press',
        name: 'Barbell Bench Press',
        muscleGroup: 'Chest',
        type: ExerciseType.barbellCompound,
      );
      final session = WorkoutSession(
        id: 'ws_test_today',
        date: DateTime.now(),
        splitDayName: 'Chest Day',
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

      final replyWorkout = await KynoAssistantService.instance.processQuery('What did I train today?');
      expect(replyWorkout.structuredInsights, isNotNull);
      final workoutFact = replyWorkout.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.fact);
      expect(workoutFact.title, contains('Chest Day'));
      expect(workoutFact.detail, contains('3 sets'));
    });

    test('Query: How much protein have I had today? returns exact logged facts', () async {
      final custom = NutritionResult.createCustom(
        canonicalMeal: 'Chicken and Rice',
        calories: 550,
        protein: 48,
        source: 'user_override',
      );
      final entry = MealEntry(
        rawInput: 'Chicken and Rice',
        result: custom,
        addedAt: DateTime.now(),
        section: MealSection.lunch,
        dayOfWeek: 1,
        parsedFoods: const ['Chicken Breast', 'Rice'],
        finalSavedInput: 'Chicken and Rice',
      );
      final log = logFor(DateTime.now());
      log.add(MealSection.lunch, entry);

      final reply = await KynoAssistantService.instance.processQuery('How much protein have I had today?');
      expect(reply.structuredInsights, isNotNull);
      final facts = reply.structuredInsights!.where((i) => i.type == KynoInformationType.fact).toList();
      expect(facts.any((f) => f.detail.contains('48.0g protein')), isTrue);
    });

    test('Query: Cross-domain "I trained chest today. Am I eating enough protein to recover?" combines both datasets', () async {
      // 1. Log chest workout
      final ex = Exercise(
        id: 'incline_db_press',
        name: 'Incline Dumbbell Press',
        muscleGroup: 'Chest',
        type: ExerciseType.dumbbell,
      );
      final session = WorkoutSession(
        id: 'ws_chest_recovery',
        date: DateTime.now(),
        splitDayName: 'Push / Chest',
        entries: [
          ExerciseEntry(
            exercise: ex,
            sets: const [
              SetEntry(weight: 30, reps: 10, setType: SetType.normal),
              SetEntry(weight: 30, reps: 10, setType: SetType.normal),
            ],
          ),
        ],
      );
      await WorkoutService.instance.saveSession(session);

      // 2. Log meal
      final custom = NutritionResult.createCustom(
        canonicalMeal: 'Protein Shake',
        calories: 200,
        protein: 30,
        source: 'user_override',
      );
      final entry = MealEntry(
        rawInput: 'Protein Shake',
        result: custom,
        addedAt: DateTime.now(),
        section: MealSection.breakfast,
        dayOfWeek: 1,
        parsedFoods: const ['Protein Powder'],
        finalSavedInput: 'Protein Shake',
      );
      final log = logFor(DateTime.now());
      log.add(MealSection.breakfast, entry);

      // 3. Ask cross-domain question
      final reply = await KynoAssistantService.instance.processQuery('I trained chest today. Am I eating enough protein to recover?');
      expect(reply.structuredInsights, isNotNull);

      // Verify both training AND nutrition appear in the structured insights
      final titlesAndDetails = reply.structuredInsights!.map((i) => '${i.title}: ${i.detail}').join(' ');
      expect(titlesAndDetails, contains('Push / Chest'));
      expect(titlesAndDetails, contains('30.0g protein'));
      expect(titlesAndDetails, contains('remaining'));
    });

    test('LIVE INVALIDATION: Ask protein -> log second meal -> ask again -> answer updates immediately without restart', () async {
      final log = logFor(DateTime.now());

      // 1. Initial meal (25g protein)
      log.add(
        MealSection.breakfast,
        MealEntry(
          rawInput: 'Eggs',
          result: NutritionResult.createCustom(
            canonicalMeal: '3 Boiled Eggs',
            calories: 210,
            protein: 25,
            source: 'user_override',
          ),
          addedAt: DateTime.now(),
          section: MealSection.breakfast,
          dayOfWeek: 1,
          parsedFoods: const ['Eggs'],
          finalSavedInput: '3 Boiled Eggs',
        ),
      );

      final reply1 = await KynoAssistantService.instance.processQuery('How much protein have I had today?');
      final fact1 = reply1.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.fact);
      expect(fact1.detail, contains('25.0g protein'));

      // 2. Log second meal (35g protein)
      log.add(
        MealSection.lunch,
        MealEntry(
          rawInput: 'Chicken Salad',
          result: NutritionResult.createCustom(
            canonicalMeal: 'Chicken Salad',
            calories: 400,
            protein: 35,
            source: 'user_override',
          ),
          addedAt: DateTime.now(),
          section: MealSection.lunch,
          dayOfWeek: 1,
          parsedFoods: const ['Chicken'],
          finalSavedInput: 'Chicken Salad',
        ),
      );
      // Simulate live invalidation called by AddMealScreen
      KynoContextService.instance.invalidate();

      // 3. Ask exact same question again
      final reply2 = await KynoAssistantService.instance.processQuery('How much protein have I had today?');
      final fact2 = reply2.structuredInsights!.firstWhere((i) => i.type == KynoInformationType.fact);
      expect(fact2.detail, contains('60.0g protein'));
      expect(fact2.detail, isNot(contains('25.0g protein')));
    });
  });
}
