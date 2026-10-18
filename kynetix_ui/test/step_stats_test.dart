import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/health_service.dart';

void main() {
  test('14-day average uses exactly the latest 14 completed days', () {
    // index 0 = yesterday. Latest 14 days are 10k; older days are 2k.
    final days = <double?>[
      ...List.filled(14, 10000.0),
      ...List.filled(16, 2000.0),
    ];
    final s = computeStepStats(days);
    expect(s.days14.length, 14);
    expect(s.avg14, 10000);
    expect(s.avg7, 10000);
    // 30-day mean = (14*10000 + 16*2000) / 30
    expect(s.avg30, ((14 * 10000 + 16 * 2000) / 30).roundToDouble());
    expect(s.effective, closeTo(s.avg14! * 0.7 + s.avg30! * 0.3, 0.001));
  });

  test('wear-gap days and failed reads are left out, not counted as zero', () {
    final days = <double?>[
      8000, 40, null, 9000, 0, 10000, 499, // 3 usable days in the latest 7
      ...List.filled(23, 7000.0),
    ];
    final s = computeStepStats(days);
    expect(s.days7, [8000, 9000, 10000]);
    expect(s.avg7, 9000);
    expect(s.days14.length, 3 + 7); // latest 14 = 7 above + 7 of the 7000s
  });

  test('no usable days gives no average', () {
    final s = computeStepStats(List<double?>.filled(30, null));
    expect(s.avg14, isNull);
    expect(s.effective, isNull);
  });

  test('only the latest 30 days are considered', () {
    final s = computeStepStats([...List.filled(30, 5000.0), 99999.0]);
    expect(s.days30.length, 30);
    expect(s.avg30, 5000);
  });
}
