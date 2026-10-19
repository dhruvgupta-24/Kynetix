package com.kynetix.app

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.Animatable2
import android.graphics.drawable.AnimatedVectorDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView

/**
 * The Shear launch intro (avd_intro), played natively over the app as it
 * starts. An AnimatedVectorDrawable runs on the RenderThread, so the work
 * Flutter does on its own threads at cold start (session restore, the first
 * screen) can't make it drop frames.
 *
 * It picks up exactly where the system splash (avd_splash) ends, plays to
 * the full wordmark, holds, then fades once Flutter has drawn the app
 * underneath ([onAppReady]). [onRevealed] fires as the fade begins.
 */
class LaunchIntro(private val activity: Activity) {

    private val handler = Handler(Looper.getMainLooper())
    private var overlay: FrameLayout? = null
    private var avd: AnimatedVectorDrawable? = null
    private var started = false
    private var animationDone = false
    private var appReady = false
    private var fading = false

    /** True once the fade has begun (or there was no intro). */
    var revealed = false
        private set
    private val revealWaiters = mutableListOf<() -> Unit>()

    /** Covers the window with graphite and the splash's last frame. */
    fun attach() {
        val drawable = activity.getDrawable(R.drawable.avd_intro) as? AnimatedVectorDrawable
        if (drawable == null) {
            reveal()
            return
        }
        avd = drawable
        val density = activity.resources.displayMetrics.density
        val widthDp = activity.resources.displayMetrics.widthPixels / density
        // The word is 311 dp wide; narrow screens scale the whole intro down.
        val fit = ((widthDp - 32f) / 311f).coerceAtMost(1f)
        val size = (360 * density).toInt()
        val image = ImageView(activity).apply {
            setImageDrawable(drawable)
            scaleType = ImageView.ScaleType.FIT_CENTER
            scaleX = fit
            scaleY = fit
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        overlay = FrameLayout(activity).apply {
            setBackgroundColor(Color.parseColor("#0B0B0C"))
            contentDescription = "Kynetix"
            isClickable = true // the app underneath takes no touches yet
            setOnClickListener { skip() }
            addView(image, FrameLayout.LayoutParams(size, size, Gravity.CENTER))
        }
        activity.addContentView(
            overlay,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        drawable.registerAnimationCallback(object : Animatable2.AnimationCallback() {
            override fun onAnimationEnd(d: Drawable?) {
                animationDone = true
                maybeFinish()
            }
        })
        // Never hold the app hostage: if Flutter is slow to draw, go anyway.
        handler.postDelayed({ markAppReady() }, 4500L)
    }

    /** Plays the intro. Called as the system splash hands over. */
    fun start() {
        val d = avd ?: return
        if (started) return
        started = true
        d.start()
        // A light tick as the blade starts across the word.
        handler.postDelayed({
            val feedback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.CONFIRM
            } else {
                HapticFeedbackConstants.VIRTUAL_KEY
            }
            overlay?.performHapticFeedback(feedback)
        }, 960L)
        // The animation callback can be skipped when animations are off.
        handler.postDelayed({ if (!animationDone) { animationDone = true; maybeFinish() } }, 2400L)
    }

    /** Flutter has drawn the app; the intro may leave once it has played. */
    fun markAppReady() {
        appReady = true
        maybeFinish()
    }

    /** Runs [then] once the intro has started fading (at once if it has). */
    fun whenRevealed(then: () -> Unit) {
        if (revealed) then() else revealWaiters.add(then)
    }

    private fun skip() {
        animationDone = true
        appReady = true
        maybeFinish(hold = 0L)
    }

    private fun maybeFinish(hold: Long = 180L) {
        if (fading || !animationDone || !appReady) return
        fading = true
        val view = overlay ?: return reveal()
        handler.postDelayed({
            reveal()
            view.animate().alpha(0f).setDuration(320L).withEndAction {
                (view.parent as? ViewGroup)?.removeView(view)
                avd?.stop()
                overlay = null
                avd = null
            }.start()
        }, hold)
    }

    private fun reveal() {
        if (revealed) return
        revealed = true
        revealWaiters.forEach { it() }
        revealWaiters.clear()
    }

    /** No intro this time (the activity was recreated): reveal at once. */
    fun skipEntirely() = reveal()
}
