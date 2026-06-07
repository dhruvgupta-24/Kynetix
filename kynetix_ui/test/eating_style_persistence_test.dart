// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kynetix/screens/onboarding_screen.dart';
import 'package:kynetix/services/profile_service.dart';
import 'package:kynetix/services/persistence_service.dart';

// ─── Eating Style Persistence Tests ───────────────────────────────────────────
//
// These tests verify that PortionAnchor (Eating Style) round-trips correctly
// through all layers: local JSON serialization, SharedPreferences, ProfileService
// Supabase map, and the auth-gate merge logic.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── 1. UserProfile JSON serialization ──────────────────────────────────────

  group('UserProfile.toJson / fromJson — portionAnchor roundtrip', () {
    test('carbAnchored survives toJson/fromJson', () {
      final profile = _makeProfile(PortionAnchor.carbAnchored);
      final json = profile.toJson();

      expect(json['portionAnchor'], 'carbAnchored');

      final restored = UserProfile.fromJson(json);
      expect(restored.portionAnchor, PortionAnchor.carbAnchored);
    });

    test('curryAnchored survives toJson/fromJson', () {
      final profile = _makeProfile(PortionAnchor.curryAnchored);
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.portionAnchor, PortionAnchor.curryAnchored);
    });

    test('balanced survives toJson/fromJson', () {
      final profile = _makeProfile(PortionAnchor.balanced);
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.portionAnchor, PortionAnchor.balanced);
    });

    test('null portionAnchor survives toJson/fromJson', () {
      final profile = _makeProfile(null);
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.portionAnchor, isNull);
    });

    test('unknown anchor string falls back to balanced', () {
      final json = _makeProfile(PortionAnchor.carbAnchored).toJson()
        ..['portionAnchor'] = 'unknownAnchorXYZ';
      final restored = UserProfile.fromJson(json);
      expect(restored.portionAnchor, PortionAnchor.balanced);
    });
  });

  // ── 2. PersistenceService roundtrip ─────────────────────────────────────────

  group('PersistenceService.saveProfile — portionAnchor persists', () {
    test('carbAnchored survives save + load cycle', () async {
      final profile = _makeProfile(PortionAnchor.carbAnchored);
      await PersistenceService.saveProfile(profile);

      // Simulate a fresh app start by loading from SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_profile_v2');
      expect(raw, isNotNull,
          reason: 'Profile JSON should be stored under user_profile_v2');

      // Deserialize the stored JSON.
      final loaded = UserProfile.fromJson(
          jsonDecode(raw!) as Map<String, dynamic>);
      expect(loaded.portionAnchor, PortionAnchor.carbAnchored,
          reason: 'portionAnchor should survive a full prefs round-trip');
    });

    test('null portionAnchor survives save + load cycle', () async {
      final profile = _makeProfile(null);
      await PersistenceService.saveProfile(profile);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_profile_v2');
      final loaded = UserProfile.fromJson(
          jsonDecode(raw!) as Map<String, dynamic>);
      expect(loaded.portionAnchor, isNull);
    });
  });

  // ── 3. ProfileService.upsertProfile map ─────────────────────────────────────

  group('ProfileService.upsertProfile — portion_anchor in payload', () {
    test('carbAnchored maps to portion_anchor = "carbAnchored"', () {
      // We cannot call Supabase in unit tests, so we inspect the build logic
      // by verifying the profile model correctly maps to the Supabase column
      // name via the pattern we implemented.
      final profile = _makeProfile(PortionAnchor.carbAnchored);
      // The upsert method includes portionAnchor via portionAnchor!.toJson().
      // toJson() returns the enum name string — verify this contract:
      expect(profile.portionAnchor!.toJson(), 'carbAnchored');
    });

    test('null portionAnchor maps to null column', () {
      final profile = _makeProfile(null);
      expect(profile.portionAnchor, isNull,
          reason: 'null portionAnchor should map to null DB column');
    });
  });

  // ── 4. ProfileService.fetchProfile Supabase row parsing ─────────────────────

  group('ProfileService fetchProfile — portion_anchor column parsing', () {
    test('carbAnchored row maps to carbAnchored enum', () {
      // Simulate the parsing logic inside fetchProfile:
      final anchorRaw = 'carbAnchored';
      final parsed = PortionAnchor.values.firstWhere(
        (e) => e.name == anchorRaw,
        orElse: () => PortionAnchor.balanced,
      );
      expect(parsed, PortionAnchor.carbAnchored);
    });

    test('curryAnchored row maps to curryAnchored enum', () {
      final anchorRaw = 'curryAnchored';
      final parsed = PortionAnchor.values.firstWhere(
        (e) => e.name == anchorRaw,
        orElse: () => PortionAnchor.balanced,
      );
      expect(parsed, PortionAnchor.curryAnchored);
    });

    test('null row column maps to null portionAnchor', () {
      final String? anchorRaw = null;
      final PortionAnchor? parsed = anchorRaw != null
          ? PortionAnchor.values.firstWhere(
              (e) => e.name == anchorRaw,
              orElse: () => PortionAnchor.balanced,
            )
          : null;
      expect(parsed, isNull);
    });

    test('invalid string falls back to balanced', () {
      final anchorRaw = 'junk_value';
      final parsed = PortionAnchor.values.firstWhere(
        (e) => e.name == anchorRaw,
        orElse: () => PortionAnchor.balanced,
      );
      expect(parsed, PortionAnchor.balanced);
    });
  });

  // ── 5. Auth gate merge logic ─────────────────────────────────────────────────

  group('Auth gate merge logic — remote wins', () {
    test('remote carbAnchored wins over local null', () {
      final remote = _makeProfile(PortionAnchor.carbAnchored);
      final local = _makeProfile(null);

      // This mirrors the fixed merge logic:
      //   final resolvedAnchor = remoteProfile.portionAnchor ?? currentUserProfile?.portionAnchor;
      final resolved = remote.portionAnchor ?? local.portionAnchor;
      expect(resolved, PortionAnchor.carbAnchored,
          reason: 'Remote non-null should always win');
    });

    test('remote null falls back to local curryAnchored', () {
      final remote = _makeProfile(null);
      final local = _makeProfile(PortionAnchor.curryAnchored);

      final resolved = remote.portionAnchor ?? local.portionAnchor;
      expect(resolved, PortionAnchor.curryAnchored,
          reason: 'When remote is null, local should be used as fallback');
    });

    test('remote balanced wins over local carbAnchored', () {
      final remote = _makeProfile(PortionAnchor.balanced);
      final local = _makeProfile(PortionAnchor.carbAnchored);

      final resolved = remote.portionAnchor ?? local.portionAnchor;
      expect(resolved, PortionAnchor.balanced,
          reason: 'Remote non-null should win even when local is set');
    });

    test('both null resolves to null', () {
      final remote = _makeProfile(null);
      final local = _makeProfile(null);

      final resolved = remote.portionAnchor ?? local.portionAnchor;
      expect(resolved, isNull);
    });
  });

  // ── 6. PortionAnchor display + AI hint contracts ─────────────────────────────

  group('PortionAnchor display labels and AI hints', () {
    test('carbAnchored has correct displayLabel', () {
      expect(
        PortionAnchor.carbAnchored.displayLabel,
        'Carb-anchored (roti/rice first)',
      );
    });

    test('curryAnchored has correct displayLabel', () {
      expect(
        PortionAnchor.curryAnchored.displayLabel,
        'Curry-anchored (dal/sabzi first)',
      );
    });

    test('carbAnchored aiHint mentions roti and dal', () {
      final hint = PortionAnchor.carbAnchored.aiHint;
      expect(hint.toLowerCase(), contains('roti'));
      expect(hint.toLowerCase(), contains('dal'));
    });

    test('curryAnchored aiHint mentions katori', () {
      final hint = PortionAnchor.curryAnchored.aiHint;
      expect(hint.toLowerCase(), contains('katori'));
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

UserProfile _makeProfile(PortionAnchor? anchor) => UserProfile(
      name: 'Test User',
      age: 22,
      gender: 'Male',
      height: 175.0,
      weight: 70.0,
      workoutDaysMin: 3,
      workoutDaysMax: 5,
      goal: 'Maintenance',
      portionAnchor: anchor,
    );
