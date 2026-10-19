import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/widgets/workout_share_card.dart';

void main() {
  final data = WorkoutShareData(
    date: DateTime(2026, 10, 19, 18, 42),
    dayName: 'Push day with a long name that wraps',
    durationMinutes: 64,
    totalVolume: 12450,
    sets: 21,
    prs: 2,
    topLifts: const [
      ShareLift(name: 'Barbell Bench Press', weight: 82.5, reps: 5, e1rm: 96, isPr: true),
      ShareLift(name: 'Weighted Dips', weight: 15, reps: 8, e1rm: 19, bodyweight: true),
    ],
    muscles: const ['Chest', 'Triceps'],
    exercises: const [
      ShareExercise(name: 'Barbell Bench Press', sets: [
        ShareSet(load: 40, reps: 10, warmUp: true),
        ShareSet(load: 82.5, reps: 5, isPr: true),
        ShareSet(load: 60, reps: 12, drop: true),
      ]),
      ShareExercise(name: 'Weighted Dips', sets: [
        ShareSet(load: 0, reps: 12, bodyweight: true),
        ShareSet(load: 15, reps: 8, bodyweight: true),
      ]),
    ],
  );

  group('Share templates', () {
    for (final t in ShareTemplate.values) {
      for (final f in ShareFormat.values) {
        for (final b in ShareBackdrop.values) {
          testWidgets('${t.name} ${f.name} ${b.name} renders at its size', (tester) async {
            tester.view.physicalSize = const Size(1000, 1400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(MaterialApp(
              home: Center(child: ShareCanvas(data: data, template: t, format: f, backdrop: b)),
            ));
            expect(tester.takeException(), isNull);
            expect(tester.getSize(find.byType(ShareCanvas)), f.size);
          });
        }
      }
    }
  });

  testWidgets('share sheet swipes templates and switches format', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => showWorkoutShareSheet(context, data), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Poster'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Receipt'), findsOneWidget);
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareCanvas), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('Share data', () {
    test('exercise volume skips warm-ups, keeps drops', () {
      final e = data.exercises.first;
      expect(e.volume, 82.5 * 5 + 60 * 12);
      expect(e.workingSets, 1);
      expect(e.hasPr, isTrue);
      expect(data.totalReps, 5 + 12 + 12 + 8);
    });

    test('exercisesOf groups sets and marks warm-ups, bodyweight and records', () {
      const bench = Exercise(id: 'b', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound);
      SetEntry w(double kg, int r, [SetType t = SetType.normal]) => SetEntry(weight: kg, reps: r, setType: t);
      final session = WorkoutSession(
        id: 's',
        date: DateTime(2026, 10, 19),
        splitDayName: 'Push',
        entries: [
          ExerciseEntry(exercise: bench, sets: [w(20, 10, SetType.warmUp), w(80, 5), w(75, 8)]),
          ExerciseEntry(exercise: const Exercise(id: 'x', name: 'X', muscleGroup: 'Core', type: ExerciseType.bodyweight), isSkipped: true),
        ],
      );
      final ex = WorkoutShareData.exercisesOf(session, isPr: (id, s) => s.weight == 80);
      expect(ex, hasLength(1));
      expect(ex.single.sets.map((s) => s.warmUp).toList(), [true, false, false]);
      expect(ex.single.sets.map((s) => s.isPr).toList(), [false, true, false]);
      expect(ex.single.volume, 80 * 5 + 75 * 8);
    });

    test('equivalent lands between 3 and 40 and is stable for a date', () {
      final d = DateTime(2026, 10, 19);
      for (final v in [120.0, 900.0, 5000.0, 12450.0, 40000.0]) {
        final p = ShareEquivalent.pick(v, d)!;
        expect(p.$2, inInclusiveRange(3, 40), reason: '$v');
        expect(ShareEquivalent.pick(v, d)!.$1, same(p.$1));
      }
      expect(ShareEquivalent.pick(50, d), isNull);
    });
  });
}
