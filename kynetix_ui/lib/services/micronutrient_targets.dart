// Daily micronutrient targets for adults, by sex and age.
//
// Source: ICMR-NIN 2020, "Nutrient Requirements for Indians: Recommended
// Dietary Allowances (RDA) and Estimated Average Requirements (EAR)",
// National Institute of Nutrition, Hyderabad. Adult values, sedentary to
// moderate activity:
//   iron        19 mg (men), 29 mg (women of reproductive age)
//   calcium     1000 mg; 1200 mg for women after menopause (age >= 50 used
//               as the proxy here)
//   vitamin B12 2.5 µg
//   vitamin D   600 IU = 15 µg (assuming little sun exposure)
//   sodium      under 2000 mg (about 5 g salt), a limit not a target
//   potassium   3500 mg
//   magnesium   440 mg (men), 370 mg (women)
//   zinc        17 mg (men), 13.2 mg (women)
//
// These are population allowances, not a diagnosis. The app only uses them to
// show where a logged diet tends to fall short.

import '../models/micronutrients.dart';
import '../models/user_profile.dart';

class MicroTarget {
  const MicroTarget(this.micro, this.amount);
  final Micro micro;

  /// RDA to reach, or (for [Micro.isLimit]) the ceiling to stay under.
  final double amount;

  bool get isLimit => micro.isLimit;
}

abstract final class MicronutrientTargets {
  static const String citation =
      'ICMR-NIN 2020 Recommended Dietary Allowances for Indians';

  /// Targets for a person. [sex] is the profile's free text ("Male",
  /// "Female"); anything not clearly female uses the male values, which are
  /// the lower iron and the higher magnesium/zinc.
  static Map<Micro, MicroTarget> forPerson({String? sex, int? age}) {
    final female = isFemale(sex);
    final older = (age ?? 0) >= 50;
    double v(Micro m) => switch (m) {
          Micro.iron => female && !older ? 29 : 19,
          Micro.calcium => female && older ? 1200 : 1000,
          Micro.vitaminB12 => 2.5,
          Micro.vitaminD => 15,
          Micro.sodium => 2000,
          Micro.potassium => 3500,
          Micro.magnesium => female ? 370 : 440,
          Micro.zinc => female ? 13.2 : 17,
        };
    return {for (final m in Micro.values) m: MicroTarget(m, v(m))};
  }

  static Map<Micro, MicroTarget> forProfile(UserProfile? p) =>
      forPerson(sex: p?.gender, age: p?.age);

  static bool isFemale(String? sex) {
    final s = (sex ?? '').trim().toLowerCase();
    return s == 'female' || s == 'f' || s == 'woman';
  }
}
