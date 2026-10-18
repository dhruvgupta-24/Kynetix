import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/data/exercise_classification.dart';
import 'package:kynetix/models/exercise_definition.dart';
import 'package:kynetix/models/workout_split.dart';

ExerciseClassification _c(String name, {String id = '', String? equipment, String? muscle, ExerciseType? stored}) =>
    ExerciseClassifier.classify(id: id, name: name, equipment: equipment, muscle: muscle, storedType: stored);

void main() {
  group('bodyweight movements', () {
    for (final name in ['Pull-ups', 'Pull Up', 'Chin-ups', 'Dips', 'Push-ups', 'Chest Dip', 'Inverted Row']) {
      test('$name is bodyweight', () {
        final c = _c(name);
        expect(c.equipment, EquipmentKind.bodyweight);
        expect(c.type, ExerciseType.bodyweight);
        expect(c.isCompound, isTrue);
        expect(c.label, 'Bodyweight');
      });
    }

    test('a saved barbell type does not make Pull-ups a barbell lift', () {
      final c = _c('Pull-ups', stored: ExerciseType.barbellCompound);
      expect(c.type, ExerciseType.bodyweight);
      expect(c.label, 'Bodyweight');
    });

    test('Weighted Pull-up is weighted bodyweight', () {
      for (final c in [_c('Weighted Pull-up'), _c('Weighted Pull-up', equipment: 'Weighted')]) {
        expect(c.type, ExerciseType.bodyweight);
        expect(c.isWeighted, isTrue);
        expect(c.bodyweightMode, ExerciseExecutionMode.weightedBodyweight);
        expect(c.label, 'Bodyweight, weighted');
      }
    });

    test('a plate held for a front raise is a plate, not bodyweight', () {
      final c = _c('Weighted Front Raise', equipment: 'Weighted');
      expect(c.equipment, EquipmentKind.plate);
      expect(c.isCompound, isFalse);
    });

    test('push-ups on dumbbells or a ball are still bodyweight', () {
      expect(_c('Push-up Close-grip Off Dumbbell', equipment: 'Dumbbell').label, 'Bodyweight');
      expect(_c('Push-up (on Stability Ball)', equipment: 'Stability Ball').label, 'Bodyweight');
      expect(_c('Kettlebell Plyo Push-up', equipment: 'Kettlebell').label, 'Bodyweight');
    });

    test('band assisted pull-up is assisted bodyweight, a banded crunch stays a band move', () {
      expect(_c('Band Assisted Pull-up', equipment: 'Band').label, 'Bodyweight, assisted');
      expect(_c('Band Bicycle Crunch', equipment: 'Band').label, 'Band');
    });
  });

  group('barbell', () {
    for (final name in ['Barbell Curl', 'Skull Crusher', 'Barbell Shrug', 'Barbell Wrist Curl']) {
      test('$name is a barbell isolation lift', () {
        final c = _c(name, stored: ExerciseType.barbellCompound);
        expect(c.equipment, anyOf(EquipmentKind.barbell, EquipmentKind.ezBar));
        expect(c.isCompound, isFalse);
        expect(c.type, ExerciseType.isolation);
      });
    }

    test('labels say barbell and isolation', () {
      expect(_c('Barbell Curl').label, 'Barbell, isolation');
      expect(_c('Barbell Biceps Curl', equipment: 'Barbell').label, 'Barbell, isolation');
    });

    for (final name in ['Bench Press', 'Squat', 'Deadlift', 'Barbell Row', 'Overhead Press', 'Romanian Deadlift']) {
      test('$name is a barbell compound lift', () {
        final c = _c(name);
        expect(c.equipment, EquipmentKind.barbell);
        expect(c.isCompound, isTrue);
        expect(c.type, ExerciseType.barbellCompound);
        expect(c.label, 'Barbell, compound');
      });
    }

    test('trap bar and EZ bar', () {
      expect(_c('Trap Bar Deadlift', equipment: 'Trap Bar').label, 'Trap bar, compound');
      expect(_c('Ez Barbell Curl', equipment: 'EZ Barbell').label, 'EZ bar, isolation');
    });
  });

  group('machines and cables', () {
    for (final name in ['Leg Press', 'Hack Squat', 'Leg Extension', 'Pec Dec', 'Seated Calf Raise']) {
      test('$name is a machine, not a cable', () {
        final c = _c(name);
        expect(c.equipment, EquipmentKind.machine);
        expect(c.type, ExerciseType.cableMachine);
        expect(c.label, 'Machine');
      });
    }

    for (final name in ['Lat Pulldown', 'Tricep Pushdown', 'Face Pull', 'Cable Chest Fly']) {
      test('$name is a cable exercise', () {
        final c = _c(name);
        expect(c.equipment, EquipmentKind.cable);
        expect(c.type, ExerciseType.cableMachine);
        expect(c.label, 'Cable');
      });
    }

    test('assisted pull-up on the counterweight machine is a machine', () {
      for (final c in [
        _c('Assisted Pull-up'),
        _c('Assisted Pull-up (machine)'),
        _c('Assisted Pull-up', equipment: 'Leverage Machine'),
      ]) {
        expect(c.equipment, EquipmentKind.machine);
        expect(c.type, ExerciseType.cableMachine);
        expect(c.isAssisted, isTrue);
      }
    });

    test('Smith machine has its own label and bar progression', () {
      final press = _c('Smith Bench Press', equipment: 'Smith Machine');
      expect(press.label, 'Smith machine');
      expect(press.type, ExerciseType.barbellCompound);
      expect(_c('Smith Shrug', equipment: 'Smith Machine').type, ExerciseType.isolation);
    });

    test('cardio machines', () {
      expect(_c('Walk Elliptical Cross Trainer', equipment: 'Elliptical Machine').label, 'Cardio machine');
      expect(_c('Walking On Incline Treadmill', equipment: 'Leverage Machine').label, 'Cardio machine');
    });
  });

  group('dumbbells and kettlebells', () {
    test('compound and isolation', () {
      expect(_c('Dumbbell Bench Press').label, 'Dumbbell, compound');
      expect(_c('Dumbbell Lateral Raise').label, 'Dumbbell, isolation');
      expect(_c('Incline DB Curl').type, ExerciseType.dumbbell);
    });

    test('kettlebell swing is a kettlebell move on dumbbell increments', () {
      final c = _c('Kettlebell Swing', equipment: 'Kettlebell');
      expect(c.label, 'Kettlebell');
      expect(c.type, ExerciseType.dumbbell);
      expect(c.isCompound, isTrue);
    });
  });

  group('unknown names never become a barbell lift', () {
    test('no name cue and no saved type is isolation', () {
      final c = _c('Mystery Move');
      expect(c.type, isNot(ExerciseType.barbellCompound));
    });

    test('a saved type is kept when the name says nothing', () {
      expect(_c('Mystery Move', stored: ExerciseType.dumbbell).type, ExerciseType.dumbbell);
      expect(_c('Mystery Move', stored: ExerciseType.cableMachine).label, 'Cable or machine');
    });
  });

  group('saved data repair', () {
    test('a stored Pull-ups with no type loads as bodyweight', () {
      final ex = Exercise.fromJson({'id': 'pullups', 'name': 'Pull-ups', 'muscleGroup': 'Back'});
      expect(ex.type, ExerciseType.bodyweight);
      expect(ex.effectiveExecutionMode, ExerciseExecutionMode.bodyweightReps);
      expect(ExerciseClassifier.forExercise(ex).label, 'Bodyweight');
    });

    test('a custom Pull-ups saved as a barbell lift loads as bodyweight', () {
      final ex = Exercise.fromJson({'id': 'custom_1', 'name': 'Pull-ups', 'muscleGroup': 'Back', 'type': 0});
      expect(ex.type, ExerciseType.bodyweight);
      expect(ex.id, 'custom_1');
      expect(ex.name, 'Pull-ups');
    });

    test('a missing type never becomes barbellCompound', () {
      for (final name in ['Leg Extension', 'Tricep Pushdown', 'Hammer Curl', 'Something New', 'Plank']) {
        final ex = Exercise.fromJson({'id': 'x', 'name': name, 'muscleGroup': 'Other'});
        expect(ex.type, isNot(ExerciseType.barbellCompound), reason: name);
      }
    });

    test('weighted pull-ups load in weighted bodyweight mode, a stored mode wins', () {
      final ex = Exercise.fromJson({'id': '0841', 'name': 'Weighted Pull-up', 'muscleGroup': 'Lats', 'type': 3});
      expect(ex.type, ExerciseType.bodyweight);
      expect(ex.executionMode, ExerciseExecutionMode.weightedBodyweight);
      final kept = Exercise.fromJson({
        'id': '0841',
        'name': 'Weighted Pull-up',
        'type': 3,
        'executionMode': 'bodyweightReps',
      });
      expect(kept.executionMode, ExerciseExecutionMode.bodyweightReps);
    });

    test('everything else survives the round trip', () {
      final json = {
        'id': 'pullups',
        'name': 'Pull-ups',
        'muscleGroup': 'Back',
        'defaultTargetSets': 4,
        'defaultRepMin': 6,
        'defaultRepMax': 10,
        'notes': 'Dead hang start',
        'supersetGroupId': 'ss1',
      };
      final ex = Exercise.fromJson(json);
      expect(ex.targetSets, 4);
      expect(ex.targetRepMin, 6);
      expect(ex.targetRepMax, 10);
      expect(ex.notes, 'Dead hang start');
      expect(ex.supersetGroupId, 'ss1');
      expect(Exercise.fromJson(ex.toJson()).type, ExerciseType.bodyweight);
    });
  });

  group('built-in templates', () {
    test('every template type matches the classifier', () {
      final mismatches = <String>[];
      for (final ex in [...deduplicatedLibrary, ...developersChoiceSplit.days.expand((d) => d.exercises)]) {
        final c = ExerciseClassifier.forExercise(ex);
        if (c.type != ex.type) mismatches.add('${ex.id}: ${ex.type.name} vs ${c.type.name} (${c.label})');
      }
      expect(mismatches, isEmpty);
    });

    test('spot checks', () {
      Exercise ex(String id) => deduplicatedLibrary.firstWhere((e) => e.id == id);
      expect(ex('pullups').type, ExerciseType.bodyweight);
      expect(ex('bb_curl').type, ExerciseType.isolation);
      expect(ex('skullcrusher').type, ExerciseType.isolation);
      expect(ExerciseClassifier.forExercise(ex('leg_press')).label, 'Machine');
      expect(ExerciseClassifier.forExercise(ex('lat_pulldown')).label, 'Cable');
      expect(ExerciseClassifier.forExercise(ex('bench_press')).label, 'Barbell, compound');
    });
  });

  group('bundled library', () {
    late List<Map<String, dynamic>> entries;

    setUpAll(() {
      final raw = File('assets/data/exercises_library.json').readAsStringSync();
      entries = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    });

    test('has every entry', () {
      expect(entries.length, 1363);
    });

    test('every stored exerciseType matches the classifier', () {
      final mismatches = <String>[];
      for (final e in entries) {
        final c = ExerciseClassifier.classify(
          id: e['id'] as String,
          name: e['name'] as String,
          equipment: e['equipment'] as String?,
          muscle: e['targetMuscle'] as String?,
        );
        if (c.type.index != e['exerciseType']) {
          mismatches.add('${e['name']}: ${e['exerciseType']} vs ${c.type.index}');
        }
      }
      expect(mismatches, isEmpty);
    });

    test('sanity: equipment and type agree', () {
      final bad = <String>[];
      for (final e in entries) {
        final eq = e['equipment'] as String;
        final t = ExerciseType.values[e['exerciseType'] as int];
        final name = e['name'] as String;
        if (eq == 'Body Weight' && t == ExerciseType.barbellCompound) bad.add('$name: bodyweight typed barbell');
        if (eq == 'Body Weight' && t != ExerciseType.bodyweight) bad.add('$name: bodyweight typed ${t.name}');
        if (eq == 'Barbell' && t == ExerciseType.bodyweight) bad.add('$name: barbell typed bodyweight');
        if (eq == 'Barbell' && t != ExerciseType.barbellCompound && t != ExerciseType.isolation) {
          bad.add('$name: barbell typed ${t.name}');
        }
        if (eq == 'Cable' && t != ExerciseType.cableMachine) bad.add('$name: cable typed ${t.name}');
        if ((eq == 'Leverage Machine' || eq == 'Sled Machine') && t != ExerciseType.cableMachine) {
          bad.add('$name: machine typed ${t.name}');
        }
        if (eq == 'Dumbbell' && t == ExerciseType.barbellCompound) bad.add('$name: dumbbell typed barbell');
        if (eq == 'Kettlebell' && t == ExerciseType.barbellCompound) bad.add('$name: kettlebell typed barbell');
        final n = name.toLowerCase();
        if (RegExp(r'\b(curl|kickback|lateral raise|shrug|wrist)\b').hasMatch(n) &&
            t == ExerciseType.barbellCompound) {
          bad.add('$name: isolation move typed barbell compound');
        }
        if (RegExp(r'^(pull-ups?|chin-ups?|dips|chest dips|push-ups?)$').hasMatch(n) &&
            t != ExerciseType.bodyweight) {
          bad.add('$name: bodyweight move typed ${t.name}');
        }
      }
      expect(bad, isEmpty);
    });

    test('library definitions pick the right logging mode', () {
      ExerciseDefinition def(String name) =>
          ExerciseDefinition.fromJson(entries.firstWhere((e) => e['name'] == name));
      expect(def('Pull-ups').inferExecutionMode(), ExerciseExecutionMode.bodyweightReps);
      expect(def('Weighted Pull-up').inferExecutionMode(), ExerciseExecutionMode.weightedBodyweight);
      expect(def('Leg Press').inferExecutionMode(), ExerciseExecutionMode.weightReps);
      expect(def('Leg Press').classification.label, 'Machine');
      expect(def('Dips').toExercise().type, ExerciseType.bodyweight);
    });

    test('labels are sentence case with no dashes or dots', () {
      final labels = {
        for (final e in entries)
          ExerciseClassifier.classify(
            id: e['id'] as String,
            name: e['name'] as String,
            equipment: e['equipment'] as String?,
            muscle: e['targetMuscle'] as String?,
          ).label,
        for (final t in ExerciseType.values) ExerciseClassifier.typeLabel(t),
      };
      for (final l in labels) {
        expect(l.contains('—') || l.contains('–') || l.contains('·'), isFalse, reason: l);
        // "EZ bar" is the one proper name allowed its capitals.
        final norm = l.replaceFirst('EZ', 'Ez');
        expect(norm[0], norm[0].toUpperCase(), reason: l);
        expect(norm.substring(1), norm.substring(1).toLowerCase(), reason: l);
      }
    });
  });
}
