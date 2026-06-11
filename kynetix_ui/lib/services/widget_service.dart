import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_log.dart';
import 'profile_service.dart';
import '../services/nutrition_target_engine.dart';

class WidgetService {
  WidgetService._();

  static const _channel = MethodChannel('com.kynetix.app/widget');

  /// Recalculates today's consumed and target macros and saves them into the
  /// shared preferences under a unified JSON string for the widget.
  static Future<void> updateWidgetData() async {
    try {
      final now = DateTime.now();
      final log = logFor(now);

      // 1. Consumed values (using totalCaloriesMid / totalProteinMid)
      final consumedCalories = log.totalCaloriesMid;
      final consumedProtein = log.totalProteinMid;

      // 2. Profile
      final profile = ProfileService.instance.currentUserProfile;
      if (profile == null) {
        debugPrint('[WidgetService] Profile not found, clearing widget data');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('widget_data_v1');
        await _channel.invokeMethod('updateWidget');
        return;
      }

      // 3. Targets (using the canonical target engine)
      final targetDay = NutritionTargetEngine().effectiveTargetForDate(
        now,
        profile: profile,
      );

      final targetCalories = targetDay.calories;
      final targetProtein = targetDay.protein;

      final remainingCalories = (targetCalories - consumedCalories).clamp(0.0, double.infinity);
      final remainingProtein = (targetProtein - consumedProtein).clamp(0.0, double.infinity);

      // Build JSON payload
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final payload = {
        'last_update_date': dateStr,
        'last_update_time': timeStr,
        'calories_consumed': consumedCalories,
        'calories_target': targetCalories,
        'calories_remaining': remainingCalories,
        'protein_consumed': consumedProtein,
        'protein_target': targetProtein,
        'protein_remaining': remainingProtein,
      };

      final prefs = await SharedPreferences.getInstance();
      
      // Throttle: check if previous values for the same day are identical
      final oldJson = prefs.getString('widget_data_v1');
      if (oldJson != null) {
        try {
          final oldMap = jsonDecode(oldJson) as Map<String, dynamic>;
          if (oldMap['last_update_date'] == dateStr &&
              oldMap['calories_consumed'] == consumedCalories &&
              oldMap['calories_target'] == targetCalories &&
              oldMap['protein_consumed'] == consumedProtein &&
              oldMap['protein_target'] == targetProtein) {
            debugPrint('[WidgetService] Widget data unchanged, skipping update');
            return;
          }
        } catch (_) {}
      }

      await prefs.setString('widget_data_v1', jsonEncode(payload));

      // Trigger native widget refresh
      await _channel.invokeMethod('updateWidget');
      debugPrint('[WidgetService] Widget data updated successfully: $payload');
    } catch (e, stack) {
      debugPrint('[WidgetService] Failed to update widget data: $e\n$stack');
    }
  }
}
