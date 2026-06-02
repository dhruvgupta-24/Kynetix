package com.kynetix.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class KynetixWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        updateAppWidget(context, appWidgetManager, appWidgetId, newOptions)
    }

    companion object {
        private const val TAG = "KynetixWidgetProvider"

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle? = null
        ) {
            try {
                val views = RemoteViews(context.packageName, R.layout.kynetix_widget)

                // Setup click intent to open Kynetix app
                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 
                    0, 
                    intent, 
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                val opts = options ?: try {
                    appWidgetManager.getAppWidgetOptions(appWidgetId)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to get app widget options: ", e)
                    null
                }

                val minWidth = opts?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0
                val minHeight = opts?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0

                Log.d(TAG, "updateAppWidget: id=$appWidgetId size=${minWidth}x${minHeight}")

                // Read SharedPreferences
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val dataStr = prefs.getString("flutter.widget_data_v1", null)

                if (dataStr == null) {
                    // Fresh install / empty state fallback
                    views.setViewVisibility(R.id.widget_content_layout, View.GONE)
                    views.setViewVisibility(R.id.widget_fallback_text, View.VISIBLE)
                    appWidgetManager.updateAppWidget(appWidgetId, views)
                    return
                }

                views.setViewVisibility(R.id.widget_content_layout, View.VISIBLE)
                views.setViewVisibility(R.id.widget_fallback_text, View.GONE)

                val json = JSONObject(dataStr)
                val lastUpdateDate = json.optString("last_update_date", "")

                // Daily Rollover check
                val currentDate = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                val isNewDay = currentDate != lastUpdateDate

                var caloriesConsumed = if (isNewDay) 0.0 else json.optDouble("calories_consumed", 0.0)
                val caloriesTarget = json.optDouble("calories_target", 2000.0)
                var caloriesRemaining = if (isNewDay) caloriesTarget else json.optDouble("calories_remaining", caloriesTarget)

                var proteinConsumed = if (isNewDay) 0.0 else json.optDouble("protein_consumed", 0.0)
                val proteinTarget = json.optDouble("protein_target", 120.0)
                var proteinRemaining = if (isNewDay) proteinTarget else json.optDouble("protein_remaining", proteinTarget)

                // Clean NaN or Infinite values
                fun Double.clean(): Double = if (isNaN() || isInfinite()) 0.0 else this
                caloriesConsumed = caloriesConsumed.clean()
                val cleanCaloriesTarget = caloriesTarget.clean()
                caloriesRemaining = caloriesRemaining.clean()
                proteinConsumed = proteinConsumed.clean()
                val cleanProteinTarget = proteinTarget.clean()
                proteinRemaining = proteinRemaining.clean()

                // Clamp values just in case
                val finalCaloriesRemaining = if (caloriesRemaining < 0.0) 0.0 else caloriesRemaining
                val finalProteinRemaining = if (proteinRemaining < 0.0) 0.0 else proteinRemaining

                val calRatio = if (cleanCaloriesTarget > 0.0) {
                    (caloriesConsumed / cleanCaloriesTarget).toFloat().coerceIn(0f, 1f)
                } else {
                    0f
                }
                val proRatio = if (cleanProteinTarget > 0.0) {
                    (proteinConsumed / cleanProteinTarget).toFloat().coerceIn(0f, 1f)
                } else {
                    0f
                }

                // Draw circular progress rings
                val bitmap = drawMacroRings(calRatio, proRatio, caloriesConsumed > cleanCaloriesTarget, proteinConsumed > cleanProteinTarget)
                views.setImageViewBitmap(R.id.widget_progress_rings, bitmap)

                // Format text values
                val calRemainingText = "${finalCaloriesRemaining.toInt()} kcal left"
                val calConsumedTargetText = "${caloriesConsumed.toInt()} / ${cleanCaloriesTarget.toInt()} kcal"
                val proRemainingText = "${finalProteinRemaining.toInt()}g protein left"
                val proConsumedTargetText = "${proteinConsumed.toInt()} / ${cleanProteinTarget.toInt()} g protein"

                // Responsive layout adjustments
                // 2x2 widget size (minWidth < 180)
                if (minWidth > 0 && minWidth < 180) {
                    views.setViewVisibility(R.id.widget_header_layout, View.GONE)
                    views.setViewVisibility(R.id.widget_details_layout, View.GONE)
                    views.setViewVisibility(R.id.widget_center_text_layout, View.VISIBLE)
                    views.setTextViewText(R.id.widget_center_value, "${finalCaloriesRemaining.toInt()}")
                    views.setTextViewText(R.id.widget_center_label, "kcal left")
                } 
                // 4x2 widget size (minWidth >= 180, minHeight < 180)
                else if (minWidth >= 180 && ((minHeight > 0 && minHeight < 180) || minHeight == 0)) {
                    views.setViewVisibility(R.id.widget_header_layout, View.GONE)
                    views.setViewVisibility(R.id.widget_details_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_center_text_layout, View.GONE)

                    views.setTextViewText(R.id.widget_calories_remaining, calRemainingText)
                    views.setTextViewText(R.id.widget_calories_consumed_target, calConsumedTargetText)
                    views.setTextViewText(R.id.widget_protein_remaining, proRemainingText)
                    views.setTextViewText(R.id.widget_protein_consumed_target, proConsumedTargetText)
                } 
                // 4x4 or larger widget size
                else {
                    views.setViewVisibility(R.id.widget_header_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_details_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_center_text_layout, View.GONE)

                    val weekdayFormat = SimpleDateFormat("EEEE, d MMMM", Locale.getDefault())
                    views.setTextViewText(R.id.widget_date, weekdayFormat.format(Date()))

                    views.setTextViewText(R.id.widget_calories_remaining, calRemainingText)
                    views.setTextViewText(R.id.widget_calories_consumed_target, calConsumedTargetText)
                    views.setTextViewText(R.id.widget_protein_remaining, proRemainingText)
                    views.setTextViewText(R.id.widget_protein_consumed_target, proConsumedTargetText)
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)

            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget error: ", e)
                try {
                    val fallbackViews = RemoteViews(context.packageName, R.layout.kynetix_widget)
                    fallbackViews.setViewVisibility(R.id.widget_content_layout, View.GONE)
                    fallbackViews.setViewVisibility(R.id.widget_fallback_text, View.VISIBLE)
                    appWidgetManager.updateAppWidget(appWidgetId, fallbackViews)
                } catch (ex: Exception) {
                    Log.e(TAG, "Fatal widget fallback update failure: ", ex)
                }
            }
        }

        private fun drawMacroRings(
            calRatio: Float,
            proRatio: Float,
            calOverTarget: Boolean,
            proOverTarget: Boolean
        ): Bitmap {
            val size = 300
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.TRANSPARENT)

            val center = size / 2f

            // Colors matching Kynetix branding
            val calColor = Color.parseColor(if (calOverTarget) "#F59E0B" else "#FF6B35") // Orange or Yellow (over target)
            val proColor = Color.parseColor(if (proOverTarget) "#F59E0B" else "#52B788") // Green or Yellow (over target)

            // Paint configurations
            val paint = Paint().apply {
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
                isAntiAlias = true
            }

            // Draw Calories ring (Outer)
            val outerRadius = size * 0.40f
            val outerStroke = size * 0.08f
            val outerRect = RectF(center - outerRadius, center - outerRadius, center + outerRadius, center + outerRadius)

            // Track
            paint.color = Color.parseColor("#2A2A3C")
            paint.strokeWidth = outerStroke
            canvas.drawArc(outerRect, -90f, 360f, false, paint)

            // Progress Arc
            paint.color = calColor
            canvas.drawArc(outerRect, -90f, calRatio * 360f, false, paint)

            // Draw Protein ring (Inner)
            val innerRadius = size * 0.27f
            val innerStroke = size * 0.07f
            val innerRect = RectF(center - innerRadius, center - innerRadius, center + innerRadius, center + innerRadius)

            // Track
            paint.color = Color.parseColor("#2A2A3C")
            paint.strokeWidth = innerStroke
            canvas.drawArc(innerRect, -90f, 360f, false, paint)

            // Progress Arc
            paint.color = proColor
            canvas.drawArc(innerRect, -90f, proRatio * 360f, false, paint)

            return bitmap
        }
    }
}
