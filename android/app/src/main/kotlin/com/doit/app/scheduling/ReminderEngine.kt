package com.doit.app.scheduling

import com.doit.app.db.OccurrenceRow
import com.doit.app.db.OccurrenceStatus
import com.doit.app.db.ReminderRow
import com.doit.app.db.ReminderStore
import java.time.LocalDate
import java.time.ZoneId

/** Current time and zone; injected so tests can freeze both. */
interface EngineClock {
    fun nowMillis(): Long
    fun zone(): ZoneId
}

class SystemEngineClock : EngineClock {
    override fun nowMillis(): Long = System.currentTimeMillis()
    override fun zone(): ZoneId = ZoneId.systemDefault()
}

/** The one pending alarm per reminder. */
interface AlarmGateway {
    fun schedule(reminderId: Long, fireAtMillis: Long, occurrenceDate: LocalDate)
    fun cancel(reminderId: Long)
}

/** The one visible notification per reminder. */
interface NotificationGateway {
    fun show(reminder: ReminderRow, occurrence: OccurrenceRow, nextFireAtMillis: Long?)
    fun cancel(reminderId: Long)
}

interface EngineLogger {
    fun d(message: String)
    fun w(message: String, error: Throwable? = null)
}

object NoopLogger : EngineLogger {
    override fun d(message: String) = Unit
    override fun w(message: String, error: Throwable?) = Unit
}

/**
 * The heart of Do It. Runs entirely outside of Flutter, from BroadcastReceivers,
 * and owns the whole notification lifecycle:
 *
 *  - [onAlarmFired]: AlarmManager woke us. Create/load the day's occurrence,
 *    show (or refresh) the notification if it is still active, then set the
 *    *next* alarm. Exactly one alarm is pending per reminder at any time, so
 *    there is never a backlog and never thousands of alarms.
 *  - [complete]: the user tapped Done (from the notification or from the app).
 *    Mark the occurrence completed, remove the notification, and jump to the
 *    next window.
 *  - [scheduleNext]: recompute from the database and set the next alarm.
 *  - [rescheduleAll]: boot, app update, time/zone change, app start.
 *
 * All decisions are derived from the shared database, so Flutter and the
 * engine can never disagree about what is scheduled.
 */
