import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/services/exercise_library_service.dart';
import 'package:kynetix/services/exercise_search_engine.dart';
import 'package:kynetix/services/exercise_display_enhancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Showcase top results for 25+ real-world gym queries', () {
    final file = File('assets/data/exercises_library.json');
    final content = file.readAsStringSync();
    final List<dynamic> list = jsonDecode(content);
    final testCatalog = list.map((item) {
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

    final queries = [
      't bar row',
      't bar',
      't-bar',
      'tbar',
      'bench press',
      'barbell bench press',
      'db bench',
      'dumbbell bench press',
      'incline db press',
      'row',
      'cable row',
      'seated cable row',
      'chest supported row',
      'rdl',
      'romanian deadlift',
      'dumbbell rdl',
      'ohp',
      'overhead press',
      'shoulder press',
      'lat pull',
      'lat pulldown',
      'bicep curl',
      'dumbbell curl',
      'preacher curl',
      'lateral raise',
      'dumbbell lateral raise',
      'cable lateral raise',
      'leg press',
      'leg extension',
      'leg curl',
    ];

    print('\n================ 25+ REAL-WORLD EXERCISE DISCOVERY SHOWCASE ================');
    for (final q in queries) {
      final results = ExerciseSearchEngine.instance.search(
        allDefinitions: testCatalog,
        query: q,
        limit: 3,
      );
      print('\nQUERY: "$q" (${results.length} results)');
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        print('  #${i + 1}: ${r.definition.displayName} (Equip: ${r.definition.equipment}) [Score: ${r.score}] - Reason: ${r.matchReason.label}');
      }
      expect(results.isNotEmpty, isTrue);
    }
    print('============================================================================\n');
  });
}
