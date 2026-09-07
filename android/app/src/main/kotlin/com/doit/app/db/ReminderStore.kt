package com.doit.app.db

import com.doit.app.scheduling.ScheduleCalculator
import java.time.LocalDate

/** Mirror of the Drift `reminders` table (see lib/core/database/tables.dart). */
data class ReminderRow(
    val id: Long,
    val title: String,
    val description: String,
    val startMinutes: Int,
    val endMinutes: Int,
    val intervalMinutes: Int,
    val daysMask: Int,
    val enabled: Boolean,
    /** 0 = notification only, 1..5 = ring like an alarm clock for that many minutes. */
    val ringMinutes: Int = DEFAULT_RING_MINUTES,
) {
    fun rule(): ScheduleCalculator.Rule =
        ScheduleCalculator.Rule(startMinutes, endMinutes, intervalMinutes, daysMask)

    companion object {
        const val DEFAULT_RING_MINUTES = 2
        const val MAX_RING_MINUTES = 5
    }
}

/** Values of `occurrences.status`, shared with `OccurrenceStatus` in Dart. */
enum class OccurrenceStatus(val dbValue: String) {
    ACTIVE("active"),
    COMPLETED("completed"),
    EXPIRED("expired");

    val isClosed: Boolean get() = this != ACTIVE

    companion object {
        fun fromDb(value: String?): OccurrenceStatus =
            entries.firstOrNull { it.dbValue == value } ?: ACTIVE
    }
}

/** Mirror of the Drift `occurrences` table. */
data class OccurrenceRow(
    val id: Long,
    val reminderId: Long,
    val date: LocalDate,
    val status: OccurrenceStatus,
    val windowStartMillis: Long,
    val windowEndMillis: Long,
    val completedAtMillis: Long?,
    val notificationCount: Int,
    val lastNotifiedAtMillis: Long?,
)

/**
 * Persistence boundary of the native engine. Implemented by [SqliteReminderStore]
 * in production and by in-memory fakes in unit tests.
 */
interface ReminderStore {
    fun getAllReminders(): List<ReminderRow>

    fun getReminder(id: Long): ReminderRow?

    fun getOccurrence(reminderId: Long, date: LocalDate): OccurrenceRow?

    fun insertOccurrence(
        reminderId: Long,
        date: LocalDate,
        status: OccurrenceStatus,
        windowStartMillis: Long,
        windowEndMillis: Long,
        completedAtMillis: Long?,
    ): OccurrenceRow

    fun updateOccurrenceStatus(id: Long, status: OccurrenceStatus, completedAtMillis: Long?)

    /** Increments the notification counter and returns the updated row. */
    fun recordNotification(id: Long, atMillis: Long): OccurrenceRow

    /** Marks active occurrences whose window ended before [nowMillis] as expired. */
    fun expireStaleOccurrences(nowMillis: Long): Int
}
