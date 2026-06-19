// android/app/src/main/kotlin/com/example/messaging_app/MainActivity.kt

package com.johnworkspace.hiddenly

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
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

    private val systemRingtoneChannelName = "hiddenly/system_ringtone"
    private var systemRingtoneChannel: MethodChannel? = null
    private var ringtone: Ringtone? = null

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
                "isPipAvailable" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)

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

        systemRingtoneChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            systemRingtoneChannelName
        )

        systemRingtoneChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    startSystemRingtone()
                    result.success(true)
                }

                "stop" -> {
                    stopSystemRingtone()
                    result.success(true)
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

        if (wasInPictureInPicture || callActiveFromFlutter) {
            nativePipChannel?.invokeMethod("onActivityResume", null)
        }

        wasInPictureInPicture = false
    }

    override fun onDestroy() {
        stopSystemRingtone()
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        if (callActiveFromFlutter) {
            nativePipChannel?.invokeMethod("onUserLeaveHint", null)
        }

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
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (!callActiveFromFlutter) return false

        return try {
            val builder = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))

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
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun startSystemRingtone() {
        try {
            stopSystemRingtone()

            val ringtoneUri = RingtoneManager.getDefaultUri(
                RingtoneManager.TYPE_RINGTONE
            )

            ringtone = RingtoneManager.getRingtone(
                applicationContext,
                ringtoneUri
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                ringtone?.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            }

            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopSystemRingtone() {
        try {
            ringtone?.stop()
            ringtone = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createCallNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channelId = "call_channel_v2"
        val channelName = "Incoming Calls"

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val systemRingtoneUri = RingtoneManager.getDefaultUri(
            RingtoneManager.TYPE_RINGTONE
        )

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Incoming call alerts"
            setSound(systemRingtoneUri, audioAttributes)
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