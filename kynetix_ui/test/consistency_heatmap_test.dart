import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/day_status.dart';
import 'package:kynetix/widgets/consistency_heatmap.dart';

void main() {
  group('ConsistencyScene', () {
    test('lays out 16 Monday-first weeks ending in the current week', () {
      final today = DateTime(2026, 10, 21); // a Wednesday
      final scene = ConsistencyScene.build(today, (_) => DayMark.none);
      expect(scene.start, DateTime(2026, 7, 6));
      expect(scene.start.weekday, DateTime.monday);
      expect(scene.todayCol, 15);
      expect(scene.todayRow, 2);
      expect(scene.dayAt(15, 2), today);
      // Thursday to Sunday of this week are still to come.
      for (var r = 3; r < 7; r++) {
        expect(scene.markAt(15, r), isNull);
      }
      expect(scene.markAt(15, 2), DayMark.none);
      expect(scene.summary, '0 days logged in the last 16 weeks');
    });

    test('counts logged days and a streak that waits for an open today', () {
      final today = DateTime(2026, 10, 21);
      DayMark markOf(DateTime d) {
        final ago = DateTime.utc(2026, 10, 21).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
        if (ago == 1) return DayMark.completed;
        if (ago == 2) return DayMark.logged;
        if (ago == 5) return DayMark.logged;
        return DayMark.none;
      }

      final scene = ConsistencyScene.build(today, markOf);
      expect(scene.loggedDays, 3);
      expect(scene.streak, 2);
      expect(scene.summary, '3 days logged in the last 16 weeks · 2 day streak');
    });

    test('day maths survives a daylight saving change inside the window', () {
      final today = DateTime(2026, 11, 4);
      final scene = ConsistencyScene.build(today, (_) => DayMark.logged);
      expect(scene.todayCol, 15);
      expect(scene.dayAt(scene.todayCol, scene.todayRow), today);
      expect(scene.streak, scene.loggedDays);
    });
  });

  group('ConsistencyGeometry', () {
    test('a tap anywhere on a square (or its trailing gap) resolves to that square', () {
      const geo = ConsistencyGeometry(origin: Offset(14, 16), cell: 12, gap: 3);
      for (final (c, r) in const [(0, 0), (7, 3), (15, 6)]) {
        final rect = geo.rectFor(c, r);
        expect(geo.cellAt(rect.center), (c, r));
        expect(geo.cellAt(rect.topLeft), (c, r));
        expect(geo.cellAt(rect.bottomRight - const Offset(0.1, 0.1)), (c, r));
      }
      expect(geo.cellAt(const Offset(2, 40)), isNull); // weekday labels
      expect(geo.cellAt(const Offset(40, 2)), isNull); // month labels
      expect(geo.cellAt(geo.origin + Offset(geo.gridSize.width + 5, 5)), isNull);
    });
  });

  group('ConsistencyHeatmap', () {
    testWidgets('fills in once with a short stagger and exposes a summary', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: ConsistencyHeatmap(avgTarget: 2000))),
      ));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel(RegExp('^Consistency, .*logged in the last 16 weeks')), findsOneWidget);
      // Nothing ticks while idle.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Padding(padding: EdgeInsets.all(16), child: ConsistencyHeatmap(avgTarget: 2100))),
      ));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
