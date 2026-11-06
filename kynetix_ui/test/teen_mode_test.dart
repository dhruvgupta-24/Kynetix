import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/screens/parent_check_screen.dart';
import 'package:kynetix/services/ai_nutrition_service.dart';
import 'package:kynetix/services/ai_router_error.dart';
import 'package:kynetix/services/analytics_service.dart';
import 'package:kynetix/services/consent_service.dart';
import 'package:kynetix/services/guardian_service.dart';
import 'package:kynetix/services/nutrition_target_engine.dart';
import 'package:kynetix/services/teen_mode.dart';
import 'package:kynetix/widgets/birthday_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime.now();
  DateTime yearsAgo(int y, {int days = 0}) => DateTime(now.year - y, now.month, now.day).subtract(Duration(days: days));

  UserProfile teen({String goal = kFatLoss, String gender = 'Male'}) => UserProfile(
        name: 'Aarav',
        age: 15,
        dateOfBirth: yearsAgo(15, days: 30),
        gender: gender,
        height: 170,
        weight: 60,
        workoutDaysMin: 4,
        workoutDaysMax: 4,
        goal: goal,
      );

  tearDown(() => TeenMode.debugOverride = null);

  group('who is a teen', () {
    test('13 to 17 is teen mode, 12 is too young, 18 is an adult', () {
      expect(birthdayStatus(yearsAgo(12, days: 300)), BirthdayStatus.tooYoung);
      expect(birthdayStatus(yearsAgo(13)), BirthdayStatus.teen);
      expect(birthdayStatus(yearsAgo(18).add(const Duration(days: 1))), BirthdayStatus.teen);
      expect(birthdayStatus(yearsAgo(18)), BirthdayStatus.ok);
      expect(birthdayAccepted(BirthdayStatus.teen), isTrue);
      expect(birthdayAccepted(BirthdayStatus.tooYoung), isFalse);
    });

    test('the birthday decides; the typed age only counts when there is none', () {
      expect(TeenMode.isMinor(teen()), isTrue);
      expect(TeenMode.isMinor(teen().copyWith(dateOfBirth: yearsAgo(20))), isFalse);
      const legacy = UserProfile(
        name: 'X', age: 16, gender: 'Male', height: 170, weight: 60,
        workoutDaysMin: 3, workoutDaysMax: 4, goal: kMaintenance,
      );
      expect(TeenMode.isMinor(legacy), isTrue);
      expect(TeenMode.isMinor(null), isFalse);
    });

    test('a teen agreeing to the policy counts as current consent', () {
      final r = ConsentRecord(version: ConsentService.policyVersion, consentedAt: now, ageConfirmedAdult: false);
      expect(r.isCurrent, isTrue);
    });
  });

  group('targets for a growing body', () {
    test('IOM energy equation for teens', () {
      final kcal = TeenMode.estimatedEnergyRequirement(male: true, age: 15, weightKg: 60, heightCm: 170, workoutDays: 4);
      expect(kcal, closeTo(3137.75, 0.01));
      final girl = TeenMode.estimatedEnergyRequirement(male: false, age: 15, weightKg: 52, heightCm: 160, workoutDays: 0);
      expect(girl, closeTo(135.3 - 30.8 * 15 + (520 + 934 * 1.6) + 25, 0.01));
    });

    test('fat loss never goes below maintenance; bulk is capped at a lean bulk', () {
      final engine = NutritionTargetEngine();
      final cut = engine.weeklyPlan(teen(goal: kFatLoss));
      expect(cut.avgDailyCalories, greaterThanOrEqualTo(cut.maintenanceCalories));
      expect(cut.maintenanceCalories, closeTo(3137.8, 1));
      final bulk = engine.weeklyPlan(teen(goal: kBulk));
      expect(bulk.avgDailyCalories - bulk.maintenanceCalories, inInclusiveRange(150, 250));
    });

    test('adults are untouched (still a deficit for fat loss)', () {
      final adult = teen(goal: kFatLoss).copyWith(age: 25, dateOfBirth: yearsAgo(25));
      final plan = NutritionTargetEngine().weeklyPlan(adult);
      expect(plan.avgDailyCalories, lessThan(plan.maintenanceCalories));
    });
  });

  group('AI on with teen rules, analytics off', () {
    test('meal estimates still go to the server for teens (it picks teen-safe providers)', () {
      TeenMode.debugOverride = true;
      expect(AiNutritionService.instance.isConfigured, isTrue);
    });

    test("the server's 403 parent_consent_required reads as teen mode, with calm copy", () {
      final e = AiRouterException.fromResponse(403, {'error': 'parent_consent_required'});
      expect(e.kind, AiRouterErrorKind.teenMode);
      expect(e.userMessage, contains('parent'));
      expect(AiRouterException.fromResponse(403, {'error': 'forbidden'}).kind, AiRouterErrorKind.generic);
    });

    test('analytics drop every event', () {
      TeenMode.debugOverride = true;
      final a = AnalyticsService(sink: (_) async {}, signedIn: () => true);
      a.track('app_open');
      a.track('meal_logged');
      expect(a.queued, 0);
      TeenMode.debugOverride = false;
      a.track('app_open');
      expect(a.queued, 1);
    });
  });

  group('parent check', () {
    late List<Map<String, dynamic>> calls;
    late String serverStatus;
    late GuardianService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      calls = [];
      serverStatus = 'none';
      svc = GuardianService.instance
        ..prefsOverride = await SharedPreferences.getInstance()
        ..transportOverride = (body) async {
          calls.add(body);
          if (body['action'] == 'request') {
            serverStatus = 'pending';
            return {'status': 'pending', 'link': 'https://dhruvgupta-24.github.io/Kynetix/parent/#t=abc', 'expires_at': '2030-01-01T00:00:00Z'};
          }
          return {'status': serverStatus};
        };
    });

    tearDown(() {
      svc.transportOverride = null;
      svc.prefsOverride = null;
    });

    test('a request sends the birthday as a plain date and remembers the status', () async {
      final link = await svc.requestLink(userId: 'u1', dateOfBirth: DateTime(2011, 3, 9), firstName: ' Aarav ');
      expect(calls.single, {'action': 'request', 'dob': '2011-03-09', 'first_name': 'Aarav'});
      expect(link.link, contains('#t='));
      expect(svc.peek('u1'), GuardianStatus.pending);
    });

    test('offline, the last known answer stands', () async {
      serverStatus = 'approved';
      expect(await svc.refresh('u1'), GuardianStatus.approved);
      svc.transportOverride = (_) async => throw const GuardianException('offline');
      expect(await svc.refresh('u1'), GuardianStatus.approved);
    });

    testWidgets('send the link, then move on by itself once the parent says yes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final shared = <String>[];
      var approved = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ParentCheckPanel(
            userId: 'u2',
            dateOfBirth: DateTime(2011, 3, 9),
            initialFirstName: 'Aarav Gupta',
            service: svc,
            pollEvery: const Duration(seconds: 1),
            share: (t) async => shared.add(t),
            onApproved: () => approved++,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Kyno, with teen rules'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('parent-send-link')));
      // The waiting card spins, so pump instead of settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(shared.single, contains('#t=abc'));
      expect(find.text('Waiting on the yes'), findsOneWidget);
      serverStatus = 'approved';
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(approved, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a parent who switched it off gets an honest screen with a way out', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      serverStatus = 'revoked';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ParentCheckPanel(
            userId: 'u3',
            dateOfBirth: DateTime(2011, 3, 9),
            service: svc,
            onApproved: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('switched Kynetix off'), findsOneWidget);
      expect(find.text('Delete my account'), findsOneWidget);
      expect(find.text('Send a new link'), findsOneWidget);
    });
  });
}
