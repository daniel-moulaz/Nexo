package com.ma.expensy

import android.app.Notification
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
    @Synchronized fun add(c: Context, row: JSONObject) {
        val old = read(c); val rows = JSONArray(); val cutoff = System.currentTimeMillis() - 7 * 86400000L
        for (i in 0 until old.length()) {
            val item = old.getJSONObject(i)
            if (item.getString("id") == row.getString("id")) return
            if (item.getLong("occurred_at") >= cutoff) rows.put(item)
        }
        // Backpressure instead of silently evicting an unreviewed suggestion.
        check(rows.length() < 250)
        rows.put(row)
        write(c, rows)
    }
    @Synchronized fun ack(c: Context, ids: Set<String>) {
        val old = read(c); val rows = JSONArray()
        for (i in 0 until old.length()) if (!ids.contains(old.getJSONObject(i).getString("id"))) rows.put(old.getJSONObject(i))
        write(c, rows)
    }
}

class FinancialNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val prefs = getSharedPreferences("nexo_automation", 0)
        if (!prefs.getBoolean("enabled", false)) return
        // Learn source identities only, never unapproved notification content.
        val observed = prefs.getStringSet("observed_apps", emptySet())!!.toMutableSet()
        if (observed.size < 100 && observed.add(sbn.packageName)) prefs.edit().putStringSet("observed_apps", observed).apply()
        if (!prefs.getStringSet("apps", emptySet())!!.contains(sbn.packageName)) return
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val now = System.currentTimeMillis()
        if (sbn.postTime < now - 7 * 86400000L || sbn.postTime > now + 60000L) return
        val extras = sbn.notification.extras
        val text = listOf(extras.getCharSequence(Notification.EXTRA_TITLE),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            .filterNotNull().joinToString(" ")
        val item = FinancialNotificationParser.parse(text) ?: return
        val eventTime = sbn.notification.`when`.takeIf { it >= now - 7 * 86400000L && it <= now + 60000L } ?: sbn.postTime
        try {
            FinancialInboxQueue.add(this, JSONObject().put("id", FinancialNotificationParser.fingerprint(sbn.packageName, sbn.key, eventTime, item))
                .put("app_id", sbn.packageName).put("amount_cents", item.cents)
                .put("description", item.description).put("kind", item.kind).put("medium", item.medium)
                .put("occurred_at", eventTime))
            prefs.edit().remove("queue_error").apply()
        } catch (_: Exception) {
            // No raw payload or financial fields in logs, even on failure.
            prefs.edit().putBoolean("queue_error", true).apply()
        }
    }
}
