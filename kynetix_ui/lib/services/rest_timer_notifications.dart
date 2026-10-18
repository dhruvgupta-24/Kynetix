import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'rest_timer_prefs.dart';

/// How the background "Rest over" alert is armed for the current rest.
enum RestOverDelivery {
  /// An exact alarm (SCHEDULE_EXACT_ALARM granted) fires it at the end time
  /// even if Android froze the app; the in-app timer must not post a second.
  exact,

  /// Scheduled inexactly (no exact-alarm permission): may arrive late, so the
  /// in-app timer still posts it on time when it can (and cancels this one).
  inexact,

  /// Nothing scheduled (rest already over, or scheduling failed).
  none,
}

/// The pure scheduling decisions, kept apart from the plugin for testing.
class RestOverSchedule {
  RestOverSchedule._();

  /// Rests ending sooner than this are left to the in-app timer.
  static const Duration minLead = Duration(seconds: 1);

  /// What to arm for a rest ending at [endsAt]. [exactAllowed] is the
  /// result of `canScheduleExactNotifications()` (null = unknown / failed,
  /// treated as not granted; never asked for, never blocking).
  static RestOverDelivery plan({
    required DateTime endsAt,
    required DateTime now,
    required bool? exactAllowed,
  }) {
    if (endsAt.difference(now) < minLead) return RestOverDelivery.none;
    return exactAllowed == true ? RestOverDelivery.exact : RestOverDelivery.inexact;
  }

  /// The plugin schedule mode for [delivery] (null for none).
  static AndroidScheduleMode? modeFor(RestOverDelivery delivery) => switch (delivery) {
        RestOverDelivery.exact => AndroidScheduleMode.exactAllowWhileIdle,
        RestOverDelivery.inexact => AndroidScheduleMode.inexactAllowWhileIdle,
        RestOverDelivery.none => null,
      };

  /// The alarm time: [endsAt] rounded up to the whole second (the plugin
  /// drops sub-seconds, which would otherwise fire up to 1 s early), in UTC.
  static tz.TZDateTime fireAt(DateTime endsAt) {
    final ms = endsAt.toUtc().millisecondsSinceEpoch;
    final ceil = ((ms + 999) ~/ 1000) * 1000;
    return tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, ceil);
  }

  /// When the in-app timer reaches zero in the background: post the alert
  /// now unless an exact alarm already covers it (no double alert).
  static bool showOnTimer(RestOverDelivery armed) => armed != RestOverDelivery.exact;
}

/// Android notifications for the rest timer.
///
/// * While resting with the app in the background: one silent, ongoing
///   notification whose chronometer counts down to the end of rest. Android
///   draws the countdown itself, so no background isolate or per-second
///   update is needed; `timeoutAfter` removes it at zero.
/// * When rest ends with the app in the background: a "Rest over" alert
///   naming the next set. It is armed with the alarm manager when the app is
///   backgrounded ([scheduleRestOver]), so it still fires if Android freezes
///   the app; exact when SCHEDULE_EXACT_ALARM is granted, else inexact with
///   the in-app timer posting it on time whenever it still runs.
///
/// Every call is best-effort: a denied permission, a missing plugin (tests,
/// iOS, desktop) or any platform error is swallowed. The workout never waits
/// on, or breaks because of, a notification.
class RestTimerNotifications {
  RestTimerNotifications._();
  static final RestTimerNotifications instance = RestTimerNotifications._();

  static const int _countdownId = 7401;
  static const int _overId = 7402;
  static const int _overScheduledId = 7403;
  static const String _countdownChannel = 'kynetix_rest_countdown';
  static const String _overChannel = 'kynetix_rest_over';
  // Train violet (Carbon). Notification chrome is drawn by the OS, outside
  // the app theme, so a fixed brand tint is right here.
  static const Color _accent = Color(0xFF8E7DFF);

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _initFailed = false;
  RestOverDelivery _armed = RestOverDelivery.none;

  static final bool _supported = () {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }();

