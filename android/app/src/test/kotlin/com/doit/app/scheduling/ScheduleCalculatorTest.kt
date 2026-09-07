package com.doit.app.scheduling

import com.doit.app.scheduling.ScheduleCalculator.Rule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * JVM tests for the native scheduling math. Run with
 * `cd android && ./gradlew :app:testDebugUnitTest`.
 *
 * The scenarios intentionally match test/core/scheduling/schedule_calculator_test.dart
 * so both implementations are verified against the same expectations.
 */
class ScheduleCalculatorTest {

    private val berlin: ZoneId = ZoneId.of("Europe/Berlin")
    private val newYork: ZoneId = ZoneId.of("America/New_York")

    private val everyDay = 0x7F
    private val weekdays = 0x1F
    private val weekends = 0x60
    private val monday = 1 shl 0
    private val sunday = 1 shl 6

    private fun at(zone: ZoneId, y: Int, m: Int, d: Int, h: Int, min: Int): Long =
        ZonedDateTime.of(y, m, d, h, min, 0, 0, zone).toInstant().toEpochMilli()

    private fun utc(y: Int, m: Int, d: Int, h: Int, min: Int): Long =
        at(ZoneId.of("UTC"), y, m, d, h, min)

    private fun rule(start: Int, end: Int, interval: Int, days: Int) =
        Rule(startMinutes = start, endMinutes = end, intervalMinutes = interval, daysMask = days)

    // Monday 2026-09-07 is a plain day in Berlin (CEST, UTC+2).

    @Test
    fun `daily reminder fires every 30 minutes within the window`() {
        val r = rule(8 * 60, 18 * 60, 30, everyDay)
        val fires = ScheduleCalculator.firesFor(r, berlin, LocalDate.of(2026, 9, 7))
        assertEquals(21, fires.size)
        assertEquals(at(berlin, 2026, 9, 7, 8, 0), fires.first())
        assertEquals(at(berlin, 2026, 9, 7, 18, 0), fires.last())
        assertEquals(at(berlin, 2026, 9, 7, 9, 30), fires[3])
    }

