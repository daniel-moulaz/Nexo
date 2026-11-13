package com.ma.expensy

import android.app.Application
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Sets up Firebase by hand (no google-services.json in the repository). */
class NexoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NexoBackground.initFirebase(this)
    }
}

/**
 * The server's silent message after the assistant asks for something. It
 * carries no data about the request: it only wakes the worker, which reads
 * the queue with this device's own session.
 */
class NexoPushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["kind"] == "queue") NexoBackground.runNow(applicationContext, "push")
    }

    override fun onNewToken(token: String) {
        NexoBackground.rememberToken(applicationContext, token)
    }
}
