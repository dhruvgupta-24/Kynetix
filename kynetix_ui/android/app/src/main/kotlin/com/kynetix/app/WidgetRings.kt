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
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Draws every home-screen widget size as one bitmap on a transparent canvas:
 * two flat concentric rings (calories outside, protein inside) with a quiet
 * dark lens behind the numbers, and small dark translucent plates behind the
 * stat clusters, so text reads on any wallpaper without a full panel, glow or
 * shadow. Graphite palette.
 *
 * The bitmap is sized to the widget's real area in dp and every drawing
 * below works in dp (the canvas is scaled once), so a 12 dp label is 12 dp
 * on the home screen.
 */
object WidgetRings {

    enum class Form { SQUARE, WIDE, TALL, LARGE }

    private val CAL = Color.rgb(255, 106, 61)
    private val CAL_OVER = Color.rgb(255, 90, 110)
    private val PRO = Color.rgb(74, 222, 155)
    private val CARBS = Color.rgb(91, 149, 247)
    private val FAT = Color.rgb(255, 182, 72)
    private val FIBER = Color.rgb(157, 140, 255)
    private val TRACK = Color.argb(120, 30, 30, 34)
    private val TRACK_LIFT = Color.argb(30, 255, 255, 255)
    private val TRACK_ON_PLATE = Color.argb(40, 255, 255, 255)
    private val LENS = Color.argb(170, 10, 10, 11)
    private val PLATE = Color.argb(160, 10, 10, 11)
    private val PLATE_EDGE = Color.argb(20, 255, 255, 255)
    private val TEXT = Color.rgb(246, 246, 244)
    private val TEXT_SOFT = Color.rgb(207, 207, 212)

    /** Most pixels one widget bitmap may use (RemoteViews bitmap budget). */
    private const val MAX_PIXELS = 1_400_000f

    @Volatile private var numFace: Typeface? = null
    @Volatile private var labelFace: Typeface? = null

    private fun face(context: Context, path: String, fallback: Typeface): Typeface = try {
        Typeface.createFromAsset(context.assets, path)
    } catch (e: Exception) {
        fallback
    }

    private fun num(context: Context): Typeface =
        numFace ?: face(context, "flutter_assets/assets/fonts/inter_tight/InterTight-600.ttf", Typeface.create("sans-serif", Typeface.BOLD))
            .also { numFace = it }

    private fun label(context: Context): Typeface =
        labelFace ?: face(context, "flutter_assets/assets/fonts/inter/Inter-500.ttf", Typeface.create("sans-serif-medium", Typeface.NORMAL))
            .also { labelFace = it }

    private fun fmt(n: Int): String = String.format(Locale.US, "%,d", n)

    /** Drawing area in dp when the launcher does not report one. */
    fun defaultDp(form: Form): Pair<Float, Float> = when (form) {
        Form.SQUARE -> 170f to 170f
        Form.WIDE -> 360f to 170f
        Form.TALL -> 170f to 400f
        Form.LARGE -> 360f to 400f
    }

