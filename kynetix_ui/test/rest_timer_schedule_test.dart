import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/rest_timer_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// The "Rest over" alarm decisions (exact vs inexact, never blocking, no
/// double alert).
void main() {
  final now = DateTime(2026, 10, 17, 18, 30, 0);

  group('plan', () {
    test('exact when the exact-alarm permission is granted', () {
      expect(
        RestOverSchedule.plan(endsAt: now.add(const Duration(seconds: 90)), now: now, exactAllowed: true),
        RestOverDelivery.exact,
      );
    });

    test('inexact when it is denied or unknown (never asked for)', () {
      for (final allowed in [false, null]) {
        expect(
          RestOverSchedule.plan(endsAt: now.add(const Duration(seconds: 90)), now: now, exactAllowed: allowed),
          RestOverDelivery.inexact,
        );
      }
    });

    test('nothing for a rest that is over or about to be', () {
      for (final lead in [const Duration(seconds: -5), Duration.zero, const Duration(milliseconds: 999)]) {
        expect(
          RestOverSchedule.plan(endsAt: now.add(lead), now: now, exactAllowed: true),
          RestOverDelivery.none,
        );
      }
      expect(
        RestOverSchedule.plan(endsAt: now.add(const Duration(seconds: 1)), now: now, exactAllowed: true),
        RestOverDelivery.exact,
      );
    });
  });

  test('schedule modes: exactAllowWhileIdle / inexactAllowWhileIdle', () {
    expect(RestOverSchedule.modeFor(RestOverDelivery.exact), AndroidScheduleMode.exactAllowWhileIdle);
    expect(RestOverSchedule.modeFor(RestOverDelivery.inexact), AndroidScheduleMode.inexactAllowWhileIdle);
    expect(RestOverSchedule.modeFor(RestOverDelivery.none), isNull);
  });

  group('fireAt', () {
    test('is the same instant in UTC, rounded up to the whole second', () {
      final endsAt = DateTime.utc(2026, 10, 17, 13, 0, 5, 250);
      final at = RestOverSchedule.fireAt(endsAt);
      expect(at.location, tz.UTC);
      expect(at.millisecondsSinceEpoch, DateTime.utc(2026, 10, 17, 13, 0, 6).millisecondsSinceEpoch);
      expect(at.isBefore(endsAt), isFalse); // never early
    });

    test('a whole-second end time is kept', () {
      final endsAt = DateTime.utc(2026, 10, 17, 13, 0, 5);
      expect(RestOverSchedule.fireAt(endsAt).millisecondsSinceEpoch, endsAt.millisecondsSinceEpoch);
    });

    test('a local end time maps to the same instant', () {
      final local = DateTime(2026, 10, 17, 18, 30, 45);
      expect(RestOverSchedule.fireAt(local).millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    });
  });

  test('the in-app timer posts the alert unless an exact alarm covers it', () {
    expect(RestOverSchedule.showOnTimer(RestOverDelivery.exact), isFalse);
    expect(RestOverSchedule.showOnTimer(RestOverDelivery.inexact), isTrue);
    expect(RestOverSchedule.showOnTimer(RestOverDelivery.none), isTrue);
  });

  test('outside Android (tests) every call is a safe no-op', () async {
    final n = RestTimerNotifications.instance;
    expect(
      await n.scheduleRestOver(endsAt: DateTime.now().add(const Duration(minutes: 1)), nextLine: 'Next'),
      RestOverDelivery.none,
    );
    await n.cancelPending();
    await n.cancelAll();
  });
}
