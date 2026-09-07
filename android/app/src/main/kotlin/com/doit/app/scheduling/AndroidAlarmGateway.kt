package com.doit.app.scheduling

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import com.doit.app.notifications.NotificationIds
import com.doit.app.receivers.AlarmReceiver
import com.doit.app.receivers.DoItIntents
import java.time.LocalDate

/**
 * [AlarmGateway] on top of AlarmManager.
 *
 * One PendingIntent per reminder (request code = reminder id, data URI
 * `doit://reminder/{id}/alarm`), always replaced with FLAG_UPDATE_CURRENT so the
 * occurrence date and intended fire time travel as fresh extras.
 *
 * Exact alarms (`setExactAndAllowWhileIdle`) are used whenever permitted; they
 * wake the device from Doze at the requested minute. Without the permission we
 * fall back to `setAndAllowWhileIdle`, which Android may defer by several
 * minutes; Settings tells the user how to fix that.
 */
class AndroidAlarmGateway(context: Context) : AlarmGateway {

    private val context = context.applicationContext
    private val alarmManager: AlarmManager
        get() = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    override fun schedule(reminderId: Long, fireAtMillis: Long, occurrenceDate: LocalDate) {
        val pendingIntent = pendingIntent(reminderId, occurrenceDate, fireAtMillis)
        val manager = alarmManager
        if (canScheduleExactAlarms()) {
            try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pendingIntent)
                return
            } catch (e: SecurityException) {
                Log.w(TAG, "Exact alarm rejected, falling back to inexact", e)
            }
        }
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMillis, pendingIntent)
    }

    override fun cancel(reminderId: Long) {
        val pendingIntent = pendingIntent(reminderId, null, 0L)
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun pendingIntent(reminderId: Long, date: LocalDate?, fireAtMillis: Long): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java)
            .setAction(DoItIntents.ACTION_FIRE)
            .setData(Uri.parse(DoItIntents.alarmUri(reminderId)))
            .putExtra(DoItIntents.EXTRA_REMINDER_ID, reminderId)
            .putExtra(DoItIntents.EXTRA_FIRE_AT, fireAtMillis)
        if (date != null) intent.putExtra(DoItIntents.EXTRA_OCCURRENCE_DATE, date.toString())
        return PendingIntent.getBroadcast(
            context,
            NotificationIds.alarmRequestCode(reminderId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        const val TAG = "DoIt.Alarms"
    }
}
