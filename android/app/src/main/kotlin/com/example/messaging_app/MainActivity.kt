// android/app/src/main/kotlin/com/example/messaging_app/MainActivity.kt

package com.example.messaging_app

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.res.Configuration
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val nativePipChannelName = "messaging_app/native_pip"
    private var nativePipChannel: MethodChannel? = null

    /*
     * Flutter updates this using setCallActive.
     *
     * Android PiP is allowed ONLY when this is true.
     * This prevents ChatList/Dashboard/Profile from being captured into PiP
     * after a call ends.
     */
    private var callActiveFromFlutter: Boolean = false
    private var wasInPictureInPicture: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nativePipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            nativePipChannelName
        )

        nativePipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipAvailable" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }

                "setCallActive" -> {
                    callActiveFromFlutter = when (val value = call.arguments) {
                        is Boolean -> value
                        is String -> value.equals("true", ignoreCase = true) || value == "1"
                        is Number -> value.toInt() == 1
                        else -> false
                    }

                    result.success(true)
                }

                "enterCallPip" -> {
                    val entered = enterCallPictureInPicture()
                    result.success(entered)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        makeAppVisibleForIncomingCall()
        createCallNotificationChannel()
    }

    override fun onResume() {
        super.onResume()

        makeAppVisibleForIncomingCall()

        /*
         * If user expanded/tapped PiP and call is still active,
         * Flutter must open CallScreen, not ChatList.
         */
        if (wasInPictureInPicture || callActiveFromFlutter) {
            nativePipChannel?.invokeMethod("onActivityResume", null)
        }

        wasInPictureInPicture = false
    }

    override fun onUserLeaveHint() {
        /*
         * Manual PiP only.
         *
         * Never let Android enter PiP from ChatList/Dashboard/Profile
         * unless Flutter says an active call exists.
         */
        if (callActiveFromFlutter) {
            nativePipChannel?.invokeMethod("onUserLeaveHint", null)
        }
        /*
         * If no active call, do nothing.
         * That means normal Home/back from ChatList/Profile/Dashboard never
         * creates any call overlay/PiP.
         */

        super.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)

        wasInPictureInPicture = isInPictureInPictureMode

        if (isInPictureInPictureMode) {
            nativePipChannel?.invokeMethod("onPipEntered", null)
        } else {
            nativePipChannel?.invokeMethod("onPipExited", null)
        }
    }

    private fun enterCallPictureInPicture(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }

        if (!callActiveFromFlutter) {
            return false
        }

        return try {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))

            /*
             * DO NOT call setAutoEnterEnabled(true).
             *
             * Auto PiP is what causes normal screens to appear in PiP after
             * the call has ended.
             */
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(false)
                builder.setSeamlessResizeEnabled(true)
            }

            enterPictureInPictureMode(builder.build())
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
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

            try {
                setBypassDnd(true)
            } catch (_: Exception) {
            }
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }
}
