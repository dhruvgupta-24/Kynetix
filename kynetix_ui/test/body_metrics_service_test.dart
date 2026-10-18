import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/services/body_metrics_service.dart';
import 'package:kynetix/services/health_service.dart' show WeightReading;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = BodyMetricsService.instance;
  final today = DateTime(2026, 10, 17);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await svc.initForUser('u1', prefsOverride: await SharedPreferences.getInstance());
  });

  test('trend smooths noise and manual wins over Health Connect', () async {
    final scale = [74.0, 74.6, 73.8, 74.4, 73.6, 74.0, 73.4, 73.6, 73.0, 73.2, 72.8, 73.0, 72.6, 72.6, 72.2];
    for (var i = 0; i < scale.length; i++) {
      await svc.logWeight(today.subtract(Duration(days: scale.length - 1 - i)), scale[i]);
    }
    final ext = [WeightReading(kg: 90, recordedAt: today.add(const Duration(hours: 7)), source: 'hc')];
    final t = svc.trend(external: ext, now: today);
    expect(t.latest!.scaleKg, 72.2, reason: 'manual weigh-in beats the Health Connect one');
    expect(t.latest!.trendKg, greaterThan(72.2));
    expect(t.latest!.trendKg, lessThan(74.0));
    final rate = t.weeklyRateKg!;
    expect(rate, lessThan(0));
    expect(rate, greaterThan(-1.2));
  });

  test('weight out of range is rejected; clear removes it', () async {
    expect(() => svc.logWeight(today, 5), throwsArgumentError);
    await svc.logWeight(today, 70.04);
    expect(svc.weightFor(today), 70.0);
    await svc.clearWeight(today);
    expect(svc.weightFor(today), isNull);
    expect(svc.lastWeightOnOrBefore(today), isNull);
  });
}
