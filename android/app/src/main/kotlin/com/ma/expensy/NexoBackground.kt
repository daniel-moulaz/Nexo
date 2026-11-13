package com.ma.expensy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * Applies the assistant's requests with the app closed.
 *
 * One worker does the job, started three ways: every 15 minutes (the
 * shortest WorkManager allows), right away when the server sends a silent
 * push (Firebase, only when configured), and on demand from the app.
 *
 * Exactly one Dart isolate touches the database at a time:
 * - with the app's own engine alive (open or in the background), the worker
 *   asks it to run a sync pass, as when the app is in front;
 * - otherwise it starts a headless engine on [ENTRYPOINT] and waits for it;
 *   an app opening meanwhile waits for that engine before it opens the
 *   database (`waitForHeadless`).
 */
object NexoBackground {
    const val CHANNEL = "nexo/background"
    private const val ENTRYPOINT = "nexoBackgroundQueue"
    private const val PERIODIC = "nexo-claude-queue"
    private const val NOW = "nexo-claude-queue-now"
    private const val PREFS = "nexo_background"
    const val NOTIFICATION_CHANNEL = "nexo_claude_queue"

    @Volatile var uiEngine: FlutterEngine? = null
    private val main = Handler(Looper.getMainLooper())
    private var headless: FlutterEngine? = null
    private val headlessWaiters = mutableListOf<() -> Unit>()

