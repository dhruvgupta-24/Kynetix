import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/screens/insights_screen.dart';
import 'package:kynetix/services/workout_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Leaving Insights within three seconds used to leave the "achievements
/// viewed" timer running after the screen was gone. It is now cancelled on
/// dispose, so a quick visit leaves nothing behind.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(url: 'https://mock.supabase.co', anonKey: 'mock-anon-key');
    } catch (_) {}
    await WorkoutService.instance.init();
  });

  testWidgets('a quick visit to Insights leaves no pending timer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InsightsScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    // Leave before the 3 s timer fires. The test binding fails the test if any
    // timer is still pending once the tree is torn down.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
