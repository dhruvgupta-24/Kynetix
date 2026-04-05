import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/services/nutrition_pipeline.dart';
import 'package:kynetix/services/ai_nutrition_service.dart';
import 'package:kynetix/services/user_nutrition_memory.dart';
import 'package:kynetix/services/personal_nutrition_memory.dart';

void main() async {
  print('parsing pipeline end-to-end validation');
  final out = StringBuffer();
  // Provide a mocked logger
  final logStrings = <String>[];
  debugPrint = (String? message, {int? wrapWidth}) {
    logStrings.add(message ?? '');
    out.writeln(message);
    print(message);
  };

  final testCases = [
    "1 scoop whey with 150g tofu",
    "2 roti with 1 ladle rice with chana dal",
    "1 dominos pizza slice with 450ml mango shake",
    "paneer with rice",
    "dal chawal",
  ];

  out.writeln('\n======================================================');
  try {
    for (final raw in testCases) {
      out.writeln('\n\n==== PIPELINE VALIDATION: "$raw" ====');
      final result = await NutritionPipeline.instance.estimateMeal(raw);
      out.writeln('\nFINAL RESULT ITEMS:');
      for (final i in result.items) {
        out.writeln('  - ${i.name} [qty: ${i.quantity}, unit: ${i.unit}] -> ${i.calories.min}-${i.calories.max} kcal (mode: ${i.mode.name})');
      }
      out.writeln('OVERALL CALORIES: ${result.calories.min} - ${result.calories.max} kcal');
    }
  } catch(e, s) {
    print('EXCEPTION: $e\n$s');
    out.writeln('EXCEPTION: $e\n$s');
  }
  
  File('output_e2e_trace.txt').writeAsStringSync(out.toString());
}
