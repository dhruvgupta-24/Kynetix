import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/config/app_theme.dart';
import 'package:kynetix/models/workout_session.dart';
import 'package:kynetix/models/workout_split.dart';
import 'package:kynetix/services/pr_classifier.dart';
import 'package:kynetix/services/previous_set_lookup.dart';
import 'package:kynetix/services/rest_timer_notifications.dart';
import 'package:kynetix/services/rest_timer_prefs.dart';
import 'package:kynetix/services/superset_advance.dart';
import 'package:kynetix/services/warmup_calculator.dart';
import 'package:kynetix/widgets/barbell_plate_calculator.dart';
import 'package:kynetix/widgets/pr_celebration.dart';
import 'package:kynetix/ui/k_brand_intro.dart' show KShearWordmark;
import 'package:kynetix/widgets/workout_share_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

SetEntry w(double weight, int reps, [SetType t = SetType.normal]) =>
    SetEntry(weight: weight, reps: reps, setType: t);

const bench = Exercise(id: 'bench', name: 'Bench Press', muscleGroup: 'Chest', type: ExerciseType.barbellCompound);
const curl = Exercise(id: 'curl', name: 'DB Curl', muscleGroup: 'Biceps', type: ExerciseType.dumbbell);

void main() {
  group('Warm-up ramp', () {
    List<(double, int)> ramp(double working, ExerciseType type) => WarmUpCalculator.generate(
          workingWeight: working,
          type: type,
        ).map((s) => (s.weight, s.reps)).toList();

    test('barbell 100 kg: bar, 40/60/80 %', () {
      expect(ramp(100, ExerciseType.barbellCompound), [(20.0, 10), (40.0, 8), (60.0, 5), (80.0, 3)]);
    });

    test('barbell rounds to loadable 2.5 kg steps', () {
      expect(ramp(102.5, ExerciseType.barbellCompound), [(20.0, 10), (40.0, 8), (62.5, 5), (82.5, 3)]);
    });

    test('skips steps at or below the empty bar', () {
      expect(ramp(30, ExerciseType.barbellCompound), [(20.0, 10), (25.0, 3)]);
      expect(ramp(20, ExerciseType.barbellCompound), isEmpty);
      expect(ramp(15, ExerciseType.barbellCompound), isEmpty);
    });

    test('warm-ups are SetType.warmUp and never reach working weight', () {
      final steps = WarmUpCalculator.generate(workingWeight: 60, type: ExerciseType.barbellCompound);
      expect(steps.every((s) => s.weight < 60), isTrue);
      expect(steps.map((s) => s.toSetEntry().setType).toSet(), {SetType.warmUp});
      expect(steps.every((s) => !s.toSetEntry().isMainWorkingSet), isTrue);
    });

    test('dumbbells round to 2.5 kg or 2 kg racks', () {
      expect(ramp(30, ExerciseType.dumbbell), [(12.5, 8), (17.5, 5), (25.0, 3)]);
      expect(WarmUpCalculator.dumbbellIncrementFor(22), 2.0);
      expect(ramp(22, ExerciseType.dumbbell), [(8.0, 8), (14.0, 5), (18.0, 3)]);
    });

    test('bodyweight gets no ramp; light dumbbells drop sub-step sets', () {
      expect(ramp(50, ExerciseType.bodyweight), isEmpty);
      expect(ramp(4, ExerciseType.dumbbell), [(2.0, 8)]);
    });

    test('suggested working weight prefers today, then last session', () {
      expect(
        WarmUpCalculator.suggestWorkingWeight(todaySets: [w(80, 5), w(40, 8, SetType.warmUp)], lastSessionSets: [w(90, 5)]),
        80,
      );
      expect(WarmUpCalculator.suggestWorkingWeight(todaySets: const [], lastSessionSets: [w(70, 5), w(75, 3)]), 75);
      expect(WarmUpCalculator.suggestWorkingWeight(todaySets: const [], fallback: 40), 40);
      expect(WarmUpCalculator.suggestWorkingWeight(todaySets: const []), isNull);
    });

    test('plate rounding never goes below the bar', () {
      expect(BarbellPlateCalculator.roundToLoadable(41), 40);
      expect(BarbellPlateCalculator.roundToLoadable(21), 20);
      expect(BarbellPlateCalculator.roundToLoadable(10), 20);
      expect(BarbellPlateCalculator.roundToLoadable(61.5), 62.5);
    });
  });

  group('Rest timer prefs', () {
    late String? uid;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      uid = 'user-a';
      RestTimerPrefs.instance
        ..resetForTest()
        ..userIdProvider = () => uid;
    });

    test('keys are scoped by user id like WorkoutService', () {
      expect(RestTimerPrefs.keyFor('abc'), '${RestTimerPrefs.baseKey}_abc');
      expect(RestTimerPrefs.keyFor(null), RestTimerPrefs.baseKey);
      expect(RestTimerPrefs.keyFor(''), RestTimerPrefs.baseKey);
    });

    test('remembers per exercise, per user, and never leaks across accounts', () async {
      final prefs = await SharedPreferences.getInstance();
      final p = RestTimerPrefs.instance;
      await p.load(prefsOverride: prefs);
      expect(p.durationFor(bench), 90);
      expect(p.durationFor(curl), 60);

      await p.setDuration('bench', 180, prefsOverride: prefs);
      expect(p.durationFor(bench), 180);
      expect(prefs.getString('${RestTimerPrefs.baseKey}_user-a'), contains('bench'));

      uid = 'user-b';
      expect(p.durationFor(bench), 90, reason: 'stale cache must not leak to another account');
      await p.load(prefsOverride: prefs);
      expect(p.durationFor(bench), 90);

      uid = 'user-a';
      await p.load(prefsOverride: prefs);
      expect(p.durationFor(bench), 180);
    });

    test('normalize clamps to 30 s – 5 min in 15 s steps', () {
      expect(RestTimerPrefs.normalize(5), 30);
      expect(RestTimerPrefs.normalize(1000), 300);
      expect(RestTimerPrefs.normalize(100), 105);
      expect(RestTimerPrefs.normalize(90), 90);
    });

    test('no rest before a queued drop set', () {
      expect(RestTimerPrefs.shouldStartRest(nextSetType: SetType.dropSet), isFalse);
      expect(RestTimerPrefs.shouldStartRest(nextSetType: SetType.normal), isTrue);
      expect(RestTimerPrefs.shouldStartRest(nextSetType: SetType.warmUp), isTrue);
    });

    test('labels and notification line', () {
      expect(restLabel(45), '45s');
      expect(restLabel(90), '1:30');
      expect(restLabel(300), '5 min');
      expect(
        restNextLine(exerciseName: 'Bench Press', setNumber: 3, weight: 62.5, reps: 8),
        'Next: Bench Press set 3, target 62.5 kg × 8',
      );
      expect(restNextLine(exerciseName: 'Plank', setNumber: 2), 'Next: Plank set 2');
    });
  });

  group('Previous set lookup', () {
    final last = [
      w(20, 10, SetType.warmUp),
      w(60, 8),
      w(62.5, 8),
      w(40, 10, SetType.dropSet),
      w(62.5, 7),
    ];

    test('matches by type and order, not raw index', () {
      expect(PreviousSetLookup.forOrdinal(last, SetType.normal, 0)!.weight, 60);
      expect(PreviousSetLookup.forOrdinal(last, SetType.normal, 2)!.reps, 7);
      expect(PreviousSetLookup.forOrdinal(last, SetType.normal, 3), isNull);
      expect(PreviousSetLookup.forOrdinal(last, SetType.dropSet, 0)!.weight, 40);
    });

    test('next set ghost counts what is already logged today', () {
      final today = [w(20, 10, SetType.warmUp), w(60, 8)];
      final ghost = PreviousSetLookup.forNextSet(previousSets: last, todaySets: today, nextType: SetType.normal);
      expect(PreviousSetLookup.format(ghost!), '62.5 × 8');
      expect(PreviousSetLookup.forNextSet(previousSets: last, todaySets: today, nextType: SetType.warmUp), isNull);
    });

    test('logged set hint and formatting', () {
      final today = [w(60, 8), w(62.5, 8)];
      expect(PreviousSetLookup.forLoggedSet(previousSets: last, todaySets: today, indexInToday: 1)!.weight, 62.5);
      expect(PreviousSetLookup.forLoggedSet(previousSets: last, todaySets: today, indexInToday: 5), isNull);
      expect(PreviousSetLookup.format(const SetEntry(weight: 0, reps: 12, externalLoadKg: 0)), 'BW × 12');
      expect(PreviousSetLookup.format(const SetEntry(weight: 0, reps: 8, externalLoadKg: 10)), 'BW+10 × 8');
      expect(PreviousSetLookup.format(w(61.25, 5)), '61.25 × 5');
    });
  });

  group('PR classification', () {
    final history = [w(80, 5), w(70, 8), w(60, 10), w(20, 10, SetType.warmUp)];

    test('never on the first-ever log', () {
      expect(PrClassifier.classify(set: w(100, 5), history: const []).isPr, isFalse);
      // Only warm-ups before: still nothing to beat.
      expect(PrClassifier.classify(set: w(100, 5), history: [w(20, 10, SetType.warmUp)]).isPr, isFalse);
    });

    test('warm-ups and drops are never records', () {
      expect(PrClassifier.classify(set: w(200, 5, SetType.warmUp), history: history).isPr, isFalse);
      expect(PrClassifier.classify(set: w(200, 5, SetType.dropSet), history: history).isPr, isFalse);
    });

    test('e1RM record comes first', () {
      final r = PrClassifier.classify(set: w(85, 5), history: history);
      expect(r.types.first, PrType.e1rm);
      expect(r.types, contains(PrType.heaviestAtReps));
      expect(r.previousWeightAtReps, 80);
    });

    test('heaviest at a rep count without an e1RM record', () {
      // 72.5 × 8 = 91.8 e1RM < 80 × 5 = 93.3
      final r = PrClassifier.classify(set: w(72.5, 8), history: history);
      expect(r.types, [PrType.heaviestAtReps]);
    });

    test('most reps at a weight', () {
      final r = PrClassifier.classify(set: w(60, 11), history: history);
      expect(r.types, [PrType.mostRepsAtWeight]);
      expect(r.previousRepsAtWeight, 10);
    });

    test('a never-tried rep count is not a record by itself', () {
      expect(PrClassifier.classify(set: w(50, 12), history: history).isPr, isFalse);
    });

    test('earlier sets today raise the bar', () {
      final r = PrClassifier.classify(set: w(85, 5), history: history, earlierToday: [w(87.5, 5)]);
      expect(r.isPr, isFalse);
    });

    test('banner copy names the record type', () {
      final r = PrClassifier.classify(set: w(60, 11), history: history);
      final copy = prBannerCopy(r, exerciseName: 'Bench Press');
      expect(copy.title, 'Most reps you\'ve done at 60 kg');
      expect(copy.detail, contains('Up from 10 reps'));
      expect(copy.title, isNot(contains('!')));
    });
  });

  group('Superset flow', () {
    const a = Exercise(id: 'a', name: 'A', muscleGroup: 'Chest', type: ExerciseType.dumbbell, supersetGroupId: 'g');
    const b = Exercise(id: 'b', name: 'B', muscleGroup: 'Back', type: ExerciseType.dumbbell, supersetGroupId: 'g');
    Map<String, ExerciseEntry> entries(int aSets, int bSets) => {
          'a': ExerciseEntry(exercise: a, sets: List.generate(aSets, (_) => w(20, 10))),
          'b': ExerciseEntry(exercise: b, sets: List.generate(bSets, (_) => w(20, 10))),
        };

    test('A1 then straight to B1 with no rest', () {
      final step = SupersetAdvance.afterSet(logged: a, allExercises: const [a, b], entriesMap: entries(1, 0));
      expect(step.goTo?.id, 'b');
      expect(step.skipRest, isTrue);
    });

    test('B1 closes the round: back to A with rest', () {
      final step = SupersetAdvance.afterSet(logged: b, allExercises: const [a, b], entriesMap: entries(1, 1));
      expect(step.goTo?.id, 'a');
      expect(step.skipRest, isFalse);
    });

    test('finished group or no group: stay', () {
      expect(SupersetAdvance.afterSet(logged: b, allExercises: const [a, b], entriesMap: entries(3, 3)).goTo, isNull);
      expect(SupersetAdvance.afterSet(logged: bench, allExercises: const [bench], entriesMap: const {}).goTo, isNull);
    });
  });

  group('Share card data', () {
    test('top lifts by e1RM, working sets only', () {
      const squat = Exercise(id: 'sq', name: 'Squat', muscleGroup: 'Legs', type: ExerciseType.barbellCompound);
      final session = WorkoutSession(
        id: 's',
        date: DateTime(2026, 10, 17),
        splitDayName: 'Push',
        durationMinutes: 52,
        entries: [
          ExerciseEntry(exercise: bench, sets: [w(20, 10, SetType.warmUp), w(80, 5), w(75, 8)]),
          ExerciseEntry(exercise: squat, sets: [w(120, 3), w(200, 1, SetType.warmUp)]),
          ExerciseEntry(exercise: curl, sets: [w(14, 10)]),
          ExerciseEntry(exercise: const Exercise(id: 'x', name: 'X', muscleGroup: 'Core', type: ExerciseType.bodyweight), isSkipped: true),
        ],
      );
      final data = WorkoutShareData.fromSession(
        session,
        duration: const Duration(minutes: 50),
        prCount: 1,
        isPr: (id, s) => id == 'sq',
      );
      expect(data.durationMinutes, 52);
      expect(data.topLifts.map((l) => l.name).toList(), ['Squat', 'Bench Press', 'DB Curl']);
      expect(data.topLifts.first.isPr, isTrue);
      expect(data.topLifts[1].weight, 75); // 75×8 (95 e1RM) beats 80×5 (93.3)
      expect(data.muscles, ['Chest', 'Legs', 'Biceps']);
    });
  });

  group('Share card widget', () {
    final data = WorkoutShareData(
      date: DateTime(2026, 10, 17),
      dayName: 'Push day with a long name that wraps',
      durationMinutes: 64,
      totalVolume: 12450,
      sets: 21,
      prs: 2,
      topLifts: const [
        ShareLift(name: 'Barbell Bench Press', weight: 82.5, reps: 5, e1rm: 96, isPr: true),
        ShareLift(name: 'Incline Dumbbell Press', weight: 30, reps: 10, e1rm: 40),
        ShareLift(name: 'Cable Fly', weight: 15, reps: 12, e1rm: 21),
      ],
      muscles: const ['Chest', 'Shoulders', 'Triceps'],
    );

    for (final palette in [KPalette.dark, KPalette.light]) {
      testWidgets('renders without overflow (${palette.isDark ? 'Carbon' : 'Paper'})', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Center(child: WorkoutShareCard(data: data, palette: palette)),
        ));
        expect(tester.takeException(), isNull);
        expect(find.byType(KShearWordmark), findsOneWidget);
        expect(find.textContaining('12,450', findRichText: true), findsOneWidget);
        expect(find.text('82.5 × 5'), findsOneWidget);
        expect(tester.getSize(find.byType(WorkoutShareCard)), kShareCardSize);
      });
    }

    testWidgets('PR burst renders nothing under reduced motion', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(textDirection: TextDirection.ltr, child: PrBurst(color: Color(0xFF8E7DFF))),
      ));
      expect(find.byType(CustomPaint), findsNothing);
    });
  });
}
