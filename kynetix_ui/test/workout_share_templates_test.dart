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

  testWidgets('receipt renders without overflow for an 8-exercise session in story and post formats', (tester) async {
    final sessionData = WorkoutShareData(
      date: DateTime(2026, 10, 27, 18, 26),
      dayName: 'Chest + Triceps',
      durationMinutes: 96,
      totalVolume: 10560,
      sets: 26,
      prs: 1,
      topLifts: const [
        ShareLift(name: 'Flat Bench Press', weight: 70, reps: 10, e1rm: 93),
        ShareLift(name: 'Pec Dec', weight: 60, reps: 11, e1rm: 82),
        ShareLift(name: 'Tricep Pushdown', weight: 45, reps: 12, e1rm: 63),
      ],
      muscles: const ['Chest', 'Triceps'],
      exercises: const [
        ShareExercise(name: 'Flat Bench Press', sets: [ShareSet(load: 70, reps: 10), ShareSet(load: 70, reps: 6), ShareSet(load: 70, reps: 7)]),
        ShareExercise(name: 'Incline DB Press', sets: [ShareSet(load: 25, reps: 12), ShareSet(load: 25, reps: 8), ShareSet(load: 25, reps: 7)]),
        ShareExercise(name: 'Cable Chest Fly', sets: [ShareSet(load: 30, reps: 11), ShareSet(load: 30, reps: 10)]),
        ShareExercise(name: 'Pec Dec', sets: [ShareSet(load: 60, reps: 11), ShareSet(load: 60, reps: 10)]),
        ShareExercise(name: 'Tricep Pushdown', sets: [ShareSet(load: 45, reps: 11), ShareSet(load: 45, reps: 12)]),
        ShareExercise(name: 'Overhead Tricep Extension', sets: [ShareSet(load: 45, reps: 10), ShareSet(load: 45, reps: 6), ShareSet(load: 45, reps: 9, isPr: true)]),
        ShareExercise(name: 'Captains Chair Straight Leg Raise', sets: [ShareSet(load: 0, reps: 12, bodyweight: true), ShareSet(load: 0, reps: 10, bodyweight: true)]),
        ShareExercise(name: 'Dips', sets: [ShareSet(load: 0, reps: 10, bodyweight: true)]),
      ],
    );

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final f in ShareFormat.values) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: ShareCanvas(
            data: sessionData,
            template: ShareTemplate.receipt,
            format: f,
            backdrop: ShareBackdrop.graphite,
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'failed on format ${f.name}');
    }
  });

  testWidgets('receipt and skyline print every exercise, never "+ N MORE"', (tester) async {
    final many = WorkoutShareData(
      date: DateTime(2026, 11, 2, 12, 48),
      dayName: 'Push',
      durationMinutes: 102,
      totalVolume: 8705,
      sets: 30,
      prs: 1,
      topLifts: const [],
      muscles: const ['Chest'],
      exercises: [
        for (var i = 1; i <= 12; i++)
          ShareExercise(name: 'Cable Pushdown With Rope Attachment $i', sets: const [ShareSet(load: 50, reps: 12), ShareSet(load: 50, reps: 10)]),
      ],
    );
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final t in [ShareTemplate.receipt, ShareTemplate.skyline]) {
      for (final f in ShareFormat.values) {
        await tester.pumpWidget(MaterialApp(
          home: Center(child: ShareCanvas(data: many, template: t, format: f)),
        ));
        expect(tester.takeException(), isNull, reason: '${t.name} ${f.name}');
        expect(find.textContaining('MORE'), findsNothing, reason: '${t.name} ${f.name}');
        expect(find.textContaining('ATTACHMENT 12', findRichText: true), findsOneWidget, reason: '${t.name} ${f.name}');
      }
    }
  });

  testWidgets('receipt scales down gracefully even with extreme font scaling', (tester) async {
    final sessionData = WorkoutShareData(
      date: DateTime(2026, 10, 27, 18, 26),
      dayName: 'Chest + Triceps',
      durationMinutes: 96,
      totalVolume: 10560,
      sets: 26,
      prs: 1,
      topLifts: const [
        ShareLift(name: 'Flat Bench Press', weight: 70, reps: 10, e1rm: 93),
      ],
      muscles: const ['Chest', 'Triceps'],
      exercises: List.generate(
        12,
        (i) => ShareExercise(name: 'Exercise $i', sets: [ShareSet(load: 50, reps: 10)]),
      ),
    );

    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: Center(
          child: ShareCanvas(
            data: sessionData,
            template: ShareTemplate.receipt,
            format: ShareFormat.story,
            backdrop: ShareBackdrop.graphite,
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
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

    test('receipt load is the heaviest working set', () {
      const lifts = ShareExercise(name: 'Squat', sets: [
        ShareSet(load: 140, reps: 3, warmUp: true),
        ShareSet(load: 100, reps: 8),
        ShareSet(load: 112.5, reps: 5),
        ShareSet(load: 80, reps: 12, drop: true),
      ]);
      expect(lifts.topLoad, '112.5 KG');
      const dips = ShareExercise(name: 'Dip', sets: [ShareSet(load: 0, reps: 12, bodyweight: true)]);
      expect(dips.topLoad, 'BW');
      const weighted = ShareExercise(name: 'Dip', sets: [ShareSet(load: 10, reps: 8, bodyweight: true)]);
      expect(weighted.topLoad, 'BW+10');
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