    @Test
    fun `next fire after a fire time is strictly later`() {
        val r = rule(8 * 60, 18 * 60, 30, everyDay)
        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 7, 9, 0))
        assertEquals(at(berlin, 2026, 9, 7, 9, 30), next!!.atMillis)
        assertEquals(LocalDate.of(2026, 9, 7), next.window.date)
    }

    @Test
    fun `after the window the next fire is tomorrow's start`() {
        val r = rule(8 * 60, 18 * 60, 30, everyDay)
        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 7, 18, 0))
        assertEquals(at(berlin, 2026, 9, 8, 8, 0), next!!.atMillis)
    }

    @Test
    fun `weekday reminder skips the weekend`() {
        val r = rule(9 * 60, 10 * 60, 60, weekdays)
        // Friday 2026-09-11 after the window -> Monday 2026-09-14.
        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 11, 12, 0))
        assertEquals(at(berlin, 2026, 9, 14, 9, 0), next!!.atMillis)
    }

    @Test
    fun `weekend reminder waits for Saturday`() {
        val r = rule(10 * 60, 12 * 60, 60, weekends)
        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 7, 8, 0))
        assertEquals(at(berlin, 2026, 9, 12, 10, 0), next!!.atMillis)
    }

    @Test
    fun `single day reminder is at most a week away`() {
        val r = rule(10 * 60, 20 * 60, 60, sunday)
        // Sunday 2026-09-06 21:00 -> next Sunday 2026-09-13 10:00.
        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 6, 21, 0))
        assertEquals(at(berlin, 2026, 9, 13, 10, 0), next!!.atMillis)
    }

    @Test
    fun `no days selected yields nothing`() {
        val r = rule(8 * 60, 18 * 60, 30, 0)
        assertNull(ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 7, 9, 0)))
    }

    @Test
    fun `five minute and one hour intervals`() {
        val five = rule(8 * 60, 9 * 60, 5, everyDay)
        assertEquals(13, ScheduleCalculator.firesFor(five, berlin, LocalDate.of(2026, 9, 7)).size)
        val hourly = rule(10 * 60, 20 * 60, 60, everyDay)
        assertEquals(11, ScheduleCalculator.firesFor(hourly, berlin, LocalDate.of(2026, 9, 7)).size)
    }

    @Test
    fun `end time not on the grid is not fired`() {
        val r = rule(8 * 60, 17 * 60 + 50, 30, everyDay)
        val fires = ScheduleCalculator.firesFor(r, berlin, LocalDate.of(2026, 9, 7))
        assertEquals(at(berlin, 2026, 9, 7, 17, 30), fires.last())
    }

    @Test
    fun `current window is null before start and after end`() {
        val r = rule(8 * 60, 18 * 60, 30, everyDay)
        assertNull(ScheduleCalculator.currentWindow(r, berlin, at(berlin, 2026, 9, 7, 7, 59)))
        assertNotNull(ScheduleCalculator.currentWindow(r, berlin, at(berlin, 2026, 9, 7, 8, 0)))
        assertNotNull(ScheduleCalculator.currentWindow(r, berlin, at(berlin, 2026, 9, 7, 18, 0)))
        assertNull(ScheduleCalculator.currentWindow(r, berlin, at(berlin, 2026, 9, 7, 18, 1)))
    }

    @Test
    fun `window crossing midnight belongs to the start date`() {
        val r = rule(22 * 60, 2 * 60, 60, monday)
        val fires = ScheduleCalculator.firesFor(r, berlin, LocalDate.of(2026, 9, 7))
        assertEquals(5, fires.size)
        assertEquals(at(berlin, 2026, 9, 8, 2, 0), fires.last())

        val window = ScheduleCalculator.currentWindow(r, berlin, at(berlin, 2026, 9, 8, 1, 30))
        assertEquals(LocalDate.of(2026, 9, 7), window!!.date)

        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 8, 0, 10))
        assertEquals(at(berlin, 2026, 9, 8, 1, 0), next!!.atMillis)
        assertEquals(LocalDate.of(2026, 9, 7), next.window.date)
    }

    @Test
    fun `closed dates are skipped`() {
        val r = rule(8 * 60, 18 * 60, 30, everyDay)
        val today = LocalDate.of(2026, 9, 7)
        val next = ScheduleCalculator.nextFireAfter(r, berlin, at(berlin, 2026, 9, 7, 9, 17)) { it == today }
        assertEquals(at(berlin, 2026, 9, 8, 8, 0), next!!.atMillis)
    }

    @Test
    fun `spring forward produces no duplicate and no missing notifications`() {
        // Berlin 2026-03-29: 02:00 CET -> 03:00 CEST.
        val r = rule(1 * 60, 5 * 60, 30, everyDay)
        val fires = ScheduleCalculator.firesFor(r, berlin, LocalDate.of(2026, 3, 29))
        val expected = listOf(
            utc(2026, 3, 29, 0, 0), utc(2026, 3, 29, 0, 30), utc(2026, 3, 29, 1, 0),
            utc(2026, 3, 29, 1, 30), utc(2026, 3, 29, 2, 0), utc(2026, 3, 29, 2, 30),
            utc(2026, 3, 29, 3, 0),
        )
        assertEquals(expected, fires)
    }

    @Test
    fun `fall back keeps instants strictly increasing`() {
        // Berlin 2026-10-25: 03:00 CEST -> 02:00 CET.
        val r = rule(1 * 60, 4 * 60, 30, everyDay)
        val fires = ScheduleCalculator.firesFor(r, berlin, LocalDate.of(2026, 10, 25))
        assertEquals(7, fires.size)
        assertTrue(fires.zipWithNext().all { (a, b) -> b > a })
        assertEquals(utc(2026, 10, 24, 23, 0), fires.first())
        assertEquals(utc(2026, 10, 25, 3, 0), fires.last())
    }

    @Test
    fun `New York spring forward gap shifts forward`() {
        // 2026-03-08 02:30 does not exist; java.time moves it to 03:30 EDT = 07:30Z.
        assertEquals(utc(2026, 3, 8, 7, 30), ScheduleCalculator.toInstant(newYork, LocalDate.of(2026, 3, 8), 2 * 60 + 30))
        // 2026-11-01 01:30 exists twice; the earlier offset (EDT) wins = 05:30Z.
        assertEquals(utc(2026, 11, 1, 5, 30), ScheduleCalculator.toInstant(newYork, LocalDate.of(2026, 11, 1), 1 * 60 + 30))
    }

    @Test
    fun `timezone change moves the same wall clock rule`() {
        val r = rule(8 * 60, 18 * 60, 30, everyDay)
        val after = utc(2026, 9, 7, 3, 0)
        val inBerlin = ScheduleCalculator.nextFireAfter(r, berlin, after)!!.atMillis
        val inNewYork = ScheduleCalculator.nextFireAfter(r, newYork, after)!!.atMillis
        assertEquals(utc(2026, 9, 7, 6, 0), inBerlin)
        assertEquals(utc(2026, 9, 7, 12, 0), inNewYork)
    }
}
