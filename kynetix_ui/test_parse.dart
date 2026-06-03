// ignore_for_file: avoid_print, unused_import
import 'package:flutter/foundation.dart';
import 'lib/services/item_parser.dart';

void main() {
  debugPrint = (String? message, {int? wrapWidth}) => print(message);
  final testCases = [
    "4 bread slices with 40g peanut butter",
    "2 roti + channa",
    "rice + dal",
    "rajma chawal",
    "oats + milk",
    "chicken + rice",
    "paneer + roti",
    "pasta + sauce",
    "sandwich + mayo",
  ];

  for (final raw in testCases) {
    print('\nInput: "$raw"');
    final res = ItemParser.parse(raw);
    for (final item in res) {
      print('  -> $item');
    }
  }
}

