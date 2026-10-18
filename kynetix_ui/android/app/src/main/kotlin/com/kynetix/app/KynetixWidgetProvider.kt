package com.kynetix.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Kynetix home-screen widget ("Carbon & Paper").
 *
 * Data comes from lib/services/widget_service.dart as JSON under the
 * SharedPreferences key `flutter.widget_data_v1`. Every render compares the
 * payload's `date_key` with today's local date, so the widget never shows
 * yesterday's numbers: after midnight it falls back to the payload's
 * `next_day` target with nothing eaten, or to a calm "Open Kynetix" state.
 *
 * One 2x2 size: [WidgetRings] draws two flat concentric rings (calories,
 * protein) on a transparent canvas with what is left in the middle.
 */
class KynetixWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
        scheduleMidnightUpdate(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        updateAppWidget(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onEnabled(context: Context) {
        scheduleMidnightUpdate(context)
    }

    override fun onDisabled(context: Context) {
        try {
            context.getSystemService(AlarmManager::class.java)?.cancel(midnightIntent(context))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel midnight update: ", e)
        }
    }

    /** What one day looks like on the widget. */
    data class DayState(
        val caloriesEaten: Int,
        val caloriesTarget: Int,
        val proteinEaten: Int,
        val proteinTarget: Int,
        val isTrainingDay: Boolean,
        val label: String,
        /** Targets are from the last known plan; the app hasn't run for a while. */
        val stale: Boolean = false,
    )

    companion object {
        private const val TAG = "KynetixWidgetProvider"
        private const val PREFS = "FlutterSharedPreferences"
        private const val DATA_KEY = "flutter.widget_data_v1"

        const val ACTION_OPEN_NUTRITION = "com.kynetix.app.ACTION_OPEN_NUTRITION"

        /** Intent extra the "Log meal" pill adds to the launch intent. */
        const val EXTRA_KYNETIX_ACTION = "kynetix_action"
        const val KYNETIX_ACTION_LOG_MEAL = "log_meal"

        private const val REQUEST_OPEN = 0
        private const val REQUEST_LOG_MEAL = 1 // retired with the 4x4 pill; kept so the code is not reused
        private const val REQUEST_MIDNIGHT = 1001

        private const val MIDNIGHT_WINDOW_MS = 10 * 60 * 1000L

        // ── State ────────────────────────────────────────────────────────────

        /** `yyyy-MM-dd` in ASCII digits, matching Dart's date keys. */
        fun todayKey(now: Date = Date()): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now)

        /**
         * Resolves what to show for [todayKey], or null for the
         * "Open Kynetix" state. Never returns another day's eaten numbers and
         * never invents a target.
         */
        fun resolveState(json: String?, todayKey: String): DayState? {
            if (json.isNullOrBlank()) return null
            val obj = try { JSONObject(json) } catch (e: Exception) { return null }

            val dataDay = obj.optString("date_key", obj.optString("last_update_date", ""))
            if (dataDay == todayKey) {
                val calTarget = obj.cleanInt("calories_target")
                val proTarget = obj.cleanInt("protein_target")
                if (calTarget == null || calTarget <= 0 || proTarget == null || proTarget <= 0) return null
                return DayState(
                    caloriesEaten = (obj.cleanInt("calories_consumed") ?: 0).coerceAtLeast(0),
                    caloriesTarget = calTarget,
                    proteinEaten = (obj.cleanInt("protein_consumed") ?: 0).coerceAtLeast(0),
                    proteinTarget = proTarget,
                    isTrainingDay = obj.optBoolean("is_training_day", false),
                    label = obj.optString("day_label", ""),
                )
            }

            // The app has not run today. Nothing has been logged on this phone
            // since, so today starts from zero against today's planned target
            // (the payload carries the week ahead).
            fun fromDay(day: JSONObject?, stale: Boolean): DayState? {
                if (day == null) return null
                val calTarget = day.cleanInt("calories_target")
                val proTarget = day.cleanInt("protein_target")
                if (calTarget == null || calTarget <= 0 || proTarget == null || proTarget <= 0) return null
                return DayState(
                    caloriesEaten = 0,
                    caloriesTarget = calTarget,
                    proteinEaten = 0,
                    proteinTarget = proTarget,
                    isTrainingDay = day.optBoolean("is_training_day", false),
                    label = day.optString("day_label", ""),
                    stale = stale,
                )
            }
            val next = obj.optJSONObject("next_day")
            if (next != null && next.optString("date_key", "") == todayKey) return fromDay(next, false)
            val days = obj.optJSONArray("days")
            if (days != null) {
                for (i in 0 until days.length()) {
                    val d = days.optJSONObject(i) ?: continue
                    if (d.optString("date_key", "") == todayKey) return fromDay(d, false)
                }
            }
            // Over a week without the app: keep showing the last plan rather
            // than a blank dial, and say it may be out of date.
            if (dataDay.isNotEmpty() && dataDay < todayKey) return fromDay(obj, true)
            return null
        }

        private fun JSONObject.cleanInt(key: String): Int? {
            if (!has(key) || isNull(key)) return null
            val d = optDouble(key, Double.NaN)
            if (d.isNaN() || d.isInfinite()) return null
            return d.roundToInt()
        }

        /** "Push Day" -> "Push day"; engine bookkeeping labels -> plain day type. */
        fun dayName(label: String, isTrainingDay: Boolean): String {
            val generic = setOf("", "Default", "Manual Override", "Saved Target", "Training Day", "Rest Day")
            val trimmed = label.trim()
            if (trimmed in generic) return if (isTrainingDay) "Training day" else "Rest day"
            return if (trimmed.endsWith(" Day")) trimmed.dropLast(4) + " day" else trimmed
        }

        private fun fmt(n: Int): String = String.format(Locale.US, "%,d", n)

        // ── Rendering ────────────────────────────────────────────────────────

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle? = null
        ) {
            try {
                val views = RemoteViews(context.packageName, R.layout.kynetix_widget_2x2)
                bindClicks(context, views)

                val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(DATA_KEY, null)
                val state = resolveState(json, todayKey())

                if (state == null) {
                    showEmpty(context, views)
                } else {
                    bindState(context, views, state)
                }
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget error: ", e)
                try {
                    val fallback = RemoteViews(context.packageName, R.layout.kynetix_widget_2x2)
                    bindClicks(context, fallback)
                    showEmpty(context, fallback)
                    appWidgetManager.updateAppWidget(appWidgetId, fallback)
                } catch (ex: Exception) {
                    Log.e(TAG, "Fatal widget fallback update failure: ", ex)
                }
            }
        }

        private fun launchIntent(context: Context, extra: String?): Intent =
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                action = ACTION_OPEN_NUTRITION
                if (extra != null) putExtra(EXTRA_KYNETIX_ACTION, extra)
            }

        private fun bindClicks(context: Context, views: RemoteViews) {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(context, REQUEST_OPEN, launchIntent(context, null), flags)
            )
        }

        private const val SIZE_PX = 480

        private fun showEmpty(context: Context, views: RemoteViews) {
            views.setImageViewBitmap(R.id.widget_dial, WidgetRings.empty(context, SIZE_PX))
            views.setContentDescription(R.id.widget_root, "Kynetix. Open Kynetix to see what is left today.")
        }

        private fun bindState(context: Context, views: RemoteViews, s: DayState) {
            views.setImageViewBitmap(R.id.widget_dial, WidgetRings.rings(context, SIZE_PX, s))
            val calLeft = s.caloriesTarget - s.caloriesEaten
            val proLeft = s.proteinTarget - s.proteinEaten
            val calSpoken = if (calLeft < 0) "${fmt(abs(calLeft))} kcal over" else "${fmt(calLeft)} kcal left"
            val proSpoken = if (proLeft < 0) "${fmt(abs(proLeft))} grams protein over" else "${fmt(proLeft)} grams protein left"
            views.setContentDescription(
                R.id.widget_root,
                "Kynetix. $calSpoken of ${fmt(s.caloriesTarget)}. $proSpoken. ${dayName(s.label, s.isTrainingDay)}."
            )
        }

        // ── Midnight refresh ─────────────────────────────────────────────────

        private fun midnightIntent(context: Context): PendingIntent {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, KynetixWidgetProvider::class.java))
            val intent = Intent(context, KynetixWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            return PendingIntent.getBroadcast(
                context,
                REQUEST_MIDNIGHT,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        /**
         * Inexact, non-waking alarm a few seconds after the next local
         * midnight (no exact-alarm permission). If the phone is asleep it
         * fires when the screen wakes, which is when the widget is seen.
         */
        fun scheduleMidnightUpdate(context: Context) {
            try {
                val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
                val next = Calendar.getInstance().apply {
                    add(Calendar.DAY_OF_YEAR, 1)
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 5)
                    set(Calendar.MILLISECOND, 0)
                }
                alarmManager.setWindow(
                    AlarmManager.RTC,
                    next.timeInMillis,
                    MIDNIGHT_WINDOW_MS,
                    midnightIntent(context)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule midnight update: ", e)
            }
        }
    }
}
