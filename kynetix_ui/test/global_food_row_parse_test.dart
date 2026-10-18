import 'package:flutter_test/flutter_test.dart';

import 'package:kynetix/services/global_food_service.dart';

void main() {
  test('server rows use *_per_unit columns', () {
    final item = GlobalFoodItem.fromJson({
      'id': 'x',
      'canonical_name': 'roti',
      'calories_per_unit': 100,
      'protein_per_unit': 3,
      'carbs_per_unit': 17.5,
      'fat_per_unit': 2,
      'fiber_per_unit': 1,
      'reference_quantity': 1,
      'reference_unit': 'piece',
    });
    expect(item.caloriesMid, 100);
    expect(item.proteinMid, 3);
    expect(item.carbsMid, 17.5);
    final two = item.toNutritionResult(quantity: 2);
    expect(two.calories.mid, 200);
    expect(two.protein.mid, 6);
  });

  test('cache rows (*_mid) still parse', () {
    final item = GlobalFoodItem.fromJson({'canonical_name': 'roti', 'calories_mid': 100, 'protein_mid': 3});
    expect(item.caloriesMid, 100);
    expect(GlobalFoodItem.fromJson(item.toJson()).proteinMid, 3);
  });
}
