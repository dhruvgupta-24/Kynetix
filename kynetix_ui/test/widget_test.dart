import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    // Set up mock values for SharedPreferences so that Supabase local storage initialization doesn't crash on platform channel
    SharedPreferences.setMockInitialValues({});
    
    // Initialize mock Supabase client to avoid uninitialized instance assertions in initState
    await Supabase.initialize(
      url: 'https://mock.supabase.co',
      anonKey: 'mock-anon-key',
    );
  });

  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const KynetixApp());
    // Onboarding screen should appear on first launch.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
