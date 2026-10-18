import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/auth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

TextField _passwordTextField(WidgetTester tester) => tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('password_field')),
        matching: find.byType(TextField),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sign-up password toggle flips obscureText and its label',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();

    // Switch to the sign-up form.
    await tester.tap(find.bySemanticsLabel('Sign up'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);

    // Hidden by default, with a 48dp toggle that offers to show it.
    expect(_passwordTextField(tester).obscureText, isTrue);
    final toggle = find.byKey(const ValueKey('password_visibility_toggle'));
    expect(toggle, findsOneWidget);
    final box = tester.getSize(toggle);
    expect(box.width, greaterThanOrEqualTo(48));
    expect(box.height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Show password'), findsOneWidget);

    // Show.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_passwordTextField(tester).obscureText, isFalse);
    expect(find.bySemanticsLabel('Hide password'), findsOneWidget);

    // Hide again.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_passwordTextField(tester).obscureText, isTrue);
    expect(find.bySemanticsLabel('Show password'), findsOneWidget);

    semantics.dispose();
  });
}
