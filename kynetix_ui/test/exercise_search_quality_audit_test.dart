import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/services/exercise_search_engine.dart';
import 'package:kynetix/services/exercise_display_enhancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExerciseDefinition> testCatalog;

  setUpAll(() {
    final file = File('assets/data/exercises_library.json');
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

    ExerciseSearchEngine.instance.setDefinitions(testCatalog);
  });

  group('Adversarial Real-World Search Quality Audit', () {
    test('1. "t bar row" and "t bar" reliably surface clean T-Bar Row as #1', () {
      final results1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 't bar row', limit: 5);
      expect(results1.isNotEmpty, isTrue);
      // Top result MUST be a clean T-Bar Row or T-Bar Row (Machine), NOT a Reverse Grip or Single-Arm variation
      final topName1 = results1.first.definition.displayName.toLowerCase();
      expect(topName1.contains('reverse'), isFalse);
      expect(topName1.contains('t-bar row') || topName1.contains('t bar row'), isTrue);

      final results2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 't bar', limit: 5);
      expect(results2.isNotEmpty, isTrue);
      final topName2 = results2.first.definition.displayName.toLowerCase();
      expect(topName2.contains('reverse'), isFalse);
      expect(topName2.contains('t-bar') || topName2.contains('t bar'), isTrue);
    });

    test('2. "bench press" surfaces clean Barbell Bench Press as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'bench press', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('bench press'), isTrue);
      expect(top.contains('decline') || top.contains('incline') || top.contains('reverse'), isFalse);
    });

    test('3. "db bench" surfaces Dumbbell Bench Press over Incline', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'db bench', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('dumbbell bench') || top.contains('db bench'), isTrue);
      expect(top.contains('incline') || top.contains('decline'), isFalse);
    });

    test('4. "incline db press" surfaces Incline Dumbbell Press as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'incline db press', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('incline') && (top.contains('dumbbell') || top.contains('db')), isTrue);
    });

    test('5. "rdl" and "romanian deadlift" surface Romanian Deadlift as #1', () {
      final results1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'rdl', limit: 5);
      expect(results1.isNotEmpty, isTrue);
      expect(results1.first.definition.displayName.toLowerCase().contains('romanian deadlift'), isTrue);

      final results2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'romanian deadlift', limit: 5);
      expect(results2.isNotEmpty, isTrue);
      expect(results2.first.definition.displayName.toLowerCase().contains('romanian deadlift'), isTrue);
    });

    test('6. "ohp" and "overhead press" surface clean Overhead Press as #1 (not band twist)', () {
      final results1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'ohp', limit: 5);
      expect(results1.isNotEmpty, isTrue);
      final top1 = results1.first.definition.displayName.toLowerCase();
      expect(top1.contains('overhead press'), isTrue);
      expect(top1.contains('band') || top1.contains('twisting'), isFalse);

      final results2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'overhead press', limit: 5);
      expect(results2.isNotEmpty, isTrue);
      final top2 = results2.first.definition.displayName.toLowerCase();
      expect(top2.contains('overhead press'), isTrue);
      expect(top2.contains('band') || top2.contains('twisting'), isFalse);
    });

    test('7. "lat pull" and "lat pulldown" surface clean Lat Pulldown as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'lat pull', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top == 'lat pulldown' || top == 'cable lat pulldown', isTrue);
    });

    test('8. "cable row" and "seated cable row" surface Seated Cable Row as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'cable row', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('cable row') || top.contains('seated row') || top.contains('seated cable row'), isTrue);
    });

    test('9. "lateral raise" surfaces clean Lateral Raise as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'lateral raise', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('lateral raise'), isTrue);
    });

    test('10. "leg press" surfaces clean Leg Press as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'leg press', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('leg press'), isTrue);
    });

    test('11. "bicep curl" and "dumbbell curl" surface clean Dumbbell / Barbell Curl as #1', () {
      final results1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'bicep curl', limit: 5);
      expect(results1.isNotEmpty, isTrue);
      final top1 = results1.first.definition.displayName.toLowerCase();
      expect(top1.contains('curl'), isTrue);

      final results2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'dumbbell curl', limit: 5);
      expect(results2.isNotEmpty, isTrue);
      final top2 = results2.first.definition.displayName.toLowerCase();
      expect(top2.contains('dumbbell') && top2.contains('curl'), isTrue);
    });

    test('12. "preacher curl" surfaces Preacher Curl as #1', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'preacher curl', limit: 5);
      expect(results.isNotEmpty, isTrue);
      final top = results.first.definition.displayName.toLowerCase();
      expect(top.contains('preacher curl'), isTrue);
    });
    test('13. Explicit variations win when specified by the user', () {
      // "reverse t bar row" -> Reverse variation MUST win over standard T-Bar Row
      final rReverseTBar = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'reverse t bar row', limit: 3);
      expect(rReverseTBar.isNotEmpty, isTrue);
      expect(rReverseTBar.first.definition.displayName.toLowerCase().contains('reverse'), isTrue);

      // "incline dumbbell press" -> Incline MUST win over flat Dumbbell Press
      final rInclineDb = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'incline dumbbell press', limit: 3);
      expect(rInclineDb.isNotEmpty, isTrue);
      expect(rInclineDb.first.definition.displayName.toLowerCase().contains('incline'), isTrue);

      // "close grip bench press" -> Close-Grip MUST win over standard Bench Press
      final rCloseGrip = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'close grip bench press', limit: 3);
      expect(rCloseGrip.isNotEmpty, isTrue);
      expect(rCloseGrip.first.definition.displayName.toLowerCase().contains('close'), isTrue);

      // "hammer curl" -> Hammer Curl MUST win over standard Bicep Curl
      final rHammer = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'hammer curl', limit: 3);
      expect(rHammer.isNotEmpty, isTrue);
      expect(rHammer.first.definition.displayName.toLowerCase().contains('hammer'), isTrue);

      // "single arm cable row" -> Single arm variation MUST win
      final rSingleArm = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'single arm cable row', limit: 3);
      expect(rSingleArm.isNotEmpty, isTrue);
      final topSA = rSingleArm.first.definition.displayName.toLowerCase();
      expect(topSA.contains('single') || topSA.contains('one arm'), isTrue);

      // "decline bench press" -> Decline MUST win over flat/incline
      final rDecline = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'decline bench press', limit: 3);
      expect(rDecline.isNotEmpty, isTrue);
      expect(rDecline.first.definition.displayName.toLowerCase().contains('decline'), isTrue);
    });

    test('14. Common gym abbreviations and aliases resolve to #1', () {
      final cases = {
        'bb bench': 'bench press',
        'db bench': 'dumbbell bench press',
        'ohp': 'overhead press',
        'rdl': 'romanian deadlift',
        'bb curl': 'barbell bicep curl',
        'ez bar curl': 'ez barbell curl',
        'arnold press': 'arnold press',
        'skull crushers': 'skull crusher',
        'pec deck': 'pec deck',
        'face pull': 'face pull',
      };

      for (final entry in cases.entries) {
        final res = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: entry.key, limit: 3);
        expect(res.isNotEmpty, isTrue, reason: 'Query "${entry.key}" should have results');
        final top = res.first.definition.displayName.toLowerCase();
        expect(
          top.contains(entry.value) ||
          top.contains(entry.key) ||
          (entry.key == 'ez bar curl' && (top.contains('ez') && top.contains('curl'))) ||
          (entry.key == 'skull crushers' && (top.contains('skull') && top.contains('crusher'))),
          isTrue,
          reason: 'Query "${entry.key}" top result was "$top", expected to contain "${entry.value}"',
        );
      }
    });

    test('15. Alternate spellings and equipment-first/exercise-first equivalences', () {
      // Alternate spellings for t-bar
      for (final q in ['t bar', 't-bar', 'tbar', 't-bar row', 't bar row']) {
        final res = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: q, limit: 3);
        expect(res.isNotEmpty, isTrue);
        final top = res.first.definition.displayName.toLowerCase();
        expect(top.contains('t-bar') || top.contains('t bar'), isTrue);
        expect(top.contains('reverse'), isFalse, reason: 'For query "$q", standard T-Bar should beat Reverse');
      }

      // Equipment-first vs movement-first
      final res1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'dumbbell incline press', limit: 3);
      final res2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'incline dumbbell press', limit: 3);
      expect(res1.isNotEmpty && res2.isNotEmpty, isTrue);
      expect(res1.first.definition.displayName.toLowerCase().contains('incline'), isTrue);
      expect(res2.first.definition.displayName.toLowerCase().contains('incline'), isTrue);
    });

    test('16. Partial searches and typos resolve gracefully', () {
      // Partials
      final rPartial1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'lat pull', limit: 3);
      expect(rPartial1.isNotEmpty, isTrue);
      expect(rPartial1.first.definition.displayName.toLowerCase().contains('lat pull'), isTrue);

      final rPartial2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'inc db', limit: 3);
      expect(rPartial2.isNotEmpty, isTrue);
      final topInc = rPartial2.first.definition.displayName.toLowerCase();
      expect(topInc.contains('incline') && (topInc.contains('dumbbell') || topInc.contains('db')), isTrue);

      // Typos
      final rTypo1 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'bicep curll', limit: 3);
      expect(rTypo1.isNotEmpty, isTrue);
      expect(rTypo1.first.definition.displayName.toLowerCase().contains('curl'), isTrue);

      final rTypo2 = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'incline bnech', limit: 3);
      expect(rTypo2.isNotEmpty, isTrue);
      expect(rTypo2.first.definition.displayName.toLowerCase().contains('incline'), isTrue);
    });

    test('17. Search deduplication eliminates duplicate display names in results', () {
      final results = ExerciseSearchEngine.instance.search(allDefinitions: testCatalog, query: 'bench press', limit: 20);
      final seenDisplayKeys = <String>{};
      for (final r in results) {
        final key = '${r.definition.displayName.toLowerCase()}_${r.definition.equipmentGroup}';
        expect(seenDisplayKeys.contains(key), isFalse,
            reason: 'Found duplicate display key in search results: $key');
        seenDisplayKeys.add(key);
      }
    });

    test('18. Favorites and recents only break close ties without overriding explicit intent', () {
      // If user has "Squat" in recents/favorites, searching "bench press" MUST still return Bench Press #1, never Squat
      final squatDef = testCatalog.firstWhere((e) => e.displayName.toLowerCase().contains('squat'));
      final benchPressResults = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: 'bench press',
        recentExerciseIds: {squatDef.id},
        limit: 5,
      );
      expect(benchPressResults.first.definition.displayName.toLowerCase().contains('bench press'), isTrue);
      expect(benchPressResults.first.definition.displayName.toLowerCase().contains('squat'), isFalse);
    });
  });
}
