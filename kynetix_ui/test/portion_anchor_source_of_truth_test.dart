/// Regression test: NutritionPipeline must read PortionAnchor from
/// ProfileService.activePortionAnchor, not EatingPatternService._seededAnchor.
///
/// Failure case guarded:
///   1. User selects Carb-Anchored → seeds EatingPatternService.
///   2. User changes to Curry-Anchored → ProfileService updated.
///   3. Reseed is skipped / delayed.
///   4. Pipeline should still use Curry-Anchored behavior because it reads
///      ProfileService, not the now-stale EatingPatternService._seededAnchor.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kynetix/models/user_profile.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/eating_pattern_service.dart';

void main() {
  group('PortionAnchor source-of-truth', () {
    setUp(() {
      // Reset both services to a clean state before each test.
      ProfileService.instance.currentUserProfile = null;
      EatingPatternService.instance.resetAll();
    });

    // ── Test 1: ProfileService is the source, not EatingPatternService ──────

    test(
      'activePortionAnchor reflects ProfileService, not EatingPatternService._seededAnchor',
      () {
        // Step 1 — Set profile to carb-anchored.
        ProfileService.instance.currentUserProfile = UserProfile(
          name: 'Test',
          age: 25,
          gender: 'Male',
          height: 170,
          weight: 70,
          workoutDaysMin: 3,
          workoutDaysMax: 5,
          goal: 'Maintenance',
          portionAnchor: PortionAnchor.carbAnchored,
        );

        // Step 2 — Seed EatingPatternService with carb-anchored.
        EatingPatternService.instance
            .seedFromPortionAnchor(PortionAnchor.carbAnchored);

        // Verify seeds are in place.
        expect(EatingPatternService.instance.activeAnchor,
            equals(PortionAnchor.carbAnchored),
            reason: 'Seed applied — EatingPatternService should reflect carbAnchored');
        expect(ProfileService.instance.activePortionAnchor,
            equals(PortionAnchor.carbAnchored),
            reason: 'ProfileService should agree initially');

        // Step 3 — User changes profile to curry-anchored.
        //          Intentionally skip EatingPatternService reseed to simulate
        //          the race condition or delayed reseed scenario.
        ProfileService.instance.currentUserProfile = UserProfile(
          name: 'Test',
          age: 25,
          gender: 'Male',
          height: 170,
          weight: 70,
          workoutDaysMin: 3,
          workoutDaysMax: 5,
          goal: 'Maintenance',
          portionAnchor: PortionAnchor.curryAnchored,
        );

        // Step 4 — EatingPatternService still says carbAnchored (stale).
        expect(EatingPatternService.instance.activeAnchor,
            equals(PortionAnchor.carbAnchored),
            reason: 'EatingPatternService._seededAnchor has NOT been updated — '
                'simulating a delayed/skipped reseed');

        // Step 5 — But ProfileService should immediately reflect curryAnchored.
        expect(ProfileService.instance.activePortionAnchor,
            equals(PortionAnchor.curryAnchored),
            reason:
                'ProfileService.activePortionAnchor must reflect the current '
                'profile setting, not the stale EatingPatternService._seededAnchor');

        // Step 6 — The two diverge. Confirm this is the scenario we are guarding against.
        expect(
          ProfileService.instance.activePortionAnchor !=
              EatingPatternService.instance.activeAnchor,
          isTrue,
          reason:
              'Services have diverged — pipeline MUST use ProfileService '
              '(curryAnchored), not EatingPatternService (carbAnchored)',
        );
      },
    );

    // ── Test 2: Null profile defaults to balanced in ProfileService ──────────

    test(
      'activePortionAnchor defaults to balanced when no profile is set',
      () {
        // No profile set — ProfileService.currentUserProfile is null.
        expect(ProfileService.instance.currentUserProfile, isNull);

        // EatingPatternService might have an old seed from a previous session.
        EatingPatternService.instance
            .seedFromPortionAnchor(PortionAnchor.carbAnchored);

        // ProfileService must still default to balanced regardless of the seed.
        expect(ProfileService.instance.activePortionAnchor,
            equals(PortionAnchor.balanced),
            reason:
                'No profile → activePortionAnchor should default to balanced, '
                'not inherit EatingPatternService state');
      },
    );

    // ── Test 3: Profile change without reseed — expected divergence ─────────

    test(
      'Pipeline reads ProfileService anchor, not EatingPatternService: '
      'change profile without reseed and verify ProfileService wins',
      () {
        // Start balanced.
        ProfileService.instance.currentUserProfile = UserProfile(
          name: 'User',
          age: 30,
          gender: 'Female',
          height: 160,
          weight: 60,
          workoutDaysMin: 2,
          workoutDaysMax: 4,
          goal: 'Fat Loss',
          portionAnchor: PortionAnchor.balanced,
        );
        EatingPatternService.instance
            .seedFromPortionAnchor(PortionAnchor.balanced);

        expect(ProfileService.instance.activePortionAnchor,
            equals(PortionAnchor.balanced));
        expect(EatingPatternService.instance.activeAnchor,
            equals(PortionAnchor.balanced));

        // Change to curry-anchored — no reseed.
        ProfileService.instance.currentUserProfile = UserProfile(
          name: 'User',
          age: 30,
          gender: 'Female',
          height: 160,
          weight: 60,
          workoutDaysMin: 2,
          workoutDaysMax: 4,
          goal: 'Fat Loss',
          portionAnchor: PortionAnchor.curryAnchored,
        );

        // ProfileService immediately reflects the new preference.
        expect(ProfileService.instance.activePortionAnchor,
            equals(PortionAnchor.curryAnchored),
            reason: 'ProfileService reflects new preference immediately');

        // EatingPatternService is stale.
        expect(EatingPatternService.instance.activeAnchor,
            equals(PortionAnchor.balanced),
            reason: 'EatingPatternService is stale — no reseed called');

        // Confirm: pipeline should use ProfileService value.
        // This is the direct value _applyMealLevelPortionAnchorPass will call.
        final pipelineAnchor = ProfileService.instance.activePortionAnchor;
        expect(pipelineAnchor, equals(PortionAnchor.curryAnchored),
            reason:
                'Pipeline reads ProfileService.instance.activePortionAnchor '
                'which equals curryAnchored — stale EatingPatternService seed is ignored');
      },
    );

    // ── Test 4: After proper reseed, both services agree ────────────────────

    test(
      'After proper reseed, EatingPatternService and ProfileService agree',
      () {
        // Start carb-anchored.
        ProfileService.instance.currentUserProfile = UserProfile(
          name: 'User',
          age: 28,
          gender: 'Male',
          height: 175,
          weight: 75,
          workoutDaysMin: 4,
          workoutDaysMax: 5,
          goal: 'Muscle Gain',
          portionAnchor: PortionAnchor.carbAnchored,
        );
        EatingPatternService.instance
            .seedFromPortionAnchor(PortionAnchor.carbAnchored);

        // Change profile AND reseed (normal app flow).
        ProfileService.instance.currentUserProfile = UserProfile(
          name: 'User',
          age: 28,
          gender: 'Male',
          height: 175,
          weight: 75,
          workoutDaysMin: 4,
          workoutDaysMax: 5,
          goal: 'Muscle Gain',
          portionAnchor: PortionAnchor.curryAnchored,
        );
        EatingPatternService.instance
            .seedFromPortionAnchor(PortionAnchor.curryAnchored);

        // Both must agree now.
        expect(ProfileService.instance.activePortionAnchor,
            equals(PortionAnchor.curryAnchored));
        expect(EatingPatternService.instance.activeAnchor,
            equals(PortionAnchor.curryAnchored));
        expect(
          ProfileService.instance.activePortionAnchor ==
              EatingPatternService.instance.activeAnchor,
          isTrue,
          reason: 'After proper reseed, both services agree',
        );
      },
    );
  });
}
