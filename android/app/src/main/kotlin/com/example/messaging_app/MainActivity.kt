// android/app/src/main/kotlin/com/example/messaging_app/MainActivity.kt

package com.example.messaging_app

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        makeAppVisibleForIncomingCall()
        createCallNotificationChannel()
    }

    override fun onResume() {
        super.onResume()
        makeAppVisibleForIncomingCall()
    }

    private fun makeAppVisibleForIncomingCall() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            val keyguardManager =
                getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager

            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
    }

    private fun createCallNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channelId = "call_channel"
        val channelName = "Incoming Calls"

        /*
         * This uses:
         * android/app/src/main/res/raw/incoming_call.mp3
         *
         * If that file does not exist, Android will still create the channel,
         * but custom ringtone may not play.
         */
        val soundUri = Uri.parse(
            "android.resource://$packageName/raw/incoming_call"
        )

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Incoming call alerts"
            setSound(soundUri, audioAttributes)
            enableVibration(true)
            enableLights(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC

            /*
             * Allows ringtone to play even when Do Not Disturb policy allows it.
             * Some devices still require user permission from notification settings.
             */
            try {
                setBypassDnd(true)
            } catch (_: Exception) {
            }
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }
}