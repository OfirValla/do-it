package com.doit.app.notifications

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.text.format.DateFormat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.doit.app.MainActivity
import com.doit.app.R
import com.doit.app.db.OccurrenceRow
import com.doit.app.db.ReminderRow
import com.doit.app.receivers.DoItIntents
import com.doit.app.receivers.NotificationActionReceiver
import com.doit.app.scheduling.NotificationGateway
import java.time.LocalDate
import java.util.Date

/**
 * Everything needed to render a reminder notification, independent of the
 * database so the ring service can re-post it after ringing ends.
 */
data class NotificationContent(
    val reminderId: Long,
    val occurrenceDate: LocalDate,
    val title: String,
    val text: String,
    val bigText: String,
    val count: Int,
    val nextFireAtMillis: Long?,
    val ringMinutes: Int,
) {
    fun writeTo(intent: Intent): Intent = intent
        .putExtra(DoItIntents.EXTRA_REMINDER_ID, reminderId)
        .putExtra(DoItIntents.EXTRA_OCCURRENCE_DATE, occurrenceDate.toString())
        .putExtra(DoItIntents.EXTRA_TITLE, title)
        .putExtra(DoItIntents.EXTRA_TEXT, text)
        .putExtra(DoItIntents.EXTRA_BIG_TEXT, bigText)
        .putExtra(DoItIntents.EXTRA_COUNT, count)
        .putExtra(DoItIntents.EXTRA_NEXT_FIRE_AT, nextFireAtMillis ?: -1L)
        .putExtra(DoItIntents.EXTRA_RING_MINUTES, ringMinutes)

    companion object {
        fun fromIntent(intent: Intent): NotificationContent? {
            val reminderId = intent.getLongExtra(DoItIntents.EXTRA_REMINDER_ID, -1L)
            if (reminderId < 0) return null
            val date = intent.getStringExtra(DoItIntents.EXTRA_OCCURRENCE_DATE)
                ?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: LocalDate.now()
            val next = intent.getLongExtra(DoItIntents.EXTRA_NEXT_FIRE_AT, -1L)
            return NotificationContent(
                reminderId = reminderId,
                occurrenceDate = date,
                title = intent.getStringExtra(DoItIntents.EXTRA_TITLE) ?: "Reminder",
                text = intent.getStringExtra(DoItIntents.EXTRA_TEXT) ?: "",
                bigText = intent.getStringExtra(DoItIntents.EXTRA_BIG_TEXT) ?: "",
                count = intent.getIntExtra(DoItIntents.EXTRA_COUNT, 0),
                nextFireAtMillis = if (next > 0) next else null,
                ringMinutes = intent.getIntExtra(DoItIntents.EXTRA_RING_MINUTES, 0),
            )
        }
    }
}

/**
 * Builds and posts the reminder notification:
 *
 *     DO IT
 *     Call Mom
 *     You haven't completed this yet. Next reminder at 11:00.
 *     [ ✓ DONE ]   [ STOP ]          (Stop only while ringing)
 *
 * Reminders with `ringMinutes > 0` are handed to [AlarmRingService], which rings
 * like an alarm clock and owns the notification while it does. The Done action
 * is a broadcast to [NotificationActionReceiver], so it works with the Flutter
 * process dead and from the lock screen.
 */
class ReminderNotifier(context: Context) : NotificationGateway {

    private val context = context.applicationContext

