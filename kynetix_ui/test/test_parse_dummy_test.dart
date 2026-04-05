import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';

void main() {
  test('parsing', () async {
    final res = await NutritionPipeline.instance.estimateMeal("1 scoop whey with 150g tofu");
    File('output_test.json').writeAsStringSync(jsonEncode(res.toJson()));
  });
}
