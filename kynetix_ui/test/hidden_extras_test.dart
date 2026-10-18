import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/hidden_extras.dart';

void main() {
  test('roti and dal suggest ghee and oil, chai suggests sugar', () {
    expect(HiddenExtras.suggest('2 roti, 1 katori dal').map((e) => e.id), ['ghee', 'butter', 'oil']);
    expect(HiddenExtras.suggest('1 cup chai').map((e) => e.id), ['sugar']);
  });

  test('already named extras and unrelated foods get nothing extra', () {
    expect(HiddenExtras.suggest('2 roti with ghee').map((e) => e.id), isNot(contains('ghee')));
    expect(HiddenExtras.suggest('100 g chicken breast, 3 egg whites'), isEmpty);
    expect(HiddenExtras.suggest('chai with sugar'), isEmpty);
  });
}
