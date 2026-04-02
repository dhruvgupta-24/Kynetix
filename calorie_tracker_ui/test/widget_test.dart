import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_tracker_ui/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const CalorieTrackerApp());
    // Onboarding screen should appear on first launch.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
