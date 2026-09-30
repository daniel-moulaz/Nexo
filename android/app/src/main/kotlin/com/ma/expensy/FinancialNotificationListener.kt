package com.ma.expensy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

/** Encrypted, bounded transport queue. SQLite ownership stays with DBHelper. */
object FinancialInboxQueue {
    private const val alias = "nexo.notification.queue.v1"
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (ks.containsAlias(alias)) return ks.getKey(alias, null) as SecretKey
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized fun read(c: Context): JSONArray {
        val data = c.getSharedPreferences("nexo_automation", 0).getString("queue", null) ?: return JSONArray()
        val bytes = Base64.decode(data, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return JSONArray(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    @Synchronized private fun write(c: Context, rows: JSONArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val data = cipher.iv + cipher.doFinal(rows.toString().toByteArray())
        check(c.getSharedPreferences("nexo_automation", 0).edit().putString("queue", Base64.encodeToString(data, Base64.NO_WRAP)).commit())
    }
    @Synchronized fun add(c: Context, row: JSONObject): Boolean {
        val old = read(c); val rows = JSONArray(); val cutoff = System.currentTimeMillis() - 7 * 86400000L
        val seen = JSONObject(c.getSharedPreferences("nexo_automation", 0).getString("seen", "{}")!!)
        if (seen.optLong(row.getString("id"), 0) >= cutoff) return false
        for (i in 0 until old.length()) {
            val item = old.getJSONObject(i)
            if (item.getString("id") == row.getString("id")) return false
            if (item.getLong("occurred_at") >= cutoff) rows.put(item)
        }
        // Backpressure instead of silently evicting an unreviewed suggestion.
        check(rows.length() < 250)
        rows.put(row)
        write(c, rows)
        return true
    }
    @Synchronized fun ack(c: Context, ids: Set<String>) {
        val old = read(c); val rows = JSONArray()
        val prefs = c.getSharedPreferences("nexo_automation", 0)
        val seen = JSONObject(prefs.getString("seen", "{}")!!)
        val cutoff = System.currentTimeMillis() - 7 * 86400000L
        seen.keys().asSequence().toList().filter { seen.optLong(it) < cutoff }.forEach { seen.remove(it) }
        for (i in 0 until old.length()) {
            val row = old.getJSONObject(i)
            if (ids.contains(row.getString("id"))) seen.put(row.getString("id"), row.getLong("occurred_at"))
        }
        // Bounded device-local replay memory. SQLite also keeps its existing tombstones.
        seen.keys().asSequence().toList().sortedByDescending { seen.optLong(it) }.drop(2000).forEach { seen.remove(it) }
        check(prefs.edit().putString("seen", seen.toString()).commit())
        for (i in 0 until old.length()) if (!ids.contains(old.getJSONObject(i).getString("id"))) rows.put(old.getJSONObject(i))
        write(c, rows)
    }
}

class FinancialNotificationListener : NotificationListenerService() {
    private fun diagnostic(reason: String, confidence: String = "") {
        getSharedPreferences("nexo_automation", 0).edit()
            .putLong("last_analyzed", System.currentTimeMillis()).putString("last_result", reason)
            .putString("last_confidence", confidence).apply()
    }
    private fun notifyReview() {
        val prefs = getSharedPreferences("nexo_automation", 0)
        if (!prefs.getBoolean("notify_review", false)) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            "nexo_suggestions", "Compras para revisar", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(this, MainActivity::class.java).putExtra(QuickAddWidgetProvider.EXTRA_ROUTE, "notification_inbox")
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(this, 73104, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "nexo_suggestions") else Notification.Builder(this)
        // Always generic: safe even while Flutter is closed or device privacy settings change.
        manager.notify(73104, builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Nexo detectou uma movimentação")
            .setContentText("Revise a sugestão antes de registrar.").setContentIntent(pending)
            .addAction(Notification.Action.Builder(null, "Revisar", pending).build())
            .setVisibility(Notification.VISIBILITY_PRIVATE).setOnlyAlertOnce(true).setAutoCancel(true).build())
    }
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("nexo_automation", 0)
        if (sbn.packageName == packageName) return
        if (!prefs.getBoolean("enabled", false)) return
        // Learn source identities only, never unapproved notification content.
        val observed = prefs.getStringSet("observed_apps", emptySet())!!.toMutableSet()
        if (observed.size < 100 && observed.add(sbn.packageName)) prefs.edit().putStringSet("observed_apps", observed).apply()
        if (!prefs.getStringSet("apps", emptySet())!!.contains(sbn.packageName)) { diagnostic("app_not_allowed"); return }
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) { diagnostic("group_summary"); return }
        val now = System.currentTimeMillis()
        if (sbn.postTime < now - 7 * 86400000L || sbn.postTime > now + 60000L) { diagnostic("old"); return }
        val extras = sbn.notification.extras
        val parsed = FinancialNotificationParser.analyzeParts(extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString())
        val item = parsed.suggestion ?: run { diagnostic(parsed.reason); return }
        val eventTime = sbn.notification.`when`.takeIf { it >= now - 7 * 86400000L && it <= now + 60000L } ?: sbn.postTime
        try {
            val added = FinancialInboxQueue.add(this, JSONObject().put("id", FinancialNotificationParser.fingerprint(sbn.packageName, sbn.key, eventTime, item))
                .put("app_id", sbn.packageName).put("amount_cents", item.cents)
                .put("description", item.description).put("kind", item.kind).put("medium", item.medium)
                .put("occurred_at", eventTime))
            prefs.edit().remove("queue_error").apply()
            diagnostic(if (added) "created" else "duplicate", item.confidence)
            if (added) try { notifyReview() } catch (_: Exception) { /* Delivery cannot discard the queued suggestion. */ }
        } catch (_: Exception) {
            // No raw payload or financial fields in logs, even on failure.
            prefs.edit().putBoolean("queue_error", true).apply()
            diagnostic("queue_error")
        }
    }
}
