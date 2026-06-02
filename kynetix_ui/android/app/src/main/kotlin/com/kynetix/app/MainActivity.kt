package com.kynetix.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.kynetix.app/widget").setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                val context = applicationContext
                val intent = Intent(context, KynetixWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                }
                val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(
                    ComponentName(context, KynetixWidgetProvider::class.java)
                )
                intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                context.sendBroadcast(intent)

                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