    private fun network() = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED).build()

    fun schedule(context: Context, enabled: Boolean) {
        val work = WorkManager.getInstance(context)
        if (!enabled) {
            work.cancelUniqueWork(PERIODIC)
            return
        }
        val request = PeriodicWorkRequestBuilder<NexoQueueWorker>(15, TimeUnit.MINUTES)
            .setConstraints(network())
            .setInputData(Data.Builder().putString("source", "periodic").build())
            .build()
        work.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    /** Right away (expedited), after any run already in progress. */
    fun runNow(context: Context, source: String) {
        val request = OneTimeWorkRequestBuilder<NexoQueueWorker>()
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .setConstraints(network())
            .setInputData(Data.Builder().putString("source", source).build())
            .build()
        WorkManager.getInstance(context)
            .enqueueUniqueWork(NOW, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    // ── Firebase, only with the project's values in the build ───────────
    fun firebaseConfigured(context: Context): Boolean =
        context.getString(R.string.nexo_fcm_app_id).isNotEmpty()

    fun initFirebase(context: Context) {
        if (!firebaseConfigured(context) || FirebaseApp.getApps(context).isNotEmpty()) return
        try {
            FirebaseApp.initializeApp(context, FirebaseOptions.Builder()
                .setApplicationId(context.getString(R.string.nexo_fcm_app_id))
                .setApiKey(context.getString(R.string.nexo_fcm_api_key))
                .setProjectId(context.getString(R.string.nexo_fcm_project_id))
                .setGcmSenderId(context.getString(R.string.nexo_fcm_sender_id))
                .build())
        } catch (_: Exception) {
            // Wrong values: the queue still runs every 15 minutes.
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, 0)

    fun rememberToken(context: Context, token: String?) {
        prefs(context).edit().putString("push_token", token).apply()
    }

    fun pushToken(context: Context, done: (String?) -> Unit) {
        if (!firebaseConfigured(context)) return done(null)
        initFirebase(context)
        try {
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { rememberToken(context, it); done(it) }
                .addOnFailureListener { done(prefs(context).getString("push_token", null)) }
        } catch (_: Exception) {
            done(null)
        }
    }

    // ── Battery: Android's own setting, plus the maker's (Xiaomi) ───────
    fun batteryUnrestricted(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun openBatterySettings(context: Context) {
        val intent = if (!batteryUnrestricted(context)) {
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"))
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /** Xiaomi's "Autostart" screen, when this phone has it. */
    fun openAutostart(context: Context): Boolean {
        val intent = Intent().setClassName("com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent); true
        } catch (_: Exception) {
            false
        }
    }

    fun isXiaomi(): Boolean = Build.MANUFACTURER.lowercase().let {
        it.contains("xiaomi") || it.contains("redmi") || it.contains("poco")
    }

    // ── The app's engine ────────────────────────────────────────────────
    fun attach(engine: FlutterEngine, context: Context) {
        uiEngine = engine
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val app = context.applicationContext
            when (call.method) {
                "waitForHeadless" -> main.post {
                    if (headless == null) result.success(null)
                    else headlessWaiters.add { result.success(null) }
                }
                "schedule" -> { schedule(app, call.arguments == true); result.success(null) }
                "runNow" -> { runNow(app, "app"); result.success(null) }
                "pushToken" -> pushToken(app) { main.post { result.success(it) } }
                "pushConfigured" -> result.success(firebaseConfigured(app))
                "battery" -> result.success(mapOf(
                    "unrestricted" to batteryUnrestricted(app),
                    "xiaomi" to isXiaomi(),
                    "maker" to Build.MANUFACTURER))
                "openBattery" -> { openBatterySettings(app); result.success(null) }
                "openAutostart" -> result.success(openAutostart(app))
                else -> result.notImplemented()
            }
        }
    }

    fun detach(engine: FlutterEngine) {
        if (uiEngine === engine) uiEngine = null
    }

    /** One pass; null when it could not run (the worker retries later). */
    suspend fun run(context: Context, source: String): Map<*, *>? =
        suspendCancellableCoroutine { cont ->
            main.post {
                val ui = uiEngine
                if (ui != null) {
                    MethodChannel(ui.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("runQueue", source, object : MethodChannel.Result {
                            override fun success(value: Any?) { if (cont.isActive) cont.resume(value as? Map<*, *> ?: emptyMap<String, Any>()) }
                            override fun error(code: String, message: String?, details: Any?) { if (cont.isActive) cont.resume(null) }
                            override fun notImplemented() { if (cont.isActive) cont.resume(null) }
                        })
                } else if (headless != null) {
                    // Another headless pass is running: it covers this one.
                    if (cont.isActive) cont.resume(emptyMap<String, Any>())
                } else {
                    startHeadless(context, source) { if (cont.isActive) cont.resume(it) }
                }
            }
        }

    private fun startHeadless(context: Context, source: String, done: (Map<*, *>?) -> Unit) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        val engine = FlutterEngine(context)
        headless = engine
        var finished = false
        fun finish(result: Map<*, *>?) {
            if (finished) return
            finished = true
            main.post {
                engine.destroy()
                headless = null
                val waiters = headlessWaiters.toList()
                headlessWaiters.clear()
                waiters.forEach { it() }
                done(result)
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "source" -> result.success(source)
                "done" -> { result.success(null); finish(call.arguments as? Map<*, *>) }
                "waitForHeadless" -> result.success(null)
                else -> result.notImplemented()
            }
        }
        // A pass that hangs must not keep the app waiting forever.
        main.postDelayed({ finish(null) }, 80_000)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT))
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL) == null) {
            manager.createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL,
                "Pedidos do Claude", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Aparece só enquanto o Nexo grava pedidos com o app fechado."
                setShowBadge(false)
            })
        }
    }
}

class NexoQueueWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val source = inputData.getString("source") ?: "periodic"
        val outcome = withTimeoutOrNull(90_000) { NexoBackground.run(applicationContext, source) }
        return if (outcome == null && runAttemptCount < 2) Result.retry() else Result.success()
    }

    /** Before Android 12 an expedited job runs as a short foreground service. */
    override suspend fun getForegroundInfo(): ForegroundInfo {
        NexoBackground.ensureChannel(applicationContext)
        val notification = NotificationCompat.Builder(applicationContext, NexoBackground.NOTIFICATION_CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Nexo")
            .setContentText("Gravando pedidos do Claude…")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setSilent(true)
            .build()
        return ForegroundInfo(7317, notification)
    }
}
