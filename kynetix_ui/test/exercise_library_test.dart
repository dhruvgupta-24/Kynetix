import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/exercise_library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Force fallback/mock population if rootBundle is unavailable in CLI test runner
    await ExerciseLibraryService.instance.initialize();
  });

  group('ExerciseLibraryService Multi-Token Search & Taxonomy', () {
    test('Library contains definitions', () {
      final library = ExerciseLibraryService.instance.allDefinitions;
      expect(library.isNotEmpty, isTrue);
      expect(library.length, greaterThanOrEqualTo(30));
    });

    test('Multi-token search finds "incline db"', () {
      final results = ExerciseLibraryService.instance.search(query: 'incline db');
      expect(results.isNotEmpty, isTrue);
      final names = results.map((e) => e.name.toLowerCase()).toList();
      expect(names.any((n) => n.contains('incline') && (n.contains('db') || n.contains('dumbbell'))), isTrue);
    });

    test('Acronym search finds "ohp" and "rdl"', () {
      final ohpResults = ExerciseLibraryService.instance.search(query: 'ohp');
      expect(ohpResults.isNotEmpty, isTrue);
      expect(ohpResults.first.name.toLowerCase(), contains('overhead press'));

      final rdlResults = ExerciseLibraryService.instance.search(query: 'rdl');
      expect(rdlResults.isNotEmpty, isTrue);
      expect(rdlResults.first.name.toLowerCase(), contains('romanian deadlift'));
    });

    test('Category filtering restricts search to specified category', () {
      final chestExercises = ExerciseLibraryService.instance.search(
        query: 'press',
        category: 'Chest',
      );
      expect(chestExercises.isNotEmpty, isTrue);
      for (final ex in chestExercises) {
        expect(ex.category.toUpperCase(), equals('CHEST'));
      }
    });

    test('Equipment filtering works correctly', () {
      final barbellExercises = ExerciseLibraryService.instance.search(
        category: 'ALL',
        equipmentGroup: 'Barbell',
      );
      expect(barbellExercises.isNotEmpty, isTrue);
      for (final ex in barbellExercises) {
        expect(ex.equipmentGroup.toUpperCase(), equals('BARBELL'));
      }
    });

    test('Dynamic Category and Equipment counts are calculated without dead-ends', () {
      final catCounts = ExerciseLibraryService.instance.getCategoryCounts();
      expect(catCounts['ALL'], greaterThan(0));
      expect(catCounts['Chest'], greaterThan(0));

      final eqCounts = ExerciseLibraryService.instance.getEquipmentCounts();
      expect(eqCounts['ALL'], greaterThan(0));
      expect(eqCounts['Barbell'], greaterThan(0));
    });

    test('Custom exercises can be registered and searched', () {
      const customEx = Exercise(
        id: 'custom_bicep_blaster_999',
        name: 'Spider Arm Blaster Curl',
        muscleGroup: 'Biceps',
        type: ExerciseType.dumbbell,
      );

      ExerciseLibraryService.instance.registerCustomExercises([customEx]);

      final searchHit = ExerciseLibraryService.instance.search(query: 'Spider Arm');
      expect(searchHit.isNotEmpty, isTrue);
      expect(searchHit.first.id, equals('custom_bicep_blaster_999'));
      expect(searchHit.first.name, equals('Spider Arm Blaster Curl'));

      final retrieved = ExerciseLibraryService.instance.getById('custom_bicep_blaster_999');
      expect(retrieved, isNotNull);
      expect(retrieved!.name, equals('Spider Arm Blaster Curl'));
    });

    test('ExerciseDefinition converts seamlessly to Kynetix Exercise with progression type', () {
      const def = ExerciseDefinition(
        id: 'heavy_bb_squat',
        name: 'Heavy Back Squat',
        category: 'Legs',
        bodyPart: 'Upper Legs',
        equipment: 'Barbell',
        equipmentGroup: 'Barbell',
        targetMuscle: 'Quads',
        muscleGroup: 'Quads',
        exerciseType: ExerciseType.barbellCompound,
        defaultTargetSets: 4,
        defaultRepMin: 5,
        defaultRepMax: 8,
      );

      final ex = def.toExercise(customNotes: 'Belt on set 3+');
      expect(ex.id, equals('heavy_bb_squat'));
      expect(ex.name, equals('Heavy Back Squat'));
      expect(ex.type, equals(ExerciseType.barbellCompound));
      expect(ex.targetSets, equals(4));
      expect(ex.targetRepMin, equals(5));
      expect(ex.targetRepMax, equals(8));
      expect(ex.notes, equals('Belt on set 3+'));
    });
  });
}
