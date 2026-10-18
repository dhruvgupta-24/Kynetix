import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/data/form_cues.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/widgets/muscle_body_map.dart';
import 'package:kynetix/widgets/muscle_regions.dart';

void main() {
  const front = BodyView.front;
  const back = BodyView.back;

  // The table the Train tab relies on: label to (side, lit regions).
  final expected = <String, MuscleTarget?>{
    // Library muscle groups (assets/data/exercises_library.json).
    'Chest': const MuscleTarget(front, {'chest'}),
    'Abs': const MuscleTarget(front, {'abs'}),
    'Biceps': const MuscleTarget(front, {'biceps'}),
    'Shoulders': const MuscleTarget(front, {'deltoids'}),
    'Triceps': const MuscleTarget(back, {'triceps'}),
    'Glutes': const MuscleTarget(back, {'gluteal'}),
    'Upper Back': const MuscleTarget(back, {'upper-back'}),
    'Lats': const MuscleTarget(back, {'upper-back'}),
    'Calves': const MuscleTarget(back, {'calves'}),
    'Quads': const MuscleTarget(front, {'quadriceps'}),
    'Forearms': const MuscleTarget(front, {'forearm'}),
    'Hamstrings': const MuscleTarget(back, {'hamstring'}),
    'Lower Back': const MuscleTarget(back, {'lower-back'}),
    'Traps': const MuscleTarget(back, {'trapezius'}),
    'Adductors': const MuscleTarget(front, {'adductors'}),
    'Serratus': const MuscleTarget(front, {'serratus'}),
    'Abductors': const MuscleTarget(back, {'gluteal'}),
    'Neck': null,
    'Cardio': null,
    // Split and setup-screen groups.
    'Back': const MuscleTarget(back, {'upper-back'}),
    'Rear Delts': const MuscleTarget(back, {'deltoids'}),
    'Core': const MuscleTarget(front, {'abs', 'obliques'}),
    'Strength': null,
    'Other': null,
    'General': null,
    'Full body': null,
    // Library categories and body parts.
    'Arms': const MuscleTarget(front, {'biceps', 'triceps', 'forearm'}),
    'Legs': const MuscleTarget(front, {'quadriceps', 'adductors'}),
    'Upper Arms': const MuscleTarget(front, {'biceps', 'triceps'}),
    'Lower Arms': const MuscleTarget(front, {'forearm'}),
    'Upper Legs': const MuscleTarget(front, {'quadriceps', 'adductors'}),
    'Lower Legs': const MuscleTarget(back, {'calves'}),
    'Waist': const MuscleTarget(front, {'abs', 'obliques'}),
    // Common variants.
    'Front Delts': const MuscleTarget(front, {'deltoids'}),
    'Side delts': const MuscleTarget(front, {'deltoids'}),
    'Obliques': const MuscleTarget(front, {'obliques'}),
    'Hip Flexors': const MuscleTarget(front, {'hip-flexors'}),
    // Raw region ids pass through to themselves.
    'upper-back': const MuscleTarget(back, {'upper-back'}),
    'lower-back': const MuscleTarget(back, {'lower-back'}),
    'gluteal': const MuscleTarget(back, {'gluteal'}),
    'quadriceps': const MuscleTarget(front, {'quadriceps'}),
    'trapezius': const MuscleTarget(back, {'trapezius'}),
    'tibialis': const MuscleTarget(front, {'tibialis'}),
  };

  group('muscleTargetFor', () {
    expected.forEach((label, target) {
      test('"$label" maps to $target', () {
        expect(muscleTargetFor(label), target);
      });
    });

    test('is case and whitespace insensitive', () {
      expect(muscleTargetFor('  rear DELTS '), const MuscleTarget(back, {'deltoids'}));
      expect(muscleTargetFor(''), isNull);
    });

    test('every region exists on the view it is shown on', () {
      final geometry = jsonDecode(File('assets/data/body_paths.json').readAsStringSync()) as Map<String, dynamic>;
      Set<String> partsOf(String v) => ((geometry[v] as Map)['paths'] as Map).keys.cast<String>().toSet();
      final frontParts = partsOf('front');
      final backParts = partsOf('back');
      expect(frontParts.containsAll(kFrontRegions), isTrue);
      expect(backParts.containsAll(kBackRegions), isTrue);
      for (final t in expected.values.whereType<MuscleTarget>()) {
        final parts = t.view == front ? frontParts : backParts;
        expect(parts.containsAll(t.regions), isTrue, reason: '$t');
      }
    });

    test('every library muscle group resolves to a region or to text only', () {
      final lib = jsonDecode(File('assets/data/exercises_library.json').readAsStringSync()) as List<dynamic>;
      final groups = <String>{};
      for (final e in lib) {
        final m = e as Map<String, dynamic>;
        for (final k in ['muscleGroup', 'targetMuscle', 'category', 'bodyPart']) {
          final v = m[k] as String? ?? '';
          if (v.isNotEmpty) groups.add(v);
        }
      }
      const textOnly = {'Cardio', 'Neck'};
      for (final g in groups) {
        if (textOnly.contains(g)) {
          expect(muscleTargetFor(g), isNull, reason: g);
        } else {
          expect(muscleTargetFor(g), isNotNull, reason: 'library group "$g" has no region');
        }
      }
    });

    test('every muscle group in the default split maps as in the table', () {
      final groups = {
        for (final d in developersChoiceSplit.days)
          for (final e in d.exercises) e.muscleGroup,
      };
      expect(groups, isNotEmpty);
      for (final g in groups) {
        expect(expected.containsKey(g), isTrue, reason: 'add "$g" to the table');
        expect(muscleTargetFor(g), expected[g], reason: g);
      }
    });
  });

  group('MuscleThumb', () {
    setUpAll(() {
      MuscleBodyMap.setCachedGeometryForTesting({
        'front': {
          'viewBox': '0 0 100 100',
          'paths': {'chest': 'M 10 10 L 50 10 L 50 50 L 10 50 Z'},
        },
        'back': {
          'viewBox': '0 0 100 100',
          'paths': {'upper-back': 'M 10 10 L 50 10 L 50 50 L 10 50 Z'},
        },
      });
    });

    testWidgets('paints for a mapped group, nothing for cardio', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            MuscleThumb('Lats', key: Key('lats')),
            MuscleThumb('Cardio', key: Key('cardio')),
          ]),
        ),
      ));
      // Drawn once into a cached image; the slot is reserved either way.
      expect(tester.getSize(find.byKey(const Key('lats'))).height, greaterThan(0));
      expect(tester.getSize(find.byKey(const Key('cardio'))), Size.zero);
      expect(MuscleThumb.canShow('Cardio'), isFalse);
      expect(MuscleThumb.canShow('Adductors'), isTrue);
    });
  });

  group('formCueFor', () {
    test('gives one short, specific line for common lifts', () {
      expect(formCueFor('Barbell Bench Press'), contains('drive the floor away'));
      expect(formCueFor('Incline Dumbbell Press'), contains('30 degrees'));
      expect(formCueFor('Incline Dumbbell Curl'), contains('Elbows pinned'));
      expect(formCueFor('Lat Pulldown'), contains('Lead with the elbows'));
      expect(formCueFor('Seated Cable Row'), contains('Pull to the hip'));
      expect(formCueFor('Romanian Deadlift'), contains('Hips back'));
      expect(formCueFor('Leg Curl'), contains('Heels to the glutes'));
    });

    test('stays silent rather than generic', () {
      expect(formCueFor('Rowing Machine'), isNull);
      expect(formCueFor('Medicine Ball Throw'), isNull);
      expect(formCueFor('Mystery Move'), isNull);
      expect(formCueFor(''), isNull);
    });

    test('copy is short, plain and free of em dashes and arrows', () {
      for (final c in allFormCues) {
        expect(c.length, lessThanOrEqualTo(80), reason: c);
        expect(c.contains('—'), isFalse, reason: c);
        expect(c.contains('→'), isFalse, reason: c);
        expect(RegExp(r'[A-Z]{3,}').hasMatch(c), isFalse, reason: c);
      }
    });
  });
}
