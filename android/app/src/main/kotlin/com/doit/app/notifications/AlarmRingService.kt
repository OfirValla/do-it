package com.doit.app.notifications

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.doit.app.channel.FlutterBridge
import com.doit.app.db.ReminderRow
import com.doit.app.receivers.DoItIntents

/**
 * Rings like an alarm clock: loops the device's alarm sound on the alarm
 * stream and vibrates until the user taps Done or Stop, or until the
 * reminder's ring duration (1..5 minutes) elapses.
 *
 * It is a foreground service because Android only lets audio keep playing in
 * the background from one, and its notification *is* the reminder notification
 * (same id), so nothing is duplicated. Starting a foreground service from the
 * background is permitted here because the trigger is an exact alarm the user
 * scheduled; if Android refuses anyway (inexact alarms, vendor restrictions),
 * [start] returns false and the caller posts a regular notification instead.
 *
 * When ringing ends without Done, the notification stays in the tray as a
 * normal reminder notification and the next interval rings again.
 */
class AlarmRingService : Service() {

    companion object {
        private const val TAG = "DoIt.Ring"
        private const val WAKE_LOCK_MARGIN_MILLIS = 15_000L

        /** Reminder currently ringing, or null. Read by the platform channel. */
        @Volatile
        var ringingReminderId: Long? = null
            private set

        @Volatile
        private var instance: AlarmRingService? = null

        /** Starts (or re-targets) the ringing. Returns false if Android refused. */
        fun start(context: Context, content: NotificationContent): Boolean {
            val intent = Intent(context, AlarmRingService::class.java)
                .setAction(DoItIntents.ACTION_RING)
            content.writeTo(intent)
            return try {
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException (API 31+) or vendor quirks.
                Log.w(TAG, "Cannot start the ringing service", e)
                false
            }
        }

        /**
         * Stops ringing. With [repostNotification] the reminder notification is
         * re-posted in its quiet form (Stop tapped or time elapsed); without it
         * the notification is removed (Done, disable, delete).
         */
        fun stop(context: Context, repostNotification: Boolean) {
            instance?.repostOnStop = repostNotification
            context.stopService(Intent(context, AlarmRingService::class.java))
        }

        fun stopIfRinging(context: Context, reminderId: Long, repostNotification: Boolean) {
            if (ringingReminderId == reminderId) stop(context, repostNotification)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val stopRunnable = Runnable { stopSelf() }
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var content: NotificationContent? = null

    @Volatile
    var repostOnStop: Boolean = true

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val next = intent?.let { NotificationContent.fromIntent(it) }
        if (next == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val notifier = ReminderNotifier(this)

        // A different reminder was ringing: leave its quiet notification behind.
        content?.let { previous ->
            if (previous.reminderId != next.reminderId) notifier.post(previous, ringing = false)
        }
        content = next
        repostOnStop = true

        // Must happen within seconds of startForegroundService().
        val notification = notifier.build(next, ringing = true)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        } else {
            0
        }
        ServiceCompat.startForeground(this, NotificationIds.notificationId(next.reminderId), notification, type)
        ringingReminderId = next.reminderId

        val minutes = next.ringMinutes.coerceIn(1, ReminderRow.MAX_RING_MINUTES)
        val durationMillis = minutes * 60_000L
        acquireWakeLock(durationMillis + WAKE_LOCK_MARGIN_MILLIS)
        startSound()
        startVibration()
        handler.removeCallbacks(stopRunnable)
        handler.postDelayed(stopRunnable, durationMillis)

        FlutterBridge.notifyRinging(next.reminderId)
        Log.d(TAG, "Ringing for reminder ${next.reminderId} ($minutes min)")
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopRunnable)
        stopSound()
        stopVibration()
        releaseWakeLock()

        val finished = content
        val repost = repostOnStop
        content = null
        ringingReminderId = null
        instance = null

        if (repost && finished != null) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
            ReminderNotifier(this).post(finished, ringing = false)
        } else {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        }
        FlutterBridge.notifyRinging(null)
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Sound, vibration, wake lock
    // -------------------------------------------------------------------------

    private fun startSound() {
        stopSound()
        val candidates: List<Uri> = listOfNotNull(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
        )
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        for (uri in candidates) {
            val mediaPlayer = MediaPlayer()
            try {
                mediaPlayer.setAudioAttributes(attributes)
                mediaPlayer.setDataSource(this, uri)
                mediaPlayer.isLooping = true
                mediaPlayer.prepare()
                mediaPlayer.start()
                player = mediaPlayer
                return
            } catch (e: Exception) {
                Log.w(TAG, "Alarm sound $uri unavailable", e)
                mediaPlayer.release()
            }
        }
        Log.w(TAG, "No alarm sound could be played; vibrating only")
    }

    private fun stopSound() {
        player?.let {
            try {
                if (it.isPlaying) it.stop()
            } catch (ignored: IllegalStateException) {
                // Already stopped.
            }
            it.release()
        }
        player = null
    }

    private fun startVibration() {
        val service = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (!service.hasVibrator()) return
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 700, 500, 700, 1200), 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            service.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION")
            service.vibrate(
                effect,
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
            )
        }
        vibrator = service
    }

    private fun stopVibration() {
        vibrator?.cancel()
        vibrator = null
    }

    private fun acquireWakeLock(timeoutMillis: Long) {
        releaseWakeLock()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DoIt:ring").apply {
            setReferenceCounted(false)
            acquire(timeoutMillis)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
