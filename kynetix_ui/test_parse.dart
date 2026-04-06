// ignore_for_file: avoid_print, unused_import
import 'package:flutter/foundation.dart';
import 'lib/services/mock_estimation_service.dart';

void main() {
  debugPrint = (String? message, {int? wrapWidth}) => print(message);
  final res = analyzeLocalEstimation("1 scoop whey with 150g tofu");
  print(res.estimation.toJson());
}
