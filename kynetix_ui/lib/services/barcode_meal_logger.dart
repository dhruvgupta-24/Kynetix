import '../models/barcode_product.dart';
import '../models/day_log.dart';
import 'kyno_context_service.dart';
import 'meal_memory.dart';
import 'persistence_service.dart';
import 'analytics_service.dart';

/// Logs an exact amount of a scanned product straight to a day and section.
///
/// Uses the same path as every other meal add (AddMealScreen, Quick Add):
/// the in-memory day log first (source of truth), then MealMemory, then
/// [PersistenceService.saveDay], whose post-save effects run the cloud sync.
/// Adds need no tombstone; tombstones only record removals and replaces.
class BarcodeMealLogger {
  BarcodeMealLogger._();

  /// Adds [grams] of [product] to [section] on [date] and returns the entry.
  static MealEntry log({
    required BarcodeProduct product,
    required double grams,
    required DateTime date,
    required MealSection section,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final result = product.resultForAmount(grams, now: at);
    final text = product.entryText(grams);

    final entry = MealEntry(
      rawInput: text,
      result: result,
      addedAt: at,
      section: section,
      dayOfWeek: date.weekday,
      parsedFoods: [product.name],
      finalSavedInput: text,
      // A label is not an estimate; a user-confirmed label is the user's own
      // numbers.
      userCorrected: product.source.isUserConfirmed,
    );

    logFor(date).add(section, entry);

    // Remembered by the full text ("40 g Parle-G …") and by the product name,
    // so typing either into the composer finds it next time.
    MealMemory.instance
        .store(
          text,
          result,
          finalSavedInput: text,
          canonicalMeal: product.name,
        )
        .ignore();

    PersistenceService.saveDay(date).ignore();
    PersistenceService.notifyLogsChanged();
    KynoContextService.instance.invalidate();
    AnalyticsService.instance.track('meal_logged', {'method': 'barcode', 'kcal_bucket': AnalyticsService.kcalBucket(entry.calMid)});
    return entry;
  }

  /// "Logged 40 g of Parle-G to Breakfast."
  static String toastFor(BarcodeProduct product, double grams, MealSection section) =>
      'Logged ${product.amountLabel(grams)} of ${product.name} to ${section.displayName}.';
}
