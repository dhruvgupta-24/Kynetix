package com.kynetix.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var pendingAction: String? = null
    private var methodChannel: MethodChannel? = null

    // Launch actions (Health Connect's "privacy policy" link) for Flutter.
    private var pendingLaunchAction: String? = null
    private var launchChannel: MethodChannel? = null

    // The Android 12+ splash plays the Shear K animation (avd_splash). It is
    // held until that animation ends, then removed at once (no fade) over the
    // identical K Flutter is already drawing. Dart waits for this before the
    // intro carries on.
    private var splashGone = Build.VERSION.SDK_INT < Build.VERSION_CODES.S
    private val splashWaiters = mutableListOf<MethodChannel.Result>()

    // The full Shear intro, played natively over the app (see LaunchIntro).
    private lateinit var intro: LaunchIntro

    companion object {
        private const val LAUNCH_CHANNEL = "com.kynetix.app/launch"
        private const val ACTION_PRIVACY_POLICY = "privacy_policy"
        // Android 13 and lower: Health Connect's rationale link.
        private const val ACTION_SHOW_PERMISSIONS_RATIONALE =
            "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"
        // Android 14+: delivered through the ViewPermissionUsageActivity alias.
        private const val ACTION_VIEW_PERMISSION_USAGE =
            "android.intent.action.VIEW_PERMISSION_USAGE"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent, coldStart = true)
        intro = LaunchIntro(this)
        if (savedInstanceState == null) {
            intro.attach()
            holdSplashForIconAnimation()
        } else {
            // Recreated (rotation, theme): no intro, no splash to wait for.
            intro.skipEntirely()
            markSplashGone()
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        // Flutter draws its own focus rings. Without this, any key press (a
        // hardware keyboard, Tab) makes Android outline the whole app window
        // with its default focus highlight, and it stays.
        disableDefaultFocusHighlight(window.decorView)
    }

    private fun disableDefaultFocusHighlight(view: View) {
        if (view is FlutterView) view.defaultFocusHighlightEnabled = false
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) disableDefaultFocusHighlight(view.getChildAt(i))
        }
    }

    private fun holdSplashForIconAnimation() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // No animated splash: the intro starts on the first frame.
            window.decorView.post { intro.start() }
            return
        }
        val shownAt = SystemClock.uptimeMillis()
        splashScreen.setOnExitAnimationListener { view ->
            // Let the K finish its slice and shear, then hand over instantly.
            val duration = view.iconAnimationDuration?.toMillis() ?: 0L
            val elapsed = SystemClock.uptimeMillis() - shownAt
            val wait = (duration - elapsed + 40L).coerceIn(0L, 1000L)
            Handler(Looper.getMainLooper()).postDelayed({
                // The intro's first frame is the splash's last: start it,
                // then lift the splash off in the same frame.
                intro.start()
                view.remove()
                markSplashGone()
            }, wait)
        }
        // If the system never shows a splash (some launches), go anyway.
        Handler(Looper.getMainLooper()).postDelayed({
            intro.start()
            markSplashGone()
        }, 3000L)
    }

    private fun markSplashGone() {
        if (splashGone) return
        splashGone = true
        splashWaiters.forEach { it.success(true) }
        splashWaiters.clear()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent, coldStart = false)
    }

    private fun handleIntent(intent: Intent?, coldStart: Boolean) {
        when (intent?.action) {
            "com.kynetix.app.ACTION_OPEN_NUTRITION" -> {
                pendingAction = when (intent.getStringExtra("kynetix_action")) {
                    "log_meal" -> "log_meal"
                    else -> "open_nutrition"
                }
                sendActionToFlutter()
            }
            ACTION_SHOW_PERMISSIONS_RATIONALE, ACTION_VIEW_PERMISSION_USAGE -> {
                pendingLaunchAction = ACTION_PRIVACY_POLICY
                // Cold start: Dart isn't listening yet, it asks with
                // getLaunchAction. Warm start: push it now.
                if (!coldStart) sendLaunchActionToFlutter()
            }
        }
    }

    private fun sendLaunchActionToFlutter() {
        val action = pendingLaunchAction
        val channel = launchChannel
        if (action != null && channel != null) {
            channel.invokeMethod("onLaunchAction", action)
            pendingLaunchAction = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/splash").setMethodCallHandler { call, result ->
            when (call.method) {
                "waitForSplash" -> if (splashGone) result.success(true) else splashWaiters.add(result)
                // Dart has drawn the app underneath the intro.
                "appReady" -> {
                    intro.markAppReady()
                    result.success(true)
                }
                // Completes as the intro starts fading: the app may animate.
                "waitForIntro" -> intro.whenRevealed { result.success(true) }
                else -> result.notImplemented()
            }
        }

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/widget")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val context = applicationContext
                    KynetixWidgetProvider.refreshAll(context)
                    result.success(true)
                }
                "pinWidget" -> {
                    // Asks the launcher to add one widget size to the home
                    // screen (Android 8+, launcher permitting).
                    val cls = when (call.argument<String>("size")) {
                        "4x2" -> KynetixWidgetWide::class.java
                        "2x4" -> KynetixWidgetTall::class.java
                        "4x4" -> KynetixWidgetLarge::class.java
                        else -> KynetixWidgetProvider::class.java
                    }
                    val m = AppWidgetManager.getInstance(applicationContext)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O &&
                        m.isRequestPinAppWidgetSupported
                    ) {
                        result.success(m.requestPinAppWidget(ComponentName(applicationContext, cls), null, null))
                    } else {
                        result.success(false)
                    }
                }
                "getPendingAction" -> {
                    val action = pendingAction
                    pendingAction = null
                    result.success(action)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/wakelock").setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                "disable" -> {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        // The Dart side asks with getLaunchAction once it is listening (cold
        // start); a warm start (onNewIntent) is pushed with onLaunchAction.
        launchChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_CHANNEL)
        launchChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchAction" -> {
                    val action = pendingLaunchAction
                    pendingLaunchAction = null
                    result.success(action)
                }
                else -> result.notImplemented()
            }
        }

        // Opens this app's system settings page (e.g. after the camera
        // permission was denied for barcode scanning).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                .setData(Uri.fromParts("package", packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Who installed this app ("com.android.vending" for Google Play, null
        // for a sideloaded APK). The sideload updater never shows for Play.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installerPackage" -> {
                        val installer = try {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                packageManager.getInstallSourceInfo(packageName).installingPackageName
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getInstallerPackageName(packageName)
                            }
                        } catch (e: Exception) {
                            null
                        }
                        result.success(installer)
                    }
                    else -> result.notImplemented()
                }
            }

        sendActionToFlutter()
    }

    private fun sendActionToFlutter() {
        val action = pendingAction
        val channel = methodChannel
        if (action != null && channel != null) {
            channel.invokeMethod("onAction", action)
            pendingAction = null
        }
    }
}
