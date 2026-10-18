import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kynetix/screens/dashboard_screen.dart';

import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/models/user_profile.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    ProfileService.instance.currentUserProfile = const UserProfile(
      name: 'Dev Tester',
      age: 25,
      gender: 'Male',
      height: 175.0,
      weight: 70.0,
      workoutDaysMin: 4,
      workoutDaysMax: 5,
      goal: 'Fat Loss',
    );
    try {
      await Supabase.initialize(
        url: 'https://mock.supabase.co',
        anonKey: 'mock-anon-key',
      );
    } catch (_) {}
  });

  testWidgets('WF-10 REGRESSION: Dashboard profile control exposes accessible semantic label "Profile"', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final profileSemantics = find.bySemanticsLabel('Profile');

    // On unpatched code, this assertion MUST FAIL because _AvatarBadge only renders
    // dynamic initials (e.g. "DT") with no semantic label or tooltip.
    expect(
      profileSemantics,
      findsOneWidget,
      reason: 'CRITICAL ACCESSIBILITY DEFECT: Profile control lacks semantic label "Profile". Screen readers and automation cannot locate profile navigation.',
    );

    handle.dispose();
  });
}
