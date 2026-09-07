package com.doit.app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.doit.app.scheduling.Engine
import java.time.LocalDate

/**
 * Woken by AlarmManager at each scheduled notification time. Shows the
 * notification (if the occurrence is still active) and schedules the next one.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DoItIntents.ACTION_FIRE) return
        val reminderId = intent.getLongExtra(DoItIntents.EXTRA_REMINDER_ID, -1L)
        if (reminderId < 0) return
        val occurrenceDate = intent.getStringExtra(DoItIntents.EXTRA_OCCURRENCE_DATE)
            ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        val fireAt = intent.getLongExtra(DoItIntents.EXTRA_FIRE_AT, 0L)

        Engine.runFromReceiver(this, context, "alarm for reminder $reminderId") { engine ->
            engine.onAlarmFired(reminderId, occurrenceDate, fireAt)
        }
    }
}
