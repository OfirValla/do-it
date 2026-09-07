package com.doit.app.receivers

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.doit.app.scheduling.Engine

/**
 * Rebuilds the alarm chain after events that invalidate it:
 *  - BOOT_COMPLETED: alarms do not survive a reboot.
 *  - MY_PACKAGE_REPLACED: alarms are cleared on app update.
 *  - TIMEZONE_CHANGED / TIME_SET: wall-clock schedules must be recomputed.
 *  - SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED: switch to exact alarms as
 *    soon as the user grants the permission.
 *
 * The user never has to open the app for any of this.
 */
class SystemEventReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in HANDLED_ACTIONS) return
        Engine.runFromReceiver(this, context, "reschedule after $action") { engine ->
            engine.rescheduleAll()
        }
    }

    private companion object {
        val HANDLED_ACTIONS: Set<String> = buildSet {
            add(Intent.ACTION_BOOT_COMPLETED)
            add(Intent.ACTION_MY_PACKAGE_REPLACED)
            add(Intent.ACTION_TIMEZONE_CHANGED)
            add(Intent.ACTION_TIME_CHANGED)
            add("android.intent.action.QUICKBOOT_POWERON")
            add("com.htc.intent.action.QUICKBOOT_POWERON")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)
            }
        }
    }
}
