import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/main.dart';

void main() {
  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const KynetixApp());
    // Onboarding screen should appear on first launch.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
