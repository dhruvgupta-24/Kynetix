import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/services/insights_report_service.dart';
import 'package:kynetix/services/user_session_coordinator.dart';

/// Regression: insights caches were written to device-wide keys and every
/// account fell back to reading them, so a new account could see the previous
/// account's weekly totals and personal bests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes go to the account-scoped key, not the device-wide one', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await InsightsReportService.instance.initForUser('user-a', prefsOverride: prefs);
    await InsightsReportService.instance.reset();
    // reset() must clear both forms and never leave a device-wide copy.
    expect(prefs.getKeys().where((k) => k == 'insights_weekly_v1'), isEmpty);
  });

  test("a new account never reads the device's unscoped insights", () async {
    SharedPreferences.setMockInitialValues({
      // Device-wide legacy cache owned by someone else.
      'insights_weekly_v1': '{"2026-W40":{"bogus":true}}',
      'insights_personal_bests_v1': '{"bogus":true}',
      UserSessionCoordinator.legacyOwnerKey: 'device-owner',
    });
    final prefs = await SharedPreferences.getInstance();
    await InsightsReportService.instance.initForUser('someone-new', prefsOverride: prefs);
    expect(InsightsReportService.instance.weeklyCache, isEmpty);
    expect(InsightsReportService.instance.personalBests, isNull);
    // The legacy keys are left alone for their owner.
    expect(prefs.getString('insights_weekly_v1'), isNotNull);
  });
}
