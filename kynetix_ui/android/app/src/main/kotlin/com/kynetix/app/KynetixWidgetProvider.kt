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
 * Four sizes, each its own entry in the widget picker: 2x2 (this class),
 * 4x2, 2x4 and 4x4 (the subclasses below). All are transparent;
 * [WidgetRings] draws the content as one bitmap per size, with small dark
 * plates behind the text.
 */
open class KynetixWidgetProvider : AppWidgetProvider() {

    /** Which drawing this provider's widgets get. */
    open val form: WidgetRings.Form = WidgetRings.Form.SQUARE

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH_ALL) {
            refreshAll(context)
            scheduleMidnightUpdate(context)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId, form)
        }
        scheduleMidnightUpdate(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        updateAppWidget(context, appWidgetManager, appWidgetId, form)
    }

    override fun onEnabled(context: Context) {
        scheduleMidnightUpdate(context)
    }

    override fun onDisabled(context: Context) {
        // Another size may still be on the home screen.
        if (allIds(context).isNotEmpty()) return
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
        // Carbs, fat and fiber (payload v3). A target of 0 means the payload
        // did not carry it, and the widget leaves that macro out.
        val carbsEaten: Int = 0,
        val carbsTarget: Int = 0,
        val fatEaten: Int = 0,
        val fatTarget: Int = 0,
        val fiberEaten: Int = 0,
        val fiberTarget: Int = 0,
    )

    companion object {
        private const val TAG = "KynetixWidgetProvider"
        private const val PREFS = "FlutterSharedPreferences"
        private const val DATA_KEY = "flutter.widget_data_v1"

        const val ACTION_OPEN_NUTRITION = "com.kynetix.app.ACTION_OPEN_NUTRITION"
        const val ACTION_REFRESH_ALL = "com.kynetix.app.ACTION_WIDGET_REFRESH_ALL"

        /** Every widget class, with the drawing each one uses. */
        private val providers = listOf(
            KynetixWidgetProvider::class.java to WidgetRings.Form.SQUARE,
            KynetixWidgetWide::class.java to WidgetRings.Form.WIDE,
            KynetixWidgetTall::class.java to WidgetRings.Form.TALL,
            KynetixWidgetLarge::class.java to WidgetRings.Form.LARGE,
        )

        private fun allIds(context: Context): List<Int> {
            val m = AppWidgetManager.getInstance(context)
            return providers.flatMap { (cls, _) -> m.getAppWidgetIds(ComponentName(context, cls)).toList() }
        }

        /** Redraws every Kynetix widget of every size. */
        fun refreshAll(context: Context) {
            val m = AppWidgetManager.getInstance(context)
            for ((cls, form) in providers) {
                for (id in m.getAppWidgetIds(ComponentName(context, cls))) {
                    updateAppWidget(context, m, id, form)
                }
            }
        }

        /** Intent extra the "Log meal" pill adds to the launch intent. */
        const val EXTRA_KYNETIX_ACTION = "kynetix_action"
        const val KYNETIX_ACTION_LOG_MEAL = "log_meal"

        private const val REQUEST_OPEN = 0
        private const val REQUEST_LOG_MEAL = 1
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
                    carbsEaten = obj.eaten("carbs_consumed"),
                    carbsTarget = obj.target("carbs_target"),
                    fatEaten = obj.eaten("fat_consumed"),
                    fatTarget = obj.target("fat_target"),
                    fiberEaten = obj.eaten("fiber_consumed"),
                    fiberTarget = obj.target("fiber_target"),
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
                    carbsTarget = day.target("carbs_target"),
                    fatTarget = day.target("fat_target"),
                    fiberTarget = day.target("fiber_target"),
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

        private fun JSONObject.eaten(key: String): Int = (cleanInt(key) ?: 0).coerceAtLeast(0)

        private fun JSONObject.target(key: String): Int = (cleanInt(key) ?: 0).coerceAtLeast(0)

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
            form: WidgetRings.Form = WidgetRings.Form.SQUARE,
        ) {
            try {
                val views = viewsFor(context, form)
                val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(DATA_KEY, null)
                val state = resolveState(json, todayKey())
                val (w, h) = contentDp(context, appWidgetManager, appWidgetId, form)
                views.setImageViewBitmap(R.id.widget_dial, WidgetRings.render(context, form, state, w, h))
                views.setContentDescription(R.id.widget_root, spoken(state))
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget error: ", e)
                try {
                    val fallback = viewsFor(context, form)
                    val (w, h) = contentDp(context, appWidgetManager, appWidgetId, form)
                    fallback.setImageViewBitmap(R.id.widget_dial, WidgetRings.render(context, form, null, w, h))
                    appWidgetManager.updateAppWidget(appWidgetId, fallback)
                } catch (ex: Exception) {
                    Log.e(TAG, "Fatal widget fallback update failure: ", ex)
                }
            }
        }


        /** Layout padding around the drawing (kynetix_widget_*.xml), in dp. */
        private const val LAYOUT_PAD_DP = 4f
        /** Log meal pill height plus its top margin, in dp. */
        private const val PILL_DP = 34f + 8f

        /**
         * The drawing's area in dp: the size the launcher gives the widget
         * (portrait uses min width and max height, as launchers report it)
         * less the layout padding and, on 2x4 and 4x4, the Log meal pill.
         */
        private fun contentDp(context: Context, m: AppWidgetManager, id: Int, form: WidgetRings.Form): Pair<Float, Float> {
            var (w, h) = WidgetRings.defaultDp(form)
            try {
                val o = m.getAppWidgetOptions(id)
                val portrait = context.resources.configuration.orientation != android.content.res.Configuration.ORIENTATION_LANDSCAPE
                val ow = o.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
                val oh = o.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
                if (ow > 0 && oh > 0) {
                    w = ow - 2 * LAYOUT_PAD_DP
                    h = oh - 2 * LAYOUT_PAD_DP
                    if (form == WidgetRings.Form.TALL || form == WidgetRings.Form.LARGE) h -= PILL_DP
                }
            } catch (e: Exception) {
                Log.e(TAG, "Widget size lookup failed: ", e)
            }
            return w.coerceAtLeast(60f) to h.coerceAtLeast(60f)
        }

        private fun viewsFor(context: Context, form: WidgetRings.Form): RemoteViews {
            val layout = when (form) {
                WidgetRings.Form.SQUARE -> R.layout.kynetix_widget_2x2
                WidgetRings.Form.WIDE -> R.layout.kynetix_widget_4x2
                WidgetRings.Form.TALL -> R.layout.kynetix_widget_2x4
                WidgetRings.Form.LARGE -> R.layout.kynetix_widget_4x4
            }
            val views = RemoteViews(context.packageName, layout)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(context, REQUEST_OPEN, launchIntent(context, null), flags)
            )
            if (form == WidgetRings.Form.TALL || form == WidgetRings.Form.LARGE) {
                // Distinct request code: extras alone do not make a distinct PendingIntent.
                views.setOnClickPendingIntent(
                    R.id.widget_log_meal,
                    PendingIntent.getActivity(context, REQUEST_LOG_MEAL, launchIntent(context, KYNETIX_ACTION_LOG_MEAL), flags)
                )
            }
            return views
        }

        private fun launchIntent(context: Context, extra: String?): Intent =
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                action = ACTION_OPEN_NUTRITION
                if (extra != null) putExtra(EXTRA_KYNETIX_ACTION, extra)
            }

        private fun spoken(s: DayState?): String {
            if (s == null) return "Kynetix. Open Kynetix to see what is left today."
            val calLeft = s.caloriesTarget - s.caloriesEaten
            val proLeft = s.proteinTarget - s.proteinEaten
            val calSpoken = if (calLeft < 0) "${fmt(abs(calLeft))} kcal over" else "${fmt(calLeft)} kcal left"
            val proSpoken = if (proLeft < 0) "${fmt(abs(proLeft))} grams protein over" else "${fmt(proLeft)} grams protein left"
            val macros = listOfNotNull(
                if (s.carbsTarget > 0) "carbs ${s.carbsEaten} of ${s.carbsTarget} grams" else null,
                if (s.fatTarget > 0) "fat ${s.fatEaten} of ${s.fatTarget} grams" else null,
                if (s.fiberTarget > 0) "fiber ${s.fiberEaten} of ${s.fiberTarget} grams" else null,
            )
            val macroSpoken = if (macros.isEmpty()) "" else " Eaten: ${macros.joinToString(", ")}."
            return "Kynetix. $calSpoken of ${fmt(s.caloriesTarget)}. $proSpoken.$macroSpoken ${dayName(s.label, s.isTrainingDay)}."
        }

        // ── Midnight refresh ─────────────────────────────────────────────────

        private fun midnightIntent(context: Context): PendingIntent {
            val intent = Intent(context, KynetixWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_ALL
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

/** 4x2: rings on the left, carbs, fat and fiber on the right. */
class KynetixWidgetWide : KynetixWidgetProvider() {
    override val form = WidgetRings.Form.WIDE
}

/** 2x4: rings on top, carbs, fat and fiber under them, and Log meal. */
class KynetixWidgetTall : KynetixWidgetProvider() {
    override val form = WidgetRings.Form.TALL
}

/** 4x4: rings, eaten of target, carbs, fat and fiber, and Log meal. */
class KynetixWidgetLarge : KynetixWidgetProvider() {
    override val form = WidgetRings.Form.LARGE
}
