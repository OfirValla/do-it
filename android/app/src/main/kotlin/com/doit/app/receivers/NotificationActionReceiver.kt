package com.doit.app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.doit.app.notifications.AlarmRingService
import com.doit.app.scheduling.Engine
import java.time.LocalDate

/**
 * Handles the notification actions without involving Flutter:
 *
 *  - **✓ Done**: marks the occurrence completed in the shared database, stops
 *    any ringing, removes the notification and schedules the next window.
 *  - **Stop**: silences the alarm but keeps the reminder active; the quiet
 *    notification stays and the next interval rings again.
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val reminderId = intent.getLongExtra(DoItIntents.EXTRA_REMINDER_ID, -1L)
        when (intent.action) {
            DoItIntents.ACTION_DONE -> {
                if (reminderId < 0) return
                val occurrenceDate = intent.getStringExtra(DoItIntents.EXTRA_OCCURRENCE_DATE)
                    ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                // Silence immediately; the engine removes the notification.
                AlarmRingService.stopIfRinging(context, reminderId, repostNotification = false)
                Engine.runFromReceiver(this, context, "done for reminder $reminderId") { engine ->
                    engine.complete(reminderId, occurrenceDate)
                }
            }
            DoItIntents.ACTION_STOP_RINGING -> {
                AlarmRingService.stop(context, repostNotification = true)
            }
        }
    }
}
