package com.kynetix.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var pendingAction: String? = null
    private var methodChannel: MethodChannel? = null

    // Launch actions (Health Connect's "privacy policy" link) for Flutter.
    private var pendingLaunchAction: String? = null
    private var launchChannel: MethodChannel? = null

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

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/widget")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val context = applicationContext
                    val widgetIntent = Intent(context, KynetixWidgetProvider::class.java).apply {
                        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    }
                    val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(
                        ComponentName(context, KynetixWidgetProvider::class.java)
                    )
                    widgetIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    context.sendBroadcast(widgetIntent)
                    result.success(true)
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
