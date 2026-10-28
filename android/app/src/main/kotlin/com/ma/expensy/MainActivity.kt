package com.ma.expensy

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import android.os.Build
import android.os.Bundle
import android.app.NotificationManager
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the "Quick Add Transaction" home screen widget tap to Dart.
 *
 * No `home_widget` plugin dependency is used here (see HOMESCREEN_WIDGET.md
 * §4.1/§4.2) — this is a plain MethodChannel + EventChannel pair, since the
 * widget only ever needs to signal "open Add Transaction", not exchange any
 * app data. Two channels are used because the two cases are genuinely
 * different android lifecycles:
 *   - Cold start:  Dart asks for the launch intent's extra once, at startup.
 *   - Warm start:  the Activity is already alive; a new Intent arrives via
 *                  onNewIntent() and must be *pushed* to Dart as a stream
 *                  event instead, since Dart isn't calling anything at that
 *                  point.
 *
 * The "com.ma.expensy/automation" channel is kept for the privacy flags
 * (hide recents, block capture) that the security settings set; the bank
 * notification listener that used to share it was retired in 1.12.9.
 */
class MainActivity : FlutterFragmentActivity() {
    private fun privacy() {
        val p = getSharedPreferences("nexo_automation", 0)
        if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(!p.getBoolean("hide_recents", false))
        if (p.getBoolean("block_capture", false)) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        privacy()
    }
    private val methodChannelName = "com.ma.expensy/quick_add"
    private val eventChannelName = "com.ma.expensy/quick_add_stream"
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ma.expensy/automation")
            .setMethodCallHandler { call, result ->
                val p = getSharedPreferences("nexo_automation", 0)
                try {
                    when (call.method) {
                        "status" -> result.success(mapOf(
                            "notificationsAllowed" to (Build.VERSION.SDK_INT < 24 || (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()),
                            "recentsSupported" to (Build.VERSION.SDK_INT >= 33)))
                        "privacy" -> {
                            p.edit().putBoolean("hide_recents", call.argument<Boolean>("recents") == true)
                                .putBoolean("block_capture", call.argument<Boolean>("capture") == true).commit()
                            privacy(); result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("native_error", "Não foi possível acessar o recurso local.", null) }
            }

        // Cold-start case: Dart calls this once at startup to read the
        // route extra the launching Intent (if any) was created with.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialRoute") {
                    result.success(intent?.getStringExtra(QuickAddWidgetProvider.EXTRA_ROUTE))
                    intent?.removeExtra(QuickAddWidgetProvider.EXTRA_ROUTE)
                } else {
                    result.notImplemented()
                }
            }

        // Warm-start case: app already running, widget tapped again ->
        // onNewIntent fires below and is forwarded here as a stream event.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra(QuickAddWidgetProvider.EXTRA_ROUTE)
        if (route != null) {
            eventSink?.success(route)
        }
    }
}
