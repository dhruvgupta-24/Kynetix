import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/exercise_search_engine.dart';
import 'package:kynetix/services/exercise_query_normalizer.dart';
import 'package:kynetix/services/exercise_display_enhancer.dart';
import 'package:kynetix/services/user_exercise_preferences_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExerciseDefinition> testCatalog;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await UserExercisePreferencesService.instance.initialize();
    final file = File('assets/data/exercises_library.json');
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      final List<dynamic> list = jsonDecode(content);
      testCatalog = list.map((item) {
        final def = ExerciseDefinition.fromJson(item as Map<String, dynamic>);
        final displayName = ExerciseDisplayEnhancer.deriveDisplayName(def.canonicalName, def.equipment);
        final enhancedAliases = ExerciseDisplayEnhancer.buildEnhancedAliases(def);
        return ExerciseDefinition(
          id: def.id,
          name: def.canonicalName,
          canonicalName: def.canonicalName,
          displayName: displayName,
          category: def.category,
          bodyPart: def.bodyPart,
          equipment: def.equipment,
          equipmentGroup: def.equipmentGroup,
          targetMuscle: def.targetMuscle,
          muscleGroup: def.muscleGroup,
          secondaryMuscles: def.secondaryMuscles,
          instructions: def.instructions,
          aliases: enhancedAliases,
          exerciseType: def.exerciseType,
        );
      }).toList();
    } else {
      testCatalog = deduplicatedLibrary.map((ex) {
        final def = ExerciseDefinition.fromExercise(ex);
        final displayName = ExerciseDisplayEnhancer.deriveDisplayName(def.canonicalName, def.equipment);
        final enhancedAliases = ExerciseDisplayEnhancer.buildEnhancedAliases(def);
        return ExerciseDefinition(
          id: def.id,
          name: def.canonicalName,
          canonicalName: def.canonicalName,
          displayName: displayName,
          category: def.category,
          bodyPart: def.bodyPart,
          equipment: def.equipment,
          equipmentGroup: def.equipmentGroup,
          targetMuscle: def.targetMuscle,
          muscleGroup: def.muscleGroup,
          aliases: enhancedAliases,
          exerciseType: def.exerciseType,
        );
      }).toList();
    }

    ExerciseSearchEngine.instance.setDefinitions(testCatalog);
  });

  group('Kynetix Relevance-Ranked Exercise Search Engine', () {
    test('1. "t bar", "t-bar", "tbar", "t bar row" prominently rank T-Bar Row at the very top', () {
      final queries = ['t bar', 't-bar', 'tbar', 't bar row'];

      for (final q in queries) {
        final results = ExerciseSearchEngine.instance.search(
          allDefinitions: testCatalog,
          query: q,
          limit: 10,
        );

        expect(results.isNotEmpty, isTrue, reason: 'Query "$q" must return results');
        
        final topNames = results.take(3).map((r) => r.definition.displayName.toLowerCase()).toList();
        final hasTBarAtTop = topNames.any((name) => name.contains('t-bar') || name.contains('t bar') || name.contains('tbar'));
        expect(hasTBarAtTop, isTrue, reason: 'Top 3 results for "$q" must contain T-Bar Row: $topNames');

        // Verify weak token matches like "Straight Bar Dip" or "Barbell Curl" do NOT outrank T-Bar Row
        final top1 = results.first.definition.displayName.toLowerCase();
        expect(top1.contains('t-bar') || top1.contains('t bar') || top1.contains('tbar'), isTrue,
            reason: 'Rank #1 for "$q" must be a T-Bar exercise, got: $top1');
      }
    });

    test('2. Common gym shorthand ("db bench", "bb row", "ohp", "rdl", "lat pull")', () {
      // OHP
      final ohpHits = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: 'ohp',
        limit: 5,
      );
      expect(ohpHits.isNotEmpty, isTrue);
      final topOhp = ohpHits.first.definition.displayName.toLowerCase();
      expect(topOhp.contains('overhead press') || topOhp.contains('shoulder press'), isTrue,
          reason: 'OHP must match Overhead Press, got: $topOhp');

      // RDL
      final rdlHits = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: 'rdl',
        limit: 5,
      );
      expect(rdlHits.isNotEmpty, isTrue);
      final topRdl = rdlHits.first.definition.displayName.toLowerCase();
      expect(topRdl.contains('romanian deadlift') || topRdl.contains('deadlift'), isTrue,
          reason: 'RDL must match Romanian Deadlift, got: $topRdl');

      // DB Bench
      final dbBenchHits = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: 'db bench',
        limit: 5,
      );
      expect(dbBenchHits.isNotEmpty, isTrue);
      final topDbBench = dbBenchHits.first.definition.displayName.toLowerCase();
      expect(topDbBench.contains('dumbbell') && topDbBench.contains('bench'), isTrue,
          reason: '"db bench" must match Dumbbell Bench Press, got: $topDbBench');

      // BB Row
      final bbRowHits = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: 'bb row',
        limit: 5,
      );
      expect(bbRowHits.isNotEmpty, isTrue);
      final topBbRow = bbRowHits.first.definition.displayName.toLowerCase();
      expect(topBbRow.contains('barbell') && topBbRow.contains('row'), isTrue,
          reason: '"bb row" must match Barbell Row, got: $topBbRow');

      // Lat Pull
      final latPullHits = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: 'lat pull',
        limit: 5,
      );
      expect(latPullHits.isNotEmpty, isTrue);
      final topLatPull = latPullHits.first.definition.displayName.toLowerCase();
      expect(topLatPull.contains('pulldown') || topLatPull.contains('pull'), isTrue,
          reason: '"lat pull" must match Lat Pulldown, got: $topLatPull');
    });

    test('3. Natural language variations: "incline dumbbell press", "incline db press", "db incline press"', () {
      final v1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'incline dumbbell press', limit: 3);
      final v2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'incline db press', limit: 3);
      final v3 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'db incline press', limit: 3);

      expect(v1.isNotEmpty, isTrue);
      expect(v2.isNotEmpty, isTrue);
      expect(v3.isNotEmpty, isTrue);

      for (final res in [v1, v2, v3]) {
        final top = res.first.definition.displayName.toLowerCase();
        expect(top.contains('incline') && (top.contains('dumbbell') || top.contains('db')), isTrue,
            reason: 'Must match Incline Dumbbell Bench/Press, got: $top');
      }
    });

    test('4. Typo tolerance: "lat pulldwon", "dumbel bench", "romainian deadlift"', () {
      final typoLat = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'lat pulldwon', limit: 3);
      expect(typoLat.isNotEmpty, isTrue);
      expect(typoLat.first.definition.displayName.toLowerCase().contains('pulldown') ||
             typoLat.first.definition.displayName.toLowerCase().contains('lat'), isTrue);

      final typoBench = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'dumbel bench', limit: 3);
      expect(typoBench.isNotEmpty, isTrue);
      expect(typoBench.first.definition.displayName.toLowerCase().contains('dumbbell') ||
             typoBench.first.definition.displayName.toLowerCase().contains('bench'), isTrue);

      final typoRdl = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'romainian deadlift', limit: 3);
      expect(typoRdl.isNotEmpty, isTrue);
      expect(typoRdl.first.definition.displayName.toLowerCase().contains('deadlift'), isTrue);
    });

    test('5. Display name & canonical name preservation', () {
      final tbarDef = testCatalog.firstWhere(
        (def) => def.id == 'tbar_row' || def.id == '0606',
        orElse: () => testCatalog.first,
      );

      expect(tbarDef.canonicalName.isNotEmpty, isTrue);
      expect(tbarDef.displayName.isNotEmpty, isTrue);
      expect(tbarDef.aliases.isNotEmpty, isTrue);
    });

    test('6. Personal history boost and favorite persistence', () async {
      UserExercisePreferencesService.instance.seedForTesting(
        favorites: {'tbar_row'},
        history: {
          'bench_press': ExerciseUsageRecord(exerciseId: 'bench_press', selectionCount: 15),
        },
      );

      expect(UserExercisePreferencesService.instance.isFavorite('tbar_row'), isTrue);
      expect(UserExercisePreferencesService.instance.getPersonalBoost('bench_press'), greaterThan(100));

      // Toggle favorite off and on
      await UserExercisePreferencesService.instance.toggleFavorite('tbar_row');
      expect(UserExercisePreferencesService.instance.isFavorite('tbar_row'), isFalse);
      await UserExercisePreferencesService.instance.toggleFavorite('tbar_row');
      expect(UserExercisePreferencesService.instance.isFavorite('tbar_row'), isTrue);
    });

    test('7. Empty search returns favorites and recents at top', () {
      UserExercisePreferencesService.instance.seedForTesting(
        favorites: {'tbar_row'},
        history: {
          'bench_press': ExerciseUsageRecord(exerciseId: 'bench_press', selectionCount: 5),
        },
      );

      final emptyResults = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: '',
        limit: 10,
      );

      expect(emptyResults.isNotEmpty, isTrue);
      final topIds = emptyResults.take(3).map((r) => r.definition.id).toList();
      expect(topIds.contains('tbar_row') || topIds.contains('bench_press'), isTrue);
    });

    test('8. Catalog integrity: preferences and search never mutate built-in catalog', () {
      final initialCount = testCatalog.length;
      final initialFirstId = testCatalog.first.id;

      // Perform searches, toggle favorites, record history
      ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'squat');
      UserExercisePreferencesService.instance.recordSelection('squat');
      UserExercisePreferencesService.instance.toggleFavorite('squat');

      expect(testCatalog.length, equals(initialCount));
      expect(testCatalog.first.id, equals(initialFirstId));
    });
  });
}
