package com.kynetix.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min

/**
 * The home-screen widget: two flat concentric rings on a transparent canvas,
 * calories outside, protein inside, with what is left in the middle. Dark
 * only, no disc, no bezel, no glow. The inside of the rings is a quiet dark
 * lens so the numbers stay legible on a bright wallpaper.
 */
object WidgetRings {

    private val CAL = Color.rgb(255, 106, 61)
    private val CAL_OVER = Color.rgb(255, 77, 109)
    private val PRO = Color.rgb(61, 220, 151)
    private val TRACK = Color.argb(110, 28, 26, 36)
    private val TRACK_LIFT = Color.argb(26, 255, 255, 255)
    private val LENS = Color.argb(150, 12, 11, 17)
    private val TEXT = Color.argb(245, 255, 255, 255)
    private val TEXT_DIM = Color.argb(160, 255, 255, 255)

    private val medium: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    @Volatile private var display: Typeface? = null

    private fun displayFace(context: Context): Typeface {
        display?.let { return it }
        val face = try {
            Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/inter_tight/InterTight-600.ttf")
        } catch (e: Exception) {
            Typeface.create("sans-serif", Typeface.BOLD)
        }
        display = face
        return face
    }

    private fun fmt(n: Int): String = String.format(Locale.US, "%,d", n)

    fun rings(context: Context, sizePx: Int, s: KynetixWidgetProvider.DayState): Bitmap {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val cx = sizePx / 2f
        val stroke = sizePx * 0.085f
        val gap = stroke * 0.32f
        val rOuter = sizePx / 2f - stroke / 2f - sizePx * 0.02f
        val rInner = rOuter - stroke - gap

        val calLeft = s.caloriesTarget - s.caloriesEaten
        val proLeft = s.proteinTarget - s.proteinEaten
        val calP = s.caloriesEaten.toFloat() / s.caloriesTarget.coerceAtLeast(1)
        val proP = s.proteinEaten.toFloat() / s.proteinTarget.coerceAtLeast(1)

        lens(c, cx, rInner - stroke / 2f - gap * 0.5f)
        ring(c, cx, rOuter, stroke, calP, if (calLeft < 0) CAL_OVER else CAL)
        ring(c, cx, rInner, stroke, proP, PRO)

        val face = displayFace(context)
        val inner = (rInner - stroke / 2f) * 2f
        val big = if (calLeft < 0) "+${fmt(abs(calLeft))}" else fmt(calLeft)
        val bigSize = fit(big, inner * 0.80f, inner * 0.34f, face)
        val base = cx + bigSize * 0.30f
        text(c, big, cx, base, bigSize, face, TEXT)
        val unit = if (calLeft < 0) "kcal over" else "kcal left"
        text(c, unit, cx, base - bigSize * 0.86f, inner * 0.10f, medium, TEXT_DIM)
        val pro = if (proLeft <= 0) "protein done" else "${fmt(proLeft)} g protein"
        text(c, pro, cx, base + inner * 0.15f, inner * 0.105f, medium, PRO)
        if (s.stale) {
            text(c, "open to refresh", cx, base + inner * 0.27f, inner * 0.08f, medium, TEXT_DIM)
        }
        return bmp
    }

    fun empty(context: Context, sizePx: Int): Bitmap {
        val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val cx = sizePx / 2f
        val stroke = sizePx * 0.085f
        val gap = stroke * 0.32f
        val rOuter = sizePx / 2f - stroke / 2f - sizePx * 0.02f
        val rInner = rOuter - stroke - gap
        lens(c, cx, rInner - stroke / 2f - gap * 0.5f)
        ring(c, cx, rOuter, stroke, 0f, CAL)
        ring(c, cx, rInner, stroke, 0f, PRO)
        val inner = (rInner - stroke / 2f) * 2f
        text(c, "Kynetix", cx, cx + inner * 0.03f, fit("Kynetix", inner * 0.7f, inner * 0.2f, displayFace(context)), displayFace(context), TEXT)
        text(c, "open to sync", cx, cx + inner * 0.16f, inner * 0.08f, medium, TEXT_DIM)
        return bmp
    }

    private fun lens(c: Canvas, cx: Float, r: Float) {
        c.drawCircle(cx, cx, r, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = LENS })
    }

    private fun ring(c: Canvas, cx: Float, r: Float, stroke: Float, progress: Float, color: Int) {
        val oval = RectF(cx - r, cx - r, cx + r, cx + r)
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            this.color = TRACK
        }
        c.drawCircle(cx, cx, r, track)
        track.color = TRACK_LIFT
        c.drawCircle(cx, cx, r, track)
        val p = min(progress, 1f)
        if (p <= 0f) return
        val full = p >= 1f
        val arc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = if (full) Paint.Cap.BUTT else Paint.Cap.ROUND
            this.color = color
        }
        c.drawArc(oval, -90f, if (full) 360f else maxOf(p * 360f, 4f), false, arc)
    }

    private fun fit(s: String, maxWidth: Float, maxSize: Float, face: Typeface): Float {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = face; textSize = maxSize }
        val w = p.measureText(s)
        return if (w <= maxWidth) maxSize else maxSize * maxWidth / w
    }

    /** Draws [s] centred on [cx] with its baseline at [baseline]. */
    private fun text(c: Canvas, s: String, cx: Float, baseline: Float, size: Float, face: Typeface, color: Int) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = face
            textSize = size
            this.color = color
            textAlign = Paint.Align.CENTER
            if (face != medium) letterSpacing = -0.04f
        }
        c.drawText(s, cx, baseline, p)
    }
}
