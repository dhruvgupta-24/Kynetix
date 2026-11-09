import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/screens/onboarding/plan_builder_moment.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';

const _plan = WeeklyTargetPlan(
  maintenanceCalories: 2540,
  avgDailyCalories: 2740,
  avgDailyProtein: 130,
  trainingDayCalories: 2820,
  restDayCalories: 2620,
  trainingDayProtein: 137,
  restDayProtein: 122,
  healthConnectActive: false,
  fiberTargetG: 38,
);

PlanBuildInputs _inputs({
  Goal goal = kLeanBulk,
  bool teen = false,
  PortionAnchor? anchor = PortionAnchor.carbAnchored,
  WeeklyTargetPlan plan = _plan,
}) =>
    PlanBuildInputs(
      plan: plan,
      heightCm: 175,
      weightKg: 72,
      age: teen ? 16 : 24,
      trainingDaysLabel: '4 to 5 days',
      goal: goal,
      teen: teen,
      portionAnchor: anchor,
    );

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced, size: const Size(400, 900)),
        child: Scaffold(body: child),
      ),
    );

const _goals = [kFatLoss, kMaintenance, kLeanBulk, kBulk, kRecomposition];

String _copyOf(List<PlanLine> lines) =>
    lines.map((l) => '${l.label} ${l.detail} ${l.why} ${l.valueText}').join('\n');

void main() {
  group('the sheet copy', () {
    test('is the real plan: burn, goal change, split, protein', () {
      final lines = planLines(_inputs());
      expect(lines.map((l) => l.label), [
        'What you burn',
        'Lean bulk',
        'Training days',
        'Rest days',
        'Protein',
        'Your plates',
      ]);
      expect(lines[0].valueText, '2,540');
      expect(lines[0].detail, '175 cm, 72 kg, age 24, training 4 to 5 days');
      expect(lines[1].valueText, '+200');
      expect(lines[2].valueText, '2,820');
      expect(lines[3].valueText, '2,620');
      expect(lines[3].why, contains('200 kcal more'));
      expect(lines[3].why, contains('2,740 kcal a day'));
      expect(lines[4].valueText, '130');
      expect(lines[4].detail, 'About 1.8 g per kg of body weight');
      expect(lines[5].detail, 'Roti or rice first');
    });

    test('a cut shows the change as a minus, maintenance as 0', () {
      const cut = WeeklyTargetPlan(
        maintenanceCalories: 2540,
        avgDailyCalories: 2040,
        avgDailyProtein: 151,
        trainingDayCalories: 2140,
        restDayCalories: 1940,
        trainingDayProtein: 158,
        restDayProtein: 144,
        healthConnectActive: false,
        fiberTargetG: 29,
      );
      expect(planLines(_inputs(goal: kFatLoss, plan: cut))[1].valueText, '-500');
      const hold = WeeklyTargetPlan(
        maintenanceCalories: 2540,
        avgDailyCalories: 2540,
        avgDailyProtein: 130,
        trainingDayCalories: 2640,
        restDayCalories: 2440,
        trainingDayProtein: 137,
        restDayProtein: 122,
        healthConnectActive: false,
        fiberTargetG: 36,
      );
      expect(planLines(_inputs(goal: kMaintenance, plan: hold))[1].valueText, '0');
    });

    test('teen mode never talks about deficits, cutting or fat loss', () {
      final banned = RegExp(r'deficit|fat loss|\bcut\b|cutting|lose|losing|diet', caseSensitive: false);
      for (final g in _goals) {
        for (final a in [null, ...PortionAnchor.values]) {
          final copy = _copyOf(planLines(_inputs(goal: g, teen: true, anchor: a)));
          expect(banned.hasMatch(copy), isFalse, reason: '$g: $copy');
        }
      }
    });

    test('no em or en dashes anywhere, adult or teen', () {
      for (final g in _goals) {
        for (final teen in [false, true]) {
          for (final a in [null, ...PortionAnchor.values]) {
            final copy = _copyOf(planLines(_inputs(goal: g, teen: teen, anchor: a)));
            expect(copy.contains('—') || copy.contains('–'), isFalse, reason: copy);
          }
        }
      }
    });

    test('a skipped eating style is honest about it', () {
      final plates = planLines(_inputs(anchor: null)).last;
      expect(plates.detail, 'Not set yet');
      expect(plates.valueText, 'Later');
    });
  });

  group('the moment', () {
    testWidgets('builds line by line, then settles on the real targets', (tester) async {
      var settled = 0;
      await tester.pumpWidget(_host(PlanBuilderMoment(
        inputs: _inputs(),
        play: true,
        onSettled: () => settled++,
      )));
      expect(find.text('Working it out from your answers'), findsOneWidget);
      expect(settled, 0);

      // Part way: the first lines are written, the sheet is not settled.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('Your daily target'), findsNothing);

      await tester.pump(PlanBuilderMoment.total);
      await tester.pumpAndSettle();
      expect(find.text('Your daily target'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Your daily target: 2,740 kcal and 130 g protein')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Protein, About 1\.8 g per kg of body weight, 130 g')), findsOneWidget);
      expect(settled, 1);
    });

    testWidgets('a tap skips straight to the settled sheet', (tester) async {
      var settled = 0;
      await tester.pumpWidget(_host(PlanBuilderMoment(
        inputs: _inputs(),
        play: true,
        onSettled: () => settled++,
      )));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(PlanBuilderMoment));
      await tester.pump();
      await tester.pump();
      expect(find.text('Your daily target'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Your daily target: 2,740 kcal')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Rest days, .*2,620 kcal')), findsOneWidget);
      expect(settled, 1);
      await tester.pumpAndSettle();
      expect(settled, 1);
    });

    testWidgets('reduced motion shows the settled sheet at once', (tester) async {
      var settled = 0;
      await tester.pumpWidget(_host(
        PlanBuilderMoment(inputs: _inputs(), play: true, onSettled: () => settled++),
        reduced: true,
      ));
      await tester.pump();
      expect(find.text('Your daily target'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Your daily target: 2,740 kcal and 130 g protein')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Training days, .*2,820 kcal')), findsOneWidget);
      expect(settled, 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a return visit with the same answers does not replay', (tester) async {
      await tester.pumpWidget(_host(PlanBuilderMoment(inputs: _inputs(), play: false)));
      await tester.pump();
      expect(find.text('Your daily target'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('settled lines open to show how they were worked out', (tester) async {
      await tester.pumpWidget(_host(PlanBuilderMoment(inputs: _inputs(), play: false)));
      await tester.pump();
      final why = planLines(_inputs())[4].why;
      expect(find.text(why), findsNothing);
      await tester.tap(find.text('Protein'));
      await tester.pumpAndSettle();
      expect(find.text(why), findsOneWidget);
      await tester.tap(find.text('Protein'));
      await tester.pumpAndSettle();
      expect(find.text(why), findsNothing);
    });

    testWidgets('large text still lays out without overflow', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(1.6)),
          child: Scaffold(body: PlanBuilderMoment(inputs: _inputs(), play: false)),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
