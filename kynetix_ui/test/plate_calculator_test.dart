import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/widgets/barbell_plate_calculator.dart';

void main() {
  group('BarbellPlateCalculator Tests', () {
    test('handles bar-only weight (20 kg) correctly', () {
      final res = BarbellPlateCalculator.calculate(targetWeightKg: 20.0, barWeightKg: 20.0);
      expect(res.weightPerSide, equals(0.0));
      expect(res.platesPerSide, isEmpty);
      expect(res.isExact, isTrue);
      expect(res.summaryText, contains('20 kg bar only'));
    });

    test('calculates 60 kg (20 kg per side = 1x20kg plate) correctly', () {
      final res = BarbellPlateCalculator.calculate(targetWeightKg: 60.0, barWeightKg: 20.0);
      expect(res.weightPerSide, equals(20.0));
      expect(res.platesPerSide, equals([20.0]));
      expect(res.isExact, isTrue);
      expect(res.summaryText, equals('20 kg / side'));
    });

    test('calculates 100 kg (40 kg per side = 25kg + 15kg plates) correctly', () {
      final res = BarbellPlateCalculator.calculate(targetWeightKg: 100.0, barWeightKg: 20.0);
      expect(res.weightPerSide, equals(40.0));
      expect(res.platesPerSide, equals([25.0, 15.0]));
      expect(res.isExact, isTrue);
      expect(res.summaryText, equals('25 + 15 kg / side'));
    });

    test('calculates complex plate combos (82.5 kg = 25 + 5 + 1.25 / side)', () {
      final res = BarbellPlateCalculator.calculate(targetWeightKg: 82.5, barWeightKg: 20.0);
      expect(res.weightPerSide, equals(31.25));
      expect(res.platesPerSide, equals([25.0, 5.0, 1.25]));
      expect(res.isExact, isTrue);
      expect(res.summaryText, equals('25 + 5 + 1.25 kg / side'));
    });

    test('calculates with custom 20kg max plates inventory ([20, 20] for 40kg/side)', () {
      final res = BarbellPlateCalculator.calculate(
        targetWeightKg: 100.0,
        barWeightKg: 20.0,
        availablePlates: [20.0, 15.0, 10.0, 5.0, 2.5, 1.25],
      );
      expect(res.weightPerSide, equals(40.0));
      expect(res.platesPerSide, equals([20.0, 20.0]));
      expect(res.isExact, isTrue);
      expect(res.summaryText, equals('2×20 kg / side'));
    });

    test('handles weights below bar weight safely without crashing', () {
      final res = BarbellPlateCalculator.calculate(targetWeightKg: 15.0, barWeightKg: 20.0);
      expect(res.weightPerSide, equals(0.0));
      expect(res.platesPerSide, isEmpty);
    });
  });
}