    fun render(
        context: Context,
        form: Form,
        s: KynetixWidgetProvider.DayState?,
        widthDp: Float = defaultDp(form).first,
        heightDp: Float = defaultDp(form).second,
    ): Bitmap {
        val w = widthDp.coerceAtLeast(48f)
        val h = heightDp.coerceAtLeast(48f)
        var u = context.resources.displayMetrics.density.coerceAtLeast(1f)
        val px = w * h * u * u
        if (px > MAX_PIXELS) u *= sqrt(MAX_PIXELS / px)
        val bmp = Bitmap.createBitmap((w * u).roundToInt().coerceAtLeast(1), (h * u).roundToInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.scale(u, u)
        val d = s?.let { Day(it) }
        when (form) {
            Form.SQUARE -> square(context, c, w, h, d)
            Form.WIDE -> wide(context, c, w, h, d)
            Form.TALL -> tall(context, c, w, h, d)
            Form.LARGE -> large(context, c, w, h, d)
        }
        return bmp
    }

    /** One stat: name, "eaten / target unit", progress and colour. */
    private class Stat(val name: String, val eaten: Int, val target: Int, val unit: String, val color: Int) {
        val p: Float get() = eaten.toFloat() / target.coerceAtLeast(1)
        val value: String get() = if (unit == "kcal") "${fmt(eaten)} / ${fmt(target)}" else "${fmt(eaten)} / ${fmt(target)} $unit"
    }

    /** What the drawings need, worked out once. */
    private class Day(s: KynetixWidgetProvider.DayState) {
        val calLeft = s.caloriesTarget - s.caloriesEaten
        val proLeft = s.proteinTarget - s.proteinEaten
        val calP = s.caloriesEaten.toFloat() / s.caloriesTarget.coerceAtLeast(1)
        val proP = s.proteinEaten.toFloat() / s.proteinTarget.coerceAtLeast(1)
        val over = calLeft < 0
        val stale = s.stale
        val dayName = KynetixWidgetProvider.dayName(s.label, s.isTrainingDay)
        val big = if (over) "+${fmt(abs(calLeft))}" else fmt(calLeft)
        val bigUnit = if (over) "kcal over" else "kcal left"
        val proShort = if (proLeft <= 0) "Protein done" else "$proLeft g protein"
        val header = if (stale) "Open Kynetix to refresh" else dayName
        val calories = Stat("Calories", s.caloriesEaten, s.caloriesTarget, "kcal", if (over) CAL_OVER else CAL)
        val protein = Stat("Protein", s.proteinEaten, s.proteinTarget, "g", PRO)

        /** Carbs, fat and fiber that have a target; an older payload has none. */
        val macros = listOfNotNull(
            if (s.carbsTarget > 0) Stat("Carbs", s.carbsEaten, s.carbsTarget, "g", CARBS) else null,
            if (s.fatTarget > 0) Stat("Fat", s.fatEaten, s.fatTarget, "g", FAT) else null,
            if (s.fiberTarget > 0) Stat("Fiber", s.fiberEaten, s.fiberTarget, "g", FIBER) else null,
        )

        /** Bars for the 4x2 plate: the macros, or eaten of target. */
        val barStats = macros.ifEmpty { listOf(calories, protein) }

        /** Bars for the 2x4 plate, which has room for eaten of target too. */
        val tallStats = listOf(calories, protein) + macros
    }

    // ── 2x2: rings, numbers inside ───────────────────────────────────────────

    private fun square(context: Context, c: Canvas, w: Float, h: Float, d: Day?) {
        val size = min(w, h)
        dial(context, c, w / 2f, h / 2f, size, d, showStale = true)
    }

    /**
     * The two rings of [size] dp centred on ([cx], [cy]), the lens, and
     * kcal left over protein left inside (or the signed-out state).
     */
    private fun dial(context: Context, c: Canvas, cx: Float, cy: Float, size: Float, d: Day?, showStale: Boolean) {
        val stroke = min(size * 0.052f, 11f)
        val gap = stroke * 0.55f
        val rOuter = size / 2f - stroke / 2f - size * 0.012f
        val rInner = rOuter - stroke - gap
        lens(c, cx, cy, rInner - stroke / 2f - gap * 0.4f)
        ring(c, cx, cy, rOuter, stroke, d?.calP ?: 0f, if (d?.over == true) CAL_OVER else CAL, TRACK, lift = true)
        ring(c, cx, cy, rInner, stroke, d?.proP ?: 0f, PRO, TRACK, lift = true)
        val inner = (rInner - stroke / 2f) * 2f
        val nf = num(context)
        val lf = label(context)
        if (d == null) {
            text(c, "Kynetix", cx, cy + inner * 0.04f, fit("Kynetix", inner * 0.7f, inner * 0.2f, nf), nf, TEXT, Paint.Align.CENTER)
            val sub = "Open to sync"
            text(c, sub, cx, cy + inner * 0.2f, fit(sub, inner * 0.7f, inner * 0.095f, lf), lf, TEXT_SOFT, Paint.Align.CENTER)
            return
        }
        val bigSize = fit(d.big, inner * 0.76f, inner * 0.32f, nf)
        // A stale note takes a line under protein, so the stack moves up.
        val lift = if (showStale && d.stale) inner * 0.07f else 0f
        val base = cy + bigSize * 0.34f - lift
        text(c, d.bigUnit, cx, base - bigSize * 0.92f, inner * 0.1f, lf, TEXT_SOFT, Paint.Align.CENTER)
        text(c, d.big, cx, base, bigSize, nf, if (d.over) CAL_OVER else TEXT, Paint.Align.CENTER)
        text(c, d.proShort, cx, base + inner * 0.165f, fit(d.proShort, inner * 0.74f, inner * 0.105f, lf), lf, PRO, Paint.Align.CENTER)
        if (showStale && d.stale) {
            val t = "Open to refresh"
            text(c, t, cx, base + inner * 0.29f, fit(t, inner * 0.62f, inner * 0.088f, lf), lf, TEXT_SOFT, Paint.Align.CENTER)
        }
    }

    // ── 4x2: rings left, a plate of bars right ───────────────────────────────

    private fun wide(context: Context, c: Canvas, w: Float, h: Float, d: Day?) {
        val gap = 10f
        val ringSize = min(h, w * 0.47f)
        dial(context, c, ringSize / 2f, h / 2f, ringSize, d, showStale = false)
        val x = ringSize + gap
        val plateW = w - x
        if (d == null) {
            messagePlate(context, c, x, h / 2f, plateW)
            return
        }
        val natural = barPlateHeight(d.barStats.size, 1f)
        val k = minOf(1f, h / natural, plateW / 170f)
        val ph = barPlateHeight(d.barStats.size, k)
        barPlate(context, c, x, (h - ph) / 2f, plateW, d.header, d.barStats, k)
    }

    // ── 2x4: rings on top, a plate of bars under them ────────────────────────

    private fun tall(context: Context, c: Canvas, w: Float, h: Float, d: Day?) {
        val gap = 12f
        var ringSize = min(w, h * 0.52f)
        val rows = d?.tallStats?.size ?: 0
        val natural = if (d == null) MESSAGE_H else barPlateHeight(rows, 1f)
        val s = minOf(1f, h / (ringSize + gap + natural), w / 160f)
        ringSize *= s
        val ph = if (d == null) MESSAGE_H * s else barPlateHeight(rows, s)
        val top = (h - (ringSize + gap + ph)) / 2f
        dial(context, c, w / 2f, top + ringSize / 2f, ringSize, d, showStale = false)
        val py = top + ringSize + gap
        if (d == null) {
            messagePlate(context, c, 0f, py + ph / 2f, w, s)
            return
        }
        barPlate(context, c, 0f, py, w, d.header, d.tallStats, s)
    }

    // ── 4x4: rings and eaten of target, then carbs, fat and fiber ────────────

    private fun large(context: Context, c: Canvas, w: Float, h: Float, d: Day?) {
        val gap = 12f
        val ringSize0 = min(w * 0.5f, h * 0.5f)
        val macros = d?.macros.orEmpty()
        val miniH0 = if (macros.isEmpty()) 0f else miniPlateHeight(1f)
        val totalH = ringSize0 + (if (miniH0 > 0f) gap + miniH0 else 0f)
        val s = min(1f, h / totalH)
        val ringSize = ringSize0 * s
        // Spare height goes to the macro rings (up to a quarter larger).
        val mk = if (miniH0 > 0f) (s * minOf(1.25f, (h - ringSize - gap) / miniH0)).coerceAtLeast(s) else s
        val miniH = miniH0 * mk
        val top = (h - (ringSize + if (miniH > 0f) gap + miniH else 0f)) / 2f
        val cy = top + ringSize / 2f
        dial(context, c, ringSize / 2f, cy, ringSize, d, showStale = false)
        val x = ringSize + gap
        val plateW = w - x
        if (d == null) {
            messagePlate(context, c, x, cy, plateW, s)
            return
        }
        val k = minOf(1.08f * s, plateW / 160f)
        val stats = listOf(d.calories, d.protein)
        val ph = barPlateHeight(stats.size, k)
        barPlate(context, c, x, cy - ph / 2f, plateW, d.header, stats, k)
        if (macros.isNotEmpty()) miniPlate(context, c, 0f, top + ringSize + gap, w, macros, mk)
    }

    // ── Plates ───────────────────────────────────────────────────────────────

    private const val PAD_X = 14f
    private const val PAD_Y = 12f
    private const val HEADER_H = 22f
    private const val ROW_H = 33f
    private const val MESSAGE_H = 62f

    private fun barPlateHeight(rows: Int, k: Float): Float =
        (PAD_Y * 2 + HEADER_H + rows * ROW_H - 6f) * k

    /** A plate with a small header and one bar row per stat. */
    private fun barPlate(context: Context, c: Canvas, x: Float, y: Float, width: Float, header: String, stats: List<Stat>, k: Float) {
        val lf = label(context)
        val height = barPlateHeight(stats.size, k)
        plate(c, RectF(x, y, x + width, y + height), 16f * k)
        val left = x + PAD_X * k
        val right = x + width - PAD_X * k
        val hs = fit(header, right - left, 11.5f * k, lf)
        text(c, header, left, y + PAD_Y * k + 11f * k, hs, lf, TEXT_SOFT)
        var top = y + (PAD_Y + HEADER_H) * k
        for (st in stats) {
            barRow(context, c, left, right, top, st, k)
            top += ROW_H * k
        }
    }

    /** "Carbs        96 / 226 g" over a slim bar; [top] is the row's top. */
    private fun barRow(context: Context, c: Canvas, left: Float, right: Float, top: Float, st: Stat, k: Float) {
        val lf = label(context)
        val nf = num(context)
        val ts = 12.5f * k
        val base = top + ts
        val vs = fit(st.value, (right - left) * 0.62f, ts, nf)
        text(c, st.name, left, base, ts, lf, TEXT)
        text(c, st.value, right, base, vs, nf, TEXT, Paint.Align.RIGHT)
        bar(c, left, right, base + 6f * k, 4f * k, st.p, st.color)
    }

    private fun miniPlateHeight(k: Float): Float = (14f + 66f + 10f + 15f + 15f + 12f) * k

    /** Carbs, fat and fiber as three small rings, eaten inside, target under. */
    private fun miniPlate(context: Context, c: Canvas, x: Float, y: Float, width: Float, stats: List<Stat>, k: Float) {
        val lf = label(context)
        val nf = num(context)
        val height = miniPlateHeight(k)
        plate(c, RectF(x, y, x + width, y + height), 18f * k)
        val colW = (width - 2 * PAD_X * k) / stats.size
        val ringD = min(66f * k, colW * 0.8f)
        val ry = y + 14f * k + ringD / 2f
        for ((i, st) in stats.withIndex()) {
            val cx = x + PAD_X * k + colW * (i + 0.5f)
            val stroke = ringD * 0.085f
            val r = ringD / 2f - stroke / 2f
            ring(c, cx, ry, r, stroke, st.p, st.color, TRACK_ON_PLATE)
            val n = "${fmt(st.eaten)}"
            val inner = (r - stroke) * 2f
            val ns = fit(n, inner * 0.72f, ringD * 0.27f, nf)
            text(c, n, cx, ry + ns * 0.36f, ns, nf, TEXT, Paint.Align.CENTER)
            val nameBase = y + (14f + 10f + 12f) * k + ringD
            text(c, st.name, cx, nameBase, fit(st.name, colW * 0.92f, 12.5f * k, lf), lf, TEXT, Paint.Align.CENTER)
            val of = "of ${fmt(st.target)} g"
            text(c, of, cx, nameBase + 15f * k, fit(of, colW * 0.92f, 11.5f * k, lf), lf, TEXT_SOFT, Paint.Align.CENTER)
        }
    }

    /** Signed-out plate, vertically centred on [cy]. */
    private fun messagePlate(context: Context, c: Canvas, x: Float, cy: Float, width: Float, k: Float = 1f) {
        val nf = num(context)
        val lf = label(context)
        val height = MESSAGE_H * k
        val y = cy - height / 2f
        plate(c, RectF(x, y, x + width, y + height), 16f * k)
        val left = x + PAD_X * k
        val avail = width - 2 * PAD_X * k
        val title = "Nothing synced yet"
        text(c, title, left, y + 27f * k, fit(title, avail, 15f * k, nf), nf, TEXT)
        val sub = "Open Kynetix to see your day"
        text(c, sub, left, y + 46f * k, fit(sub, avail, 12f * k, lf), lf, TEXT_SOFT)
    }

    // ── Pieces ───────────────────────────────────────────────────────────────

    private fun plate(c: Canvas, r: RectF, radius: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = PLATE }
        c.drawRoundRect(r, radius, radius, p)
        p.style = Paint.Style.STROKE
        p.strokeWidth = 0.75f
        p.color = PLATE_EDGE
        val e = RectF(r.left + 0.375f, r.top + 0.375f, r.right - 0.375f, r.bottom - 0.375f)
        c.drawRoundRect(e, radius, radius, p)
    }

