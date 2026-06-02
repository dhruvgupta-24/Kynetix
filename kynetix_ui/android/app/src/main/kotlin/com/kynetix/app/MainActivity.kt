package com.kynetix.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private var pendingAction: String? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == "com.kynetix.app.ACTION_OPEN_NUTRITION") {
            pendingAction = "open_nutrition"
            sendActionToFlutter()
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
