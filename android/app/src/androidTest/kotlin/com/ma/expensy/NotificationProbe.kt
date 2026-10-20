package com.ma.expensy

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import android.os.ParcelFileDescriptor
import org.json.JSONObject

/** Runs only on a disposable emulator. Never included in the release APK. */
class NotificationProbe : Instrumentation() {
    private val passed = mutableListOf<String>()
    private var resume = false
    private var queueOnly = false
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        resume = arguments?.getString("phase") == "resume"
        queueOnly = arguments?.getString("phase") == "queue"
        start()
    }
    private fun shell(command: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(uiAutomation.executeShellCommand(command))
            .bufferedReader().use { it.readText() }
    private fun post(tag: String, text: String) {
        // UiAutomation tokenizes arguments, it does not interpret shell quotes.
        // NBSP keeps the message in one argument and exercises bank Unicode copy.
        shell("cmd notification post -t NexoQA $tag ${text.replace(' ', '\u00a0')}")
    }
    private fun awaitCondition(label: String, predicate: () -> Boolean) {
        val end = System.currentTimeMillis() + 12000
        while (System.currentTimeMillis() < end) {
            if (predicate()) { passed.add(label); return }
            Thread.sleep(100)
        }
        error("Timeout: $label")
    }
    override fun onStart() {
        val result = Bundle()
        try {
            val context = targetContext
            check(context.packageName == "com.ma.expensy.nativeqa") {
                "This probe requires the isolated nativeqa application ID"
            }
            val prefs = context.getSharedPreferences("nexo_automation", 0)
            if (queueOnly) {
                check(prefs.edit().clear().commit())
                val now = System.currentTimeMillis()
                fun row(id: String, time: Long = now) = JSONObject()
                    .put("id", id).put("app_id", "test.bank").put("occurred_at", time)
                    .put("amount_cents", 100).put("description", "Sintético")
                    .put("kind", "expense").put("medium", "bank")
                check(FinancialInboxQueue.add(context, row("expired", now - 8 * 86400000L)))
                check(FinancialInboxQueue.add(context, row("current")))
                check(FinancialInboxQueue.read(context).length() == 1)
                passed.add("intake prunes encrypted items older than seven days")
                check(!FinancialInboxQueue.add(context, row("current")))
                passed.add("queued duplicate rejected")
                FinancialInboxQueue.ack(context, setOf("current"))
                check(!FinancialInboxQueue.add(context, row("current")))
                passed.add("acknowledged duplicate rejected")
                for (i in 0 until 250) check(FinancialInboxQueue.add(context, row("bounded-$i")))
                var rejected = false
                try { FinancialInboxQueue.add(context, row("overflow")) }
                catch (_: IllegalStateException) { rejected = true }
                check(rejected && FinancialInboxQueue.read(context).length() == 250)
                passed.add("queue backpressure retains all 250 pending items")
                FinancialInboxQueue.ack(context, (0 until 125).map { "bounded-$it" }.toSet())
                check(FinancialInboxQueue.read(context).length() == 125)
                passed.add("partial ack retains unrelated pending items")
                val encrypted = prefs.getString("queue", null)!!
                check(prefs.edit().putString("queue", "invalid-encrypted-data").commit())
                try {
                    var failed = false
                    try { FinancialInboxQueue.add(context, row("must-not-overwrite")) }
                    catch (_: Exception) { failed = true }
                    check(failed && prefs.getString("queue", null) == "invalid-encrypted-data")
                } finally { check(prefs.edit().putString("queue", encrypted).commit()) }
                check(FinancialInboxQueue.read(context).length() == 125)
                passed.add("decryption failure cannot overwrite pending queue")
                result.putString("stream", "PASS (${passed.size})\n" + passed.joinToString("\n"))
                finish(Activity.RESULT_OK, result)
                return
            }
            if (resume) {
                val queue = FinancialInboxQueue.read(context)
                check(queue.length() == 1)
                val item = queue.getJSONObject(0)
                check(item.getLong("amount_cents") == 8000L && item.getString("kind") == "income")
                passed.add("encrypted queue survives process restart")
                runOnMainSync { FinancialNotificationListener.recover(context) }
                awaitCondition("listener reconnects after process restart") { FinancialNotificationListener.connected }
                Thread.sleep(500)
                check(FinancialInboxQueue.read(context).length() == 1)
                passed.add("persisted tombstone and pending item survive replay")
                check(context.databaseList().none { it.endsWith(".db") })
                passed.add("restart does not create financial entries")
                result.putString("stream", "PASS (${passed.size})\n" + passed.joinToString("\n"))
                finish(Activity.RESULT_OK, result)
                return
            }
            check(prefs.edit().clear().putBoolean("enabled", true)
                .putStringSet("apps", setOf("com.android.shell")).commit())
            shell("cmd notification allow_listener ${context.packageName}/com.ma.expensy.FinancialNotificationListener")
            runOnMainSync { FinancialNotificationListener.recover(context) }
            awaitCondition("listener connected") { FinancialNotificationListener.connected }
            post("nexo_probe", "Compra aprovada no credito de R$ 32,90 em MERCADO")
            awaitCondition("real Android notification reaches encrypted queue") {
                FinancialInboxQueue.read(context).length() == 1
            }
            val item = FinancialInboxQueue.read(context).getJSONObject(0)
            check(item.getLong("amount_cents") == 3290L)
            check(item.getString("medium") == "credit")
            check(item.getString("app_id") == "com.android.shell")
            passed.add("parsed amount and credit medium")
            val ciphertext = prefs.getString("queue", "")!!
            check(!ciphertext.contains("MERCADO") && !ciphertext.contains("amount_cents"))
            passed.add("persisted transport is encrypted")
            runOnMainSync { FinancialNotificationListener.recover(context) }
            Thread.sleep(500)
            check(FinancialInboxQueue.read(context).length() == 1)
            passed.add("active notification replay does not duplicate")
            FinancialInboxQueue.ack(context, setOf(item.getString("id")))
            check(FinancialInboxQueue.read(context).length() == 0)
            runOnMainSync { FinancialNotificationListener.recover(context) }
            Thread.sleep(500)
            check(FinancialInboxQueue.read(context).length() == 0)
            passed.add("ack tombstone blocks replay")
            post("nexo_denied", "Compra recusada R$ 90,00")
            awaitCondition("declined purchase rejected") { prefs.getString("last_result", "") == "not_financial" }
            check(FinancialInboxQueue.read(context).length() == 0)
            check(prefs.edit().putStringSet("apps", emptySet()).commit())
            post("nexo_unapproved", "Pix recebido R$ 80,00")
            Thread.sleep(500)
            check(FinancialInboxQueue.read(context).length() == 0)
            passed.add("unapproved app ignored")
            check(prefs.edit().putStringSet("apps", setOf("com.android.shell")).commit())
            runOnMainSync { FinancialNotificationListener.recover(context) }
            awaitCondition("newly allowed active notification recovered") { FinancialInboxQueue.read(context).length() == 1 }
            check(context.databaseList().none { it.endsWith(".db") })
            passed.add("no financial database created by capture")
            result.putString("stream", "PASS (${passed.size})\n" + passed.joinToString("\n"))
            finish(Activity.RESULT_OK, result)
        } catch (failure: Throwable) {
            result.putString("stream", "FAIL after ${passed.joinToString()}\n${failure.stackTraceToString()}")
            finish(Activity.RESULT_CANCELED, result)
        }
    }
}