    private fun bar(c: Canvas, left: Float, right: Float, top: Float, barH: Float, p: Float, color: Int) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = TRACK_ON_PLATE }
        c.drawRoundRect(RectF(left, top, right, top + barH), barH, barH, paint)
        val pp = min(p.coerceAtLeast(0f), 1f)
        if (pp > 0f) {
            paint.color = color
            c.drawRoundRect(RectF(left, top, left + maxOf((right - left) * pp, barH), top + barH), barH, barH, paint)
        }
    }

    private fun lens(c: Canvas, cx: Float, cy: Float, r: Float) {
        c.drawCircle(cx, cy, r, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = LENS })
    }

    private fun ring(c: Canvas, cx: Float, cy: Float, r: Float, stroke: Float, progress: Float, color: Int, track: Int, lift: Boolean = false) {
        val oval = RectF(cx - r, cy - r, cx + r, cy + r)
        val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            this.color = track
        }
        c.drawCircle(cx, cy, r, t)
        if (lift) {
            // On a transparent widget the track needs a light edge to read on
            // dark wallpapers as well as light ones.
            t.color = TRACK_LIFT
            c.drawCircle(cx, cy, r, t)
        }
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
        return if (w <= maxWidth || w <= 0f) maxSize else maxSize * maxWidth / w
    }

    /** Draws [s] with its baseline at [baseline]; sizes are in dp. */
    private fun text(c: Canvas, s: String, x: Float, baseline: Float, size: Float, face: Typeface, color: Int, align: Paint.Align = Paint.Align.LEFT) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            typeface = face
            textSize = size
            this.color = color
            textAlign = align
            letterSpacing = if (size > 18f) -0.03f else -0.005f
        }
        c.drawText(s, x, baseline, p)
    }
}
