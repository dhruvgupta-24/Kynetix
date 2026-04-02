import '../models/day_log.dart';

class MealPatternSnapshot {
  final Map<MealSection, List<String>> commonFoodsBySection;
  final Map<MealSection, double> averageMealHourBySection;
  final double breakfastProteinAverage;
  final double lunchProteinAverage;
  final double dinnerProteinAverage;
  final bool tendsToMissProteinEarly;
  final int daysLogged;

  const MealPatternSnapshot({
    required this.commonFoodsBySection,
    required this.averageMealHourBySection,
    required this.breakfastProteinAverage,
    required this.lunchProteinAverage,
    required this.dinnerProteinAverage,
    required this.tendsToMissProteinEarly,
    required this.daysLogged,
  });
}

class DayPatternService {
  DayPatternService._();
  static final DayPatternService instance = DayPatternService._();

  MealPatternSnapshot snapshot({DateTime? upTo}) {
    final cutoff = upTo ?? DateTime.now();
    final common = <MealSection, Map<String, int>>{
      for (final s in MealSection.values) s: <String, int>{},
    };
    final hourTotals = <MealSection, double>{for (final s in MealSection.values) s: 0};
    final hourCounts = <MealSection, int>{for (final s in MealSection.values) s: 0};
    double breakfastProtein = 0;
    double lunchProtein = 0;
    double dinnerProtein = 0;
    int breakfastDays = 0;
    int lunchDays = 0;
    int dinnerDays = 0;
    int days = 0;

    for (final item in dayLogStore.entries) {
      final day = DateTime.tryParse(item.key);
      if (day == null || day.isAfter(cutoff)) continue;
      final log = item.value;
      if (log.isEmpty) continue;
      days++;

      for (final section in MealSection.values) {
        final entries = log.entriesFor(section);
        if (entries.isEmpty) continue;
        for (final e in entries) {
          common[section]![e.finalSavedInput] = (common[section]![e.finalSavedInput] ?? 0) + 1;
          hourTotals[section] = hourTotals[section]! + e.addedAt.hour + (e.addedAt.minute / 60.0);
          hourCounts[section] = hourCounts[section]! + 1;
        }

        final prot = entries.fold<double>(0, (sum, e) => sum + e.protMid);
        if (section == MealSection.breakfast) {
          breakfastProtein += prot;
          breakfastDays++;
        } else if (section == MealSection.lunch) {
          lunchProtein += prot;
          lunchDays++;
        } else if (section == MealSection.dinner) {
          dinnerProtein += prot;
          dinnerDays++;
        }
      }
    }

    return MealPatternSnapshot(
      commonFoodsBySection: {
        for (final s in MealSection.values)
          s: (common[s]!.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .take(3)
              .map((e) => e.key)
              .toList(),
      },
      averageMealHourBySection: {
        for (final s in MealSection.values)
          s: hourCounts[s]! == 0 ? 0 : hourTotals[s]! / hourCounts[s]!,
      },
      breakfastProteinAverage: breakfastDays == 0 ? 0 : breakfastProtein / breakfastDays,
      lunchProteinAverage: lunchDays == 0 ? 0 : lunchProtein / lunchDays,
      dinnerProteinAverage: dinnerDays == 0 ? 0 : dinnerProtein / dinnerDays,
      tendsToMissProteinEarly: breakfastDays > 2 && lunchDays > 2 &&
          ((breakfastProtein / breakfastDays) + (lunchProtein / lunchDays)) < 32,
      daysLogged: days,
    );
  }
}