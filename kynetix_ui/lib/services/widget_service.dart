import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/day_log.dart';
import '../screens/onboarding_screen.dart' show currentUserProfile;
import '../services/workout_service.dart';
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
      final profile = currentUserProfile;
      if (profile == null) {
        debugPrint('[WidgetService] Profile not found, clearing widget data');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('widget_data_v1');
        await _channel.invokeMethod('updateWidget');
        return;
      }

      // 3. Targets (mirroring the dashboard's _effectiveDayTarget exactly)
      final ws = WorkoutService.instance;
      final session = ws.sessionFor(now);
      final splitDay = ws.splitDayFor(now);
      final gymDay = log.gymDay;

      final bool isGymDay;
      if (gymDay != null) {
        isGymDay = gymDay.didGym || (session?.isEmpty == false);
      } else {
        final splitIsTraining = splitDay != null && !splitDay.isRestDay;
        isGymDay = splitIsTraining || (session?.isEmpty == false);
      }

      final String? workoutTypeName;
      if (session != null && !session.isEmpty && session.splitDayName.isNotEmpty) {
        workoutTypeName = session.splitDayName;
      } else if (gymDay?.workoutType != null) {
        workoutTypeName = gymDay!.workoutType!.displayName;
      } else if (gymDay?.splitDayName != null) {
        workoutTypeName = gymDay!.splitDayName;
      } else if (splitDay != null && !splitDay.isRestDay) {
        workoutTypeName = splitDay.name;
      } else {
        workoutTypeName = null;
      }

      final targetDay = NutritionTargetEngine().dayTarget(
        profile,
        isGymDay: isGymDay,
        health: null, // Health Connect steps cached on profile if synced
        session: session,
        workoutTypeName: workoutTypeName,
        targetCaloriesOverride: gymDay?.targetCaloriesOverride,
        carryForwardAdjustment: log.carryForwardAdjustment,
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
