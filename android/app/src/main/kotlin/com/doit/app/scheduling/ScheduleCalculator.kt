package com.doit.app.scheduling

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Timezone-aware scheduling math. Mirrors `ScheduleCalculator` in
 * lib/core/scheduling/schedule_calculator.dart line by line; keep both in sync.
 *
 * Semantics:
 *  * Windows and fire times are defined on the wall clock of the zone.
 *  * Fire times are `start + k * interval` while inside the window (end included
 *    when it lands on the grid).
 *  * Non-existent wall-clock times (DST gap) shift forward by the gap, ambiguous
 *    times resolve to the earlier offset (java.time semantics).
 *  * Fire times collapsing onto the same instant are de-duplicated.
 *
 * Pure JVM code (no Android imports) so it can be unit tested on the host.
 */
object ScheduleCalculator {
    const val MINUTES_PER_DAY = 24 * 60
    const val LOOK_BACK_DAYS = 1
    const val LOOK_AHEAD_DAYS = 7

    data class Rule(
        val startMinutes: Int,
        val endMinutes: Int,
        val intervalMinutes: Int,
        val daysMask: Int,
    ) {
        val crossesMidnight: Boolean get() = endMinutes <= startMinutes

        val windowLengthMinutes: Int
            get() = if (crossesMidnight) endMinutes + MINUTES_PER_DAY - startMinutes else endMinutes - startMinutes

        val hasAnyDay: Boolean get() = daysMask != 0

        /** Monday = bit 0 ... Sunday = bit 6, same as [DayOfWeek.getValue] - 1. */
        fun includes(day: DayOfWeek): Boolean = (daysMask and (1 shl (day.value - 1))) != 0
    }

    data class Window(val date: LocalDate, val startMillis: Long, val endMillis: Long) {
        fun contains(millis: Long): Boolean = millis in startMillis..endMillis
    }

    data class FireTime(val atMillis: Long, val window: Window)

    fun localDateOf(zone: ZoneId, millis: Long): LocalDate =
        Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()

    /** Wall-clock time on [date] resolved to an instant; [minutesOfDay] may exceed 1439. */
    fun toInstant(zone: ZoneId, date: LocalDate, minutesOfDay: Int): Long {
        val day = date.plusDays((minutesOfDay / MINUTES_PER_DAY).toLong())
        val minutes = minutesOfDay % MINUTES_PER_DAY
        return ZonedDateTime.of(day, LocalTime.of(minutes / 60, minutes % 60), zone).toInstant().toEpochMilli()
    }

    fun windowFor(rule: Rule, zone: ZoneId, date: LocalDate): Window = Window(
        date = date,
        startMillis = toInstant(zone, date, rule.startMinutes),
        endMillis = toInstant(zone, date, rule.startMinutes + rule.windowLengthMinutes),
    )

    /** All notification instants of the occurrence starting on [date], de-duplicated. */
    fun firesFor(rule: Rule, zone: ZoneId, date: LocalDate): List<Long> {
        val fires = ArrayList<Long>()
        val length = rule.windowLengthMinutes
        val interval = rule.intervalMinutes.coerceAtLeast(1)
        var last: Long? = null
        var offset = 0
        while (offset <= length) {
            val instant = toInstant(zone, date, rule.startMinutes + offset)
            if (last == null || instant > last) {
                fires.add(instant)
                last = instant
            }
            offset += interval
        }
        return fires
    }

    /** The window containing [nowMillis], if any. Today is checked before yesterday. */
    fun currentWindow(rule: Rule, zone: ZoneId, nowMillis: Long): Window? {
        val today = localDateOf(zone, nowMillis)
        for (back in 0..LOOK_BACK_DAYS) {
            val date = today.minusDays(back.toLong())
            if (!rule.includes(date.dayOfWeek)) continue
            val window = windowFor(rule, zone, date)
            if (window.contains(nowMillis)) return window
        }
        return null
    }

    /**
     * First notification strictly after [afterMillis]; dates for which
     * [isDateClosed] returns true (completed/expired occurrences) are skipped.
     */
    fun nextFireAfter(
        rule: Rule,
        zone: ZoneId,
        afterMillis: Long,
        isDateClosed: (LocalDate) -> Boolean = { false },
    ): FireTime? {
        if (!rule.hasAnyDay) return null
        val today = localDateOf(zone, afterMillis)
        for (i in -LOOK_BACK_DAYS..LOOK_AHEAD_DAYS) {
            val date = today.plusDays(i.toLong())
            if (!rule.includes(date.dayOfWeek)) continue
            val window = windowFor(rule, zone, date)
            if (window.endMillis <= afterMillis) continue
            if (isDateClosed(date)) continue
            for (fire in firesFor(rule, zone, date)) {
                if (fire > afterMillis) return FireTime(fire, window)
            }
        }
        return null
    }

    /** Most recent window (today or yesterday) that has already started. */
    fun mostRecentStartedWindow(rule: Rule, zone: ZoneId, nowMillis: Long): Window? {
        val today = localDateOf(zone, nowMillis)
        for (back in 0..LOOK_BACK_DAYS) {
            val date = today.minusDays(back.toLong())
            if (!rule.includes(date.dayOfWeek)) continue
            val window = windowFor(rule, zone, date)
            if (window.startMillis <= nowMillis) return window
        }
        return null
    }
}
