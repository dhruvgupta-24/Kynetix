import '../models/day_log.dart';
import '../models/nutrition_result.dart';
import '../ui/k_format.dart';
import 'analytics_service.dart';
import 'kyno_context_service.dart';
import 'meal_memory.dart';
import 'persistence_service.dart';

/// Logs a meal read from a photo straight to a day and section, after the
/// person tapped Log meal on the result panel (their confirmation).
///
/// Same path as every other meal add (AddMealScreen, barcode, Quick Add):
/// the in-memory day log first (the source of truth), then MealMemory, then
/// [PersistenceService.saveDay], whose post-save effects run the cloud sync.
/// Adds need no tombstone; tombstones only record removals and replaces.
class MealPhotoLogger {
  MealPhotoLogger._();

  /// Adds [result] (the pipeline's estimate of the photo, described by
  /// [text], e.g. "3 roti, 150 g dal tadka") to [section] on [date].
  static MealEntry log({
    required NutritionResult result,
    required String text,
    required DateTime date,
    required MealSection section,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final entry = MealEntry(
      rawInput: text,
      result: result,
      addedAt: at,
      section: section,
      dayOfWeek: date.weekday,
      parsedFoods: result.items.map((i) => i.name).toList(),
      finalSavedInput: text,
      // Kyno's estimate, confirmed with one tap: not the person's own numbers.
      userCorrected: false,
    );

    logFor(date).add(section, entry);

    // Typing the same text later finds these numbers again.
    MealMemory.instance
        .store(
          text,
          result,
          finalSavedInput: text,
          canonicalMeal: result.canonicalMeal,
        )
        .ignore();

    PersistenceService.saveDay(date).ignore();
    PersistenceService.notifyLogsChanged();
    KynoContextService.instance.invalidate();
    AnalyticsService.instance.track('meal_logged', {
      'method': 'photo',
      'kcal_bucket': AnalyticsService.kcalBucket(entry.calMid),
    });
    return entry;
  }

  /// "Logged to Lunch, 640 kcal."
  static String toastFor(MealEntry entry) =>
      'Logged to ${entry.section.displayName}, ${thousands(entry.calMid.round())} kcal.';
}