    companion object {
        /** Quiet reminders: default notification sound. */
        const val CHANNEL_ID = "do_it_reminders"

        /** Ringing reminders: silent channel, the sound is played by AlarmRingService. */
        const val ALARM_CHANNEL_ID = "do_it_alarms"

        private const val BRAND_COLOR = 0xFF6B4EFF.toInt()
        private const val STATUS_TEXT = "You haven't completed this yet."

        fun ensureChannels(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Reminders", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Reminders that come back until you mark them done."
                        enableVibration(true)
                        setShowBadge(true)
                        lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    },
                )
            }
            if (manager.getNotificationChannel(ALARM_CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(ALARM_CHANNEL_ID, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Reminders that ring like an alarm clock until you tap Done or Stop."
                        setSound(null, null) // AlarmRingService plays the alarm sound itself.
                        enableVibration(false)
                        setShowBadge(true)
                        lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                    },
                )
            }
        }

        /** Kept for callers that only need the default channel to exist. */
        fun ensureChannel(context: Context) = ensureChannels(context)

        fun canUseFullScreenIntent(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return manager.canUseFullScreenIntent()
        }
    }

    override fun show(reminder: ReminderRow, occurrence: OccurrenceRow, nextFireAtMillis: Long?) {
        ensureChannels(context)
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        val content = contentFor(reminder, occurrence, nextFireAtMillis)
        if (reminder.ringMinutes > 0 && AlarmRingService.start(context, content)) return
        post(content, ringing = false)
    }

    override fun cancel(reminderId: Long) {
        AlarmRingService.stopIfRinging(context, reminderId, repostNotification = false)
        NotificationManagerCompat.from(context).cancel(NotificationIds.notificationId(reminderId))
    }

    /** Posts (or replaces) the notification for [content]. */
    @SuppressLint("MissingPermission")
    fun post(content: NotificationContent, ringing: Boolean) {
        ensureChannels(context)
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        manager.notify(NotificationIds.notificationId(content.reminderId), build(content, ringing))
    }

    /** The "Send a test alarm" button in Settings. */
    fun showTest(ringMinutes: Int) {
        val now = System.currentTimeMillis()
        val content = NotificationContent(
            reminderId = NotificationIds.TEST_REMINDER_ID,
            occurrenceDate = LocalDate.now(),
            title = "Do It is working",
            text = "This is what a reminder looks like. Tap Done or Stop.",
            bigText = "This is what a reminder looks like.\n\nIt rings for $ringMinutes minute" +
                (if (ringMinutes == 1) "" else "s") + " unless you tap Done or Stop.",
            count = 1,
            nextFireAtMillis = null,
            ringMinutes = ringMinutes,
        )
        ensureChannels(context)
        if (ringMinutes > 0 && AlarmRingService.start(context, content)) return
        post(content.copy(nextFireAtMillis = now), ringing = false)
    }

    fun contentFor(reminder: ReminderRow, occurrence: OccurrenceRow, nextFireAtMillis: Long?): NotificationContent {
        val timeFormat = DateFormat.getTimeFormat(context)
        val nextText = if (nextFireAtMillis != null) {
            "Next reminder at ${timeFormat.format(Date(nextFireAtMillis))}."
        } else {
            "This was the last reminder for today."
        }
        val text = if (reminder.description.isNotBlank()) reminder.description else STATUS_TEXT
        val bigText = buildString {
            if (reminder.description.isNotBlank()) {
                append(reminder.description)
                append("\n\n")
            }
            append(STATUS_TEXT)
            append(' ')
            append(nextText)
        }
        return NotificationContent(
            reminderId = reminder.id,
            occurrenceDate = occurrence.date,
            title = reminder.title,
            text = text,
            bigText = bigText,
            count = occurrence.notificationCount,
            nextFireAtMillis = nextFireAtMillis,
            ringMinutes = reminder.ringMinutes,
        )
    }

    fun build(content: NotificationContent, ringing: Boolean): Notification {
        val id = content.reminderId
        val builder = NotificationCompat.Builder(context, if (ringing) ALARM_CHANNEL_ID else CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_do_it)
            .setColor(BRAND_COLOR)
            .setSubText("DO IT")
            .setContentTitle(content.title)
            .setContentText(if (ringing) "Ringing · ${content.text}" else content.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content.bigText))
            .setCategory(if (ringing) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(false)
            .setOngoing(ringing)
            .setAutoCancel(!ringing)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setNumber(content.count)
            .setContentIntent(openIntent(id, fullScreen = false))
            .addAction(R.drawable.ic_action_done, "✓ Done", doneIntent(content))

        if (ringing) {
            builder.addAction(R.drawable.ic_action_done, "Stop", stopIntent(id))
            if (canUseFullScreenIntent(context)) {
                builder.setFullScreenIntent(openIntent(id, fullScreen = true), true)
            }
        } else {
            builder.setDefaults(NotificationCompat.DEFAULT_ALL)
        }
        return builder.build()
    }

    private fun doneIntent(content: NotificationContent): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java)
            .setAction(DoItIntents.ACTION_DONE)
            .setData(Uri.parse(DoItIntents.doneUri(content.reminderId)))
            .putExtra(DoItIntents.EXTRA_REMINDER_ID, content.reminderId)
            .putExtra(DoItIntents.EXTRA_OCCURRENCE_DATE, content.occurrenceDate.toString())
        return PendingIntent.getBroadcast(
            context,
            NotificationIds.doneRequestCode(content.reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun stopIntent(reminderId: Long): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java)
            .setAction(DoItIntents.ACTION_STOP_RINGING)
            .setData(Uri.parse(DoItIntents.stopUri(reminderId)))
            .putExtra(DoItIntents.EXTRA_REMINDER_ID, reminderId)
        return PendingIntent.getBroadcast(
            context,
            NotificationIds.doneRequestCode(reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openIntent(reminderId: Long, fullScreen: Boolean): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse(if (fullScreen) DoItIntents.fullScreenUri(reminderId) else DoItIntents.openUri(reminderId)))
            .putExtra(DoItIntents.EXTRA_REMINDER_ID, reminderId)
            .putExtra(DoItIntents.EXTRA_FULL_SCREEN, fullScreen)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        return PendingIntent.getActivity(
            context,
            NotificationIds.openRequestCode(reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
