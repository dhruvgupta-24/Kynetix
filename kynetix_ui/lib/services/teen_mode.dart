import '../models/user_profile.dart';
import 'profile_service.dart';

/// Teen mode: Kynetix for 13 to 17 year olds.
///
/// Same app, with four differences, all keyed off the birthday:
///  * a parent or guardian says yes first (GuardianService, DPDP Act s.9);
///  * AI only on providers whose terms allow teens (OpenAI, Groq, or their own
///    ChatGPT), never Gemini or OpenRouter, with teen safety rules added and
///    risky messages moderated. All of that is enforced on the server;
///  * no product analytics (no behavioural tracking of children, s.9(3));
///  * energy targets sized for a growing body (IOM estimated energy
///    requirement for 9 to 18 year olds) and never set below maintenance.
///
/// Turning 18 ends it on its own: everything here reads the age from the
/// birthday each time.
abstract final class TeenMode {
  /// Youngest age Kynetix is for.
  static const minimumAge = 13;

  /// Teen mode ends on this birthday.
  static const adultAge = 18;

  /// True for a birthday that makes someone 13 to 17 on [now].
  static bool isMinorDob(DateTime? dob, {DateTime? now}) {
    if (dob == null) return false;
    final age = UserProfile.ageOn(dob, now ?? DateTime.now());
    return age < adultAge;
  }

  /// True when [p] belongs to someone under 18. Profiles without a birthday
  /// fall back to the typed-in age.
  static bool isMinor(UserProfile? p, {DateTime? now}) {
    if (p == null) return false;
    if (p.dateOfBirth != null) return isMinorDob(p.dateOfBirth, now: now);
    return p.age > 0 && p.age < adultAge;
  }

  /// Test hook: forces teen mode on or off regardless of the profile.
  static bool? debugOverride;

  /// Teen mode for the signed-in user's profile.
  static bool get active =>
      debugOverride ?? isMinor(ProfileService.instance.currentUserProfile);

  /// Estimated energy requirement for 9 to 18 year olds (Institute of
  /// Medicine DRI, 2005), in kcal/day. It already includes the energy cost
  /// of growth. [workoutDays] maps to the physical activity level:
  /// sedentary (0), low active (1 to 2), active (3 to 4), very active (5+).
  static double estimatedEnergyRequirement({
    required bool male,
    required int age,
    required double weightKg,
    required double heightCm,
    required double workoutDays,
  }) {
    final h = heightCm / 100.0;
    final level = workoutDays <= 0.5
        ? 0
        : workoutDays <= 2.5
            ? 1
            : workoutDays <= 4.5
                ? 2
                : 3;
    if (male) {
      const pa = [1.00, 1.13, 1.26, 1.42];
      return 88.5 - 61.9 * age + pa[level] * (26.7 * weightKg + 903 * h) + 25;
    }
    const pa = [1.00, 1.16, 1.31, 1.56];
    return 135.3 - 30.8 * age + pa[level] * (10.0 * weightKg + 934 * h) + 25;
  }
}