class ReminderEngine(
    private val store: ReminderStore,
    private val alarms: AlarmGateway,
    private val notifier: NotificationGateway,
    private val clock: EngineClock,
    private val log: EngineLogger = NoopLogger,
) {

    fun onAlarmFired(reminderId: Long, occurrenceDate: LocalDate?, intendedFireAtMillis: Long) {
        val now = clock.nowMillis()
        val zone = clock.zone()
        store.expireStaleOccurrences(now)

        val reminder = store.getReminder(reminderId)
        if (reminder == null || !reminder.enabled) {
            log.d("Alarm for $reminderId ignored: ${if (reminder == null) "deleted" else "disabled"}")
            alarms.cancel(reminderId)
            notifier.cancel(reminderId)
            return
        }
        val rule = reminder.rule()

        // The alarm carries the date it was scheduled for. Only notify when the
        // delivery still falls inside that window (a delivery delayed past the
        // end of the window is dropped rather than shown as a stale backlog).
        val window = occurrenceDate
            ?.takeIf { rule.includes(it.dayOfWeek) }
            ?.let { ScheduleCalculator.windowFor(rule, zone, it) }
            ?.takeIf { it.contains(now) }
            ?: ScheduleCalculator.currentWindow(rule, zone, now)

        if (window != null) {
            val occurrence = store.getOccurrence(reminderId, window.date)
                ?: store.insertOccurrence(
                    reminderId, window.date, OccurrenceStatus.ACTIVE,
                    window.startMillis, window.endMillis, null,
                )
            if (occurrence.status == OccurrenceStatus.ACTIVE) {
                val after = maxOf(now, intendedFireAtMillis)
                val next = ScheduleCalculator.nextFireAfter(rule, zone, after) { isClosed(reminderId, it) }
                val nextInSameWindow = next?.takeIf { it.window.date == window.date }?.atMillis
                val updated = store.recordNotification(occurrence.id, now)
                notifier.show(reminder, updated, nextInSameWindow)
                log.d("Notified reminder $reminderId (#${updated.notificationCount} for ${window.date})")
            } else {
                log.d("Occurrence ${window.date} of $reminderId is ${occurrence.status}; not notifying")
            }
        } else {
            log.d("Alarm for $reminderId delivered outside any window; not notifying")
        }

        scheduleNext(reminderId, maxOf(now, intendedFireAtMillis))
    }

    /**
     * Marks the occurrence as completed. [occurrenceDate] comes from the
     * notification's Done action so that a late tap (after the window ended)
     * still completes the right day; from the app it may be null.
     */
    fun complete(reminderId: Long, occurrenceDate: LocalDate?) {
        val now = clock.nowMillis()
        val zone = clock.zone()
        val reminder = store.getReminder(reminderId)
        if (reminder == null) {
            cancel(reminderId)
            return
        }
        val rule = reminder.rule()
        val window = occurrenceDate?.let { ScheduleCalculator.windowFor(rule, zone, it) }
            ?: ScheduleCalculator.currentWindow(rule, zone, now)
            ?: ScheduleCalculator.mostRecentStartedWindow(rule, zone, now)

        if (window != null) {
            val existing = store.getOccurrence(reminderId, window.date)
            if (existing == null) {
                store.insertOccurrence(
                    reminderId, window.date, OccurrenceStatus.COMPLETED,
                    window.startMillis, window.endMillis, now,
                )
            } else if (existing.status != OccurrenceStatus.COMPLETED) {
                store.updateOccurrenceStatus(existing.id, OccurrenceStatus.COMPLETED, now)
            }
            log.d("Completed ${window.date} of reminder $reminderId")
        }
        notifier.cancel(reminderId)
        scheduleNext(reminderId, now)
    }

    /** Cancels the pending alarm and computes + schedules the next fire. */
    fun scheduleNext(reminderId: Long, afterMillis: Long = clock.nowMillis()) {
        alarms.cancel(reminderId)
        val reminder = store.getReminder(reminderId)
        if (reminder == null || !reminder.enabled) {
            notifier.cancel(reminderId)
            return
        }
        val zone = clock.zone()
        val rule = reminder.rule()

        // A notification for an occurrence that is no longer active must not linger.
        ScheduleCalculator.currentWindow(rule, zone, afterMillis)?.let { current ->
            val occurrence = store.getOccurrence(reminderId, current.date)
            if (occurrence != null && occurrence.status.isClosed) notifier.cancel(reminderId)
        }

        val next = ScheduleCalculator.nextFireAfter(rule, zone, afterMillis) { isClosed(reminderId, it) }
        if (next == null) {
            log.d("Reminder $reminderId has no upcoming fire")
            return
        }
        alarms.schedule(reminderId, next.atMillis, next.window.date)
        log.d("Reminder $reminderId next fire at ${next.atMillis} (${next.window.date})")
    }

    /** Disable / delete: nothing pending, nothing visible. */
    fun cancel(reminderId: Long) {
        alarms.cancel(reminderId)
        notifier.cancel(reminderId)
    }

    /** Boot, package replaced, time or zone changed, app start. */
    fun rescheduleAll() {
        val now = clock.nowMillis()
        store.expireStaleOccurrences(now)
        for (reminder in store.getAllReminders()) {
            if (reminder.enabled) scheduleNext(reminder.id, now) else cancel(reminder.id)
        }
    }

    private fun isClosed(reminderId: Long, date: LocalDate): Boolean =
        store.getOccurrence(reminderId, date)?.status?.isClosed ?: false
}
