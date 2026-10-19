import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/mock_estimation_service.dart';

/// "1 katori dal" is a stated amount (~2 ladles), not a mess ladle that was
/// only partly eaten (which gave 39 kcal for a katori of dal).
void main() {
  test('a katori of dal is about two ladles, fully eaten', () {
    final r = mockProcessMealInput('1 katori dal');
    expect(r.calories.mid, inInclusiveRange(110, 150));
    // Two ladles of thin mess dal at 3.0-3.5 g protein per ladle.
    expect(r.protein.mid, greaterThanOrEqualTo(6));
  });

  test('plain "dal" keeps the mess ladle partial-eat model', () {
    final r = mockProcessMealInput('dal');
    expect(r.calories.mid, lessThan(60));
  });
}