  Future<bool> _ensureInit() async {
    if (!_supported || _initFailed) return false;
    if (_initialized) return true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_rest'),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[REST_NOTIF] init failed: $e');
      _initFailed = true;
    }
    return _initialized;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for POST_NOTIFICATIONS (Android 13+) once per user, at the first
  /// rest timer. Never blocks the caller's flow; a denial is final until the
  /// user changes it in system settings.
  Future<void> requestPermissionOnce() async {
    if (!await _ensureInit()) return;
    final prefs = RestTimerPrefs.instance;
    if (prefs.notificationAsked) return;
    try {
      await prefs.markNotificationAsked();
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[REST_NOTIF] permission request failed: $e');
    }
  }

  /// Shows the ongoing countdown that ends at [endsAt].
  Future<void> showCountdown({required DateTime endsAt, required String nextLine}) async {
    if (!await _ensureInit()) return;
    final remainingMs = endsAt.difference(DateTime.now()).inMilliseconds;
    if (remainingMs <= 0) return;
    try {
      await _plugin.show(
        id: _countdownId,
        title: 'Resting',
        body: nextLine,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _countdownChannel,
            'Rest countdown',
            channelDescription: 'Shows the time left on your rest between sets.',
            icon: 'ic_stat_rest',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            when: endsAt.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: true,
            timeoutAfter: remainingMs,
            category: AndroidNotificationCategory.stopwatch,
            visibility: NotificationVisibility.public,
            color: _accent,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[REST_NOTIF] countdown failed: $e');
    }
  }

  NotificationDetails get _restOverDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          _overChannel,
          'Rest over',
          channelDescription: 'Tells you when your rest between sets is up.',
          icon: 'ic_stat_rest',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 220, 120, 220, 120, 380]),
          autoCancel: true,
          timeoutAfter: 2 * 60 * 1000,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          color: _accent,
        ),
      );

  /// Arms the "Rest over" alert for [endsAt] with the system alarm manager,
  /// so it arrives on time even when Android freezes the backgrounded app.
  /// Exact (exactAllowWhileIdle) when the exact-alarm permission is granted,
  /// inexact otherwise; never asks for the permission. Replaces any earlier
  /// one. Returns what was armed.
  Future<RestOverDelivery> scheduleRestOver({
    required DateTime endsAt,
    required String nextLine,
  }) async {
    if (!await _ensureInit()) return RestOverDelivery.none;
    bool? exactAllowed;
    try {
      exactAllowed = await _android?.canScheduleExactNotifications();
    } catch (_) {}
    var delivery = RestOverSchedule.plan(
      endsAt: endsAt,
      now: DateTime.now(),
      exactAllowed: exactAllowed,
    );
    _armed = RestOverDelivery.none;
    while (delivery != RestOverDelivery.none) {
      try {
        await _plugin.zonedSchedule(
          id: _overScheduledId,
          scheduledDate: RestOverSchedule.fireAt(endsAt),
          notificationDetails: _restOverDetails,
          androidScheduleMode: RestOverSchedule.modeFor(delivery)!,
          title: 'Rest over',
          body: nextLine,
        );
        _armed = delivery;
        break;
      } catch (e) {
        debugPrint('[REST_NOTIF] schedule ($delivery) failed: $e');
        // Permission revoked in between: fall back once to inexact.
        delivery = delivery == RestOverDelivery.exact
            ? RestOverDelivery.inexact
            : RestOverDelivery.none;
      }
    }
    return _armed;
  }

  /// "Rest over" alert with the next set (the in-app timer reached zero
  /// while the app is in the background).
  Future<void> showRestOver({required String nextLine}) async {
    if (!await _ensureInit()) return;
    try {
      await _plugin.cancel(id: _countdownId);
      if (!RestOverSchedule.showOnTimer(_armed)) {
        // The exact alarm posts it at this very moment.
        _armed = RestOverDelivery.none;
        return;
      }
      await _cancelScheduled();
      await _plugin.show(
        id: _overId,
        title: 'Rest over',
        body: nextLine,
        notificationDetails: _restOverDetails,
      );
    } catch (e) {
      debugPrint('[REST_NOTIF] rest-over failed: $e');
    }
  }

  Future<void> _cancelScheduled() async {
    _armed = RestOverDelivery.none;
    await _plugin.cancel(id: _overScheduledId);
  }

  Future<void> cancelCountdown() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _countdownId);
    } catch (_) {}
  }

  /// Rest skipped or ended in the app: drop the countdown and the pending
  /// "Rest over" alarm (an alert already shown stays).
  Future<void> cancelPending() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _countdownId);
      await _cancelScheduled();
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _countdownId);
      await _plugin.cancel(id: _overId);
      await _cancelScheduled();
    } catch (_) {}
  }
}

/// "Next: Bench Press set 3, target 62.5 kg × 8".
String restNextLine({
  required String exerciseName,
  required int setNumber,
  double? weight,
  int? reps,
  String Function(num)? fmt,
}) {
  final f = fmt ?? _fmt;
  final target = (weight != null && reps != null && weight > 0)
      ? ', target ${f(weight)} kg × $reps'
      : (reps != null ? ', target $reps reps' : '');
  return 'Next: $exerciseName set $setNumber$target';
}

String _fmt(num v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}
