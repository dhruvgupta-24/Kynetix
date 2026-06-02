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
                val opts = options ?: try {
                    appWidgetManager.getAppWidgetOptions(appWidgetId)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to get app widget options: ", e)
                    null
                }

                val minWidth = opts?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0
                val minHeight = opts?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0

                Log.d(TAG, "updateAppWidget: id=$appWidgetId size=${minWidth}x${minHeight}")

                // Determine layout dynamically based on options dimensions
                val layoutResId = when {
                    minWidth > 0 && minWidth < 180 -> R.layout.kynetix_widget_2x2
                    minWidth >= 180 && ((minHeight > 0 && minHeight < 180) || minHeight == 0) -> R.layout.kynetix_widget_4x2
                    minWidth >= 180 && minHeight >= 180 -> R.layout.kynetix_widget_4x4
                    else -> R.layout.kynetix_widget_2x2 // Default/fallback
                }

                val views = RemoteViews(context.packageName, layoutResId)

                // Setup click intent to open Kynetix app & switch to Nutrition tab
                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    action = "com.kynetix.app.ACTION_OPEN_NUTRITION"
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 
                    0, 
                    intent, 
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

                // Read SharedPreferences
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val dataStr = prefs.getString("flutter.widget_data_v1", null)

                if (dataStr == null) {
                    // Fresh install / empty state fallback
                    views.setViewVisibility(R.id.widget_content_layout, View.GONE)
                    views.setViewVisibility(R.id.widget_fallback_text, View.VISIBLE)
                    if (layoutResId != R.layout.kynetix_widget_2x2) {
                        views.setViewVisibility(R.id.widget_header_layout, View.GONE)
                        views.setViewVisibility(R.id.widget_details_layout, View.GONE)
                    }
                    if (layoutResId == R.layout.kynetix_widget_2x2 || layoutResId == R.layout.kynetix_widget_4x2) {
                        views.setViewVisibility(R.id.widget_timestamp_layout, View.GONE)
                    }
                    appWidgetManager.updateAppWidget(appWidgetId, views)
                    return
                }

                val json = JSONObject(dataStr)
                val lastUpdateDate = json.optString("last_update_date", "")
                val lastUpdateTime = json.optString("last_update_time", "--:--")

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

                // Allow ratios to exceed 1.0f (up to 2.0f) to render over-target highlight arc
                val calRatio = if (cleanCaloriesTarget > 0.0) {
                    (caloriesConsumed / cleanCaloriesTarget).toFloat().coerceIn(0f, 2f)
                } else {
                    0f
                }
                val proRatio = if (cleanProteinTarget > 0.0) {
                    (proteinConsumed / cleanProteinTarget).toFloat().coerceIn(0f, 2f)
                } else {
                    0f
                }

                // Bind view elements based on layout size
                if (layoutResId == R.layout.kynetix_widget_2x2) {
                    views.setViewVisibility(R.id.widget_content_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_timestamp_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_fallback_text, View.GONE)

                    val bitmap = drawConcentricRings(calRatio, proRatio, caloriesConsumed > cleanCaloriesTarget, proteinConsumed > cleanProteinTarget, isLarge = false)
                    views.setImageViewBitmap(R.id.widget_progress_rings, bitmap)

                    views.setTextViewText(R.id.widget_calories_value, "${finalCaloriesRemaining.toInt()}")
                    views.setTextViewText(R.id.widget_protein_value, "${finalProteinRemaining.toInt()}g")
                    views.setTextViewText(R.id.widget_timestamp, "Updated $lastUpdateTime")
                } 
                else if (layoutResId == R.layout.kynetix_widget_4x2) {
                    views.setViewVisibility(R.id.widget_content_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_timestamp_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_fallback_text, View.GONE)

                    val calBitmap = drawSingleRing(calRatio, caloriesConsumed > cleanCaloriesTarget, "#FF6B35")
                    val proBitmap = drawSingleRing(proRatio, proteinConsumed > cleanProteinTarget, "#52B788")
                    views.setImageViewBitmap(R.id.widget_calories_ring, calBitmap)
                    views.setImageViewBitmap(R.id.widget_protein_ring, proBitmap)

                    views.setTextViewText(R.id.widget_calories_center_value, "${finalCaloriesRemaining.toInt()}")
                    views.setTextViewText(R.id.widget_protein_center_value, "${finalProteinRemaining.toInt()}g")

                    views.setTextViewText(R.id.widget_calories_remaining, "${finalCaloriesRemaining.toInt()} kcal left")
                    views.setTextViewText(R.id.widget_calories_consumed_target, "${caloriesConsumed.toInt()} / ${cleanCaloriesTarget.toInt()} consumed")

                    views.setTextViewText(R.id.widget_protein_remaining, "${finalProteinRemaining.toInt()}g left")
                    views.setTextViewText(R.id.widget_protein_consumed_target, "${proteinConsumed.toInt()} / ${cleanProteinTarget.toInt()} consumed")

                    views.setTextViewText(R.id.widget_timestamp, "Updated $lastUpdateTime")
                } 
                else { // 4x4
                    views.setViewVisibility(R.id.widget_content_layout, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_fallback_text, View.GONE)

                    val bitmap = drawConcentricRings(calRatio, proRatio, caloriesConsumed > cleanCaloriesTarget, proteinConsumed > cleanProteinTarget, isLarge = true)
                    views.setImageViewBitmap(R.id.widget_progress_rings, bitmap)

                    views.setTextViewText(R.id.widget_calories_value, "${finalCaloriesRemaining.toInt()}")
                    views.setTextViewText(R.id.widget_protein_value, "${finalProteinRemaining.toInt()}g")

                    views.setTextViewText(R.id.widget_calories_remaining, "${finalCaloriesRemaining.toInt()} kcal remaining")
                    views.setTextViewText(R.id.widget_calories_consumed_target, "${caloriesConsumed.toInt()} / ${cleanCaloriesTarget.toInt()} kcal")

                    views.setTextViewText(R.id.widget_protein_remaining, "${finalProteinRemaining.toInt()}g remaining")
                    views.setTextViewText(R.id.widget_protein_consumed_target, "${proteinConsumed.toInt()} / ${cleanProteinTarget.toInt()} g")

                    views.setTextViewText(R.id.widget_timestamp, "Updated $lastUpdateTime")
                }

                appWidgetManager.updateAppWidget(appWidgetId, views)

            } catch (e: Exception) {
                Log.e(TAG, "updateAppWidget error: ", e)
                try {
                    val fallbackResId = when {
                        options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0 >= 180 -> {
                            if (options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0 >= 180) {
                                R.layout.kynetix_widget_4x4
                            } else {
                                R.layout.kynetix_widget_4x2
                            }
                        }
                        else -> R.layout.kynetix_widget_2x2
                    }
                    val fallbackViews = RemoteViews(context.packageName, fallbackResId)
                    fallbackViews.setViewVisibility(R.id.widget_content_layout, View.GONE)
                    fallbackViews.setViewVisibility(R.id.widget_fallback_text, View.VISIBLE)
                    if (fallbackResId != R.layout.kynetix_widget_2x2) {
                        fallbackViews.setViewVisibility(R.id.widget_header_layout, View.GONE)
                        fallbackViews.setViewVisibility(R.id.widget_details_layout, View.GONE)
                    }
                    if (fallbackResId == R.layout.kynetix_widget_2x2 || fallbackResId == R.layout.kynetix_widget_4x2) {
                        fallbackViews.setViewVisibility(R.id.widget_timestamp_layout, View.GONE)
                    }
                    appWidgetManager.updateAppWidget(appWidgetId, fallbackViews)
                } catch (ex: Exception) {
                    Log.e(TAG, "Fatal widget fallback update failure: ", ex)
                }
            }
        }

        private fun drawSingleRing(
            ratio: Float,
            overTarget: Boolean,
            colorHex: String
        ): Bitmap {
            val size = 150
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.TRANSPARENT)

            val center = size / 2f
            val radius = size * 0.40f
            val stroke = size * 0.12f
            val rect = RectF(center - radius, center - radius, center + radius, center + radius)

            val paint = Paint().apply {
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
                isAntiAlias = true
            }

            // Draw track
            paint.color = Color.parseColor("#2A2A3C")
            paint.strokeWidth = stroke
            canvas.drawArc(rect, -90f, 360f, false, paint)

            // Primary progress color
            val baseColor = Color.parseColor(colorHex)
            paint.color = baseColor

            if (overTarget) {
                // If over target, draw full 360 degree circle of base color
                canvas.drawArc(rect, -90f, 360f, false, paint)
                
                // Then overlay the excess arc in gold/yellow
                val excessRatio = (ratio - 1.0f).coerceAtMost(1.0f)
                paint.color = Color.parseColor("#F59E0B")
                canvas.drawArc(rect, -90f, excessRatio * 360f, false, paint)
            } else {
                canvas.drawArc(rect, -90f, ratio * 360f, false, paint)
            }

            return bitmap
        }

        private fun drawConcentricRings(
            calRatio: Float,
            proRatio: Float,
            calOverTarget: Boolean,
            proOverTarget: Boolean,
            isLarge: Boolean
        ): Bitmap {
            val size = if (isLarge) 400 else 300
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawColor(Color.TRANSPARENT)

            val center = size / 2f

            val paint = Paint().apply {
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
                isAntiAlias = true
            }

            // 1. Draw Calories Ring (Outer)
            val outerRadius = if (isLarge) size * 0.41f else size * 0.44f
            val outerStroke = size * 0.09f
            val outerRect = RectF(center - outerRadius, center - outerRadius, center + outerRadius, center + outerRadius)

            // Outer Track
            paint.color = Color.parseColor("#2A2A3C")
            paint.strokeWidth = outerStroke
            canvas.drawArc(outerRect, -90f, 360f, false, paint)

            // Outer Progress
            paint.color = Color.parseColor("#FF6B35")
            if (calOverTarget) {
                canvas.drawArc(outerRect, -90f, 360f, false, paint)
                
                // Draw gold over-target overlay
                val excessRatio = (calRatio - 1.0f).coerceAtMost(1.0f)
                paint.color = Color.parseColor("#F59E0B")
                canvas.drawArc(outerRect, -90f, excessRatio * 360f, false, paint)
            } else {
                canvas.drawArc(outerRect, -90f, calRatio * 360f, false, paint)
            }

            // 2. Draw Protein Ring (Inner)
            val innerRadius = if (isLarge) size * 0.29f else size * 0.31f
            val innerStroke = size * 0.075f
            val innerRect = RectF(center - innerRadius, center - innerRadius, center + innerRadius, center + innerRadius)

            // Inner Track
            paint.color = Color.parseColor("#2A2A3C")
            paint.strokeWidth = innerStroke
            canvas.drawArc(innerRect, -90f, 360f, false, paint)

            // Inner Progress
            paint.color = Color.parseColor("#52B788")
            if (proOverTarget) {
                canvas.drawArc(innerRect, -90f, 360f, false, paint)
                
                // Draw gold over-target overlay
                val excessRatio = (proRatio - 1.0f).coerceAtMost(1.0f)
                paint.color = Color.parseColor("#F59E0B")
                canvas.drawArc(innerRect, -90f, excessRatio * 360f, false, paint)
            } else {
                canvas.drawArc(innerRect, -90f, proRatio * 360f, false, paint)
            }

            return bitmap
        }
    }
}
