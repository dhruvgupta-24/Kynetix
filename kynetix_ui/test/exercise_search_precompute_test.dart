import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/services/exercise_display_enhancer.dart';
import 'package:kynetix/services/exercise_search_engine.dart';
import 'package:kynetix/services/user_exercise_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legacy_exercise_search_engine.dart' as legacy;

/// The search engine now precomputes each exercise's normalized fields once.
/// Results (order, score, reason, best-match flag) must be identical to the
/// pre-optimisation engine for every query and filter combination.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExerciseDefinition> catalog;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await UserExercisePreferencesService.instance.initialize();
    final list = jsonDecode(File('assets/data/exercises_library.json').readAsStringSync()) as List<dynamic>;
    catalog = list.map((item) {
      final def = ExerciseDefinition.fromJson(item as Map<String, dynamic>);
      return ExerciseDefinition(
        id: def.id,
        name: def.canonicalName,
        canonicalName: def.canonicalName,
        displayName: ExerciseDisplayEnhancer.deriveDisplayName(def.canonicalName, def.equipment),
        category: def.category,
        bodyPart: def.bodyPart,
        equipment: def.equipment,
        equipmentGroup: def.equipmentGroup,
        targetMuscle: def.targetMuscle,
        muscleGroup: def.muscleGroup,
        aliases: ExerciseDisplayEnhancer.buildEnhancedAliases(def),
        exerciseType: def.exerciseType,
      );
    }).toList();
    expect(catalog.length, greaterThan(1000));
    ExerciseSearchEngine.instance.setDefinitions(catalog);
    legacy.ExerciseSearchEngine.instance.setDefinitions(catalog);
  });

  const queries = [
    'bench', 'bench press', 'incline db', 'db incline press', 't bar', 't-bar row', 'tbar',
    'ohp', 'rdl', 'lat pull', 'pullup', 'squat', 'curl', 'hammer curl', 'reverse curl',
    'single arm row', 'one leg press', 'cable fly', 'pec deck', 'skull crusher', 'face pull',
    'calf', 'abs', 'deadlfit', 'sqaut', 'benchh pres', 'tricep', 'shoulder press seated',
    'b', 'x', 'z', 'leg', 'barbell', 'dumbbell bench', 'smith', 'kettlebell swing',
    'close grip bench press', 'seated row', 'hip thrust', 'shrug', 'push up', 'chin up',
    'wide grip lat pulldown machine', 'romanian deadlift dumbbell', 'zzzz qqqq', '',
  ];

  String describe(List<dynamic> results) => results
      .map((r) => '${r.definition.id}|${r.score}|${r.matchReason.type}|${r.matchReason.label}|${r.isBestMatch}')
      .join('\n');

  test('results are identical to the pre-optimisation engine', () {
    for (final q in queries) {
      for (final filter in const [
        (null, null),
        ('Chest', null),
        (null, 'Dumbbell'),
        ('Back', 'Cable'),
      ]) {
        final now = ExerciseSearchEngine.instance.search(
          allDefinitions: catalog,
          query: q,
          category: filter.$1,
          equipmentGroup: filter.$2,
          splitExerciseIds: {catalog[3].id, catalog[40].id},
          recentExerciseIds: {catalog[7].id},
          excludeIds: {catalog[11].id},
        );
        final before = legacy.ExerciseSearchEngine.instance.search(
          allDefinitions: catalog,
          query: q,
          category: filter.$1,
          equipmentGroup: filter.$2,
          splitExerciseIds: {catalog[3].id, catalog[40].id},
          recentExerciseIds: {catalog[7].id},
          excludeIds: {catalog[11].id},
        );
        expect(describe(now), describe(before), reason: 'query "$q" filter $filter');
      }
    }
  });

  test('a definition outside the index still scores identically', () {
    final extra = ExerciseDefinition(
      id: 'custom_x',
      name: 'Custom Zercher Squat',
      canonicalName: 'custom zercher squat',
      displayName: 'Custom Zercher Squat',
      category: 'Legs',
      bodyPart: 'Upper Legs',
      equipment: 'Barbell',
      equipmentGroup: 'Barbell',
      targetMuscle: 'Quads',
      muscleGroup: 'Quads',
      aliases: const ['zercher'],
      exerciseType: catalog.first.exerciseType,
    );
    // Same length as the index, different contents: the stale index path.
    final swapped = [extra, ...catalog.skip(1)];
    for (final q in const ['zercher', 'custom squat', 'zerhcer squat', 'squat']) {
      final now = ExerciseSearchEngine.instance.search(allDefinitions: swapped, query: q);
      final before = legacy.ExerciseSearchEngine.instance.search(allDefinitions: swapped, query: q);
      expect(describe(now), describe(before), reason: q);
    }
  });

  test('search is faster than the pre-optimisation engine', () {
    final sw = Stopwatch()..start();
    for (final q in queries) {
      legacy.ExerciseSearchEngine.instance.search(allDefinitions: catalog, query: q);
    }
    final before = sw.elapsedMicroseconds;
    sw
      ..reset()
      ..start();
    for (final q in queries) {
      ExerciseSearchEngine.instance.search(allDefinitions: catalog, query: q);
    }
    final now = sw.elapsedMicroseconds;
    // ignore: avoid_print
    print('search over ${queries.length} queries: before=${before ~/ 1000} ms, now=${now ~/ 1000} ms');
    expect(now, lessThan(before));
  });
}
