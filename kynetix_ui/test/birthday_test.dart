import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/screens/birthday_screen.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/widgets/birthday_field.dart';
import 'package:kynetix/ui/k_shear_text.dart';

void main() {
  const base = UserProfile(
    name: 'Dhruv Gupta',
    age: 20,
    gender: 'Male',
    height: 175,
    weight: 72,
    workoutDaysMin: 4,
    workoutDaysMax: 5,
    goal: 'Maintenance',
  );

  group('age from a birthday', () {
    test('counts whole years, turning over on the day', () {
      final dob = DateTime(2000, 11, 6);
      expect(UserProfile.ageOn(dob, DateTime(2026, 11, 5)), 25);
      expect(UserProfile.ageOn(dob, DateTime(2026, 11, 6)), 26);
    });

    test('withCurrentAge corrects a stale age and leaves no-birthday profiles alone', () {
      final p = base.copyWith(dateOfBirth: DateTime(2000, 1, 1));
      expect(p.withCurrentAge(DateTime(2026, 11, 6)).age, 26);
      expect(identical(base.withCurrentAge(DateTime(2026, 11, 6)), base), isTrue);
    });

    test('29 February birthdays are celebrated on 28 February in other years', () {
      final p = base.copyWith(dateOfBirth: DateTime(2004, 2, 29));
      expect(p.isBirthday(DateTime(2027, 2, 28)), isTrue);
      expect(p.isBirthday(DateTime(2028, 2, 29)), isTrue);
      expect(p.isBirthday(DateTime(2028, 2, 28)), isFalse);
    });

    test('18 and up only, and no impossible years', () {
      final now = DateTime(2026, 11, 6);
      expect(birthdayStatus(null, now: now), BirthdayStatus.missing);
      expect(birthdayStatus(DateTime(2008, 11, 7), now: now), BirthdayStatus.tooYoung);
      expect(birthdayStatus(DateTime(2008, 11, 6), now: now), BirthdayStatus.ok);
      expect(birthdayStatus(DateTime(1900, 1, 1), now: now), BirthdayStatus.implausible);
    });
  });

  group('the birthday survives every save and sync path', () {
    test('json round trip keeps it as a plain date', () {
      final p = base.copyWith(dateOfBirth: DateTime(1999, 7, 4));
      expect(p.toJson()['dateOfBirth'], '1999-07-04');
      expect(UserProfile.fromJson(p.toJson()).dateOfBirth, DateTime(1999, 7, 4));
    });

    test('copyWithHealth keeps it', () {
      final p = base.copyWith(dateOfBirth: DateTime(1999, 7, 4));
      expect(p.copyWithHealth(averageDailySteps: 8000, lastHealthSyncAt: DateTime(2026)).dateOfBirth, DateTime(1999, 7, 4));
    });

    test('a cloud row without a birthday never erases the local one', () {
      final local = base.copyWith(dateOfBirth: DateTime(1999, 7, 4));
      final row = {
        'name': 'Dhruv',
        'age': 27,
        'gender': 'Male',
        'height_cm': 175,
        'weight_kg': 72,
        'profile_json': base.toJson(),
      };
      final remote = ProfileService.profileFromRow(row, local: local)!;
      final merged = ProfileService.mergeRemoteWithLocal(remote, local);
      expect(merged.dateOfBirth, DateTime(1999, 7, 4));
    });
  });

  testWidgets('the party screen rolls the age and names the user', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final p = base.copyWith(age: 27, dateOfBirth: DateTime(1999, 11, 6));
    await tester.pumpWidget(MaterialApp(home: BirthdayScreen(profile: p, now: DateTime(2026, 11, 6, 9))));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byWidgetPredicate((w) => w is KShearText && w.text == 'HAPPY BIRTHDAY, DHRUV'), findsOneWidget);
    expect(find.text('UNLOCKED'), findsOneWidget);
    expect(find.text("Let's get it"), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The confetti stops: nothing keeps ticking once it has fallen.
    await tester.pump(const Duration(seconds: 8));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
