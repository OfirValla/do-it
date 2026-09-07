package com.doit.app.scheduling

import com.doit.app.db.OccurrenceRow
import com.doit.app.db.OccurrenceStatus
import com.doit.app.db.ReminderRow
import com.doit.app.db.ReminderStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Behavioural tests of the native engine with in-memory fakes. These cover the
 * "critical scenario": alarm fires with Flutter dead, notification shown, Done
 * tapped from the notification, no further notifications for the day, next day
 * starts fresh; plus boot restore, disable, edit and late delivery.
 */
class ReminderEngineTest {

    private val zone: ZoneId = ZoneId.of("Europe/Berlin")

    private lateinit var store: FakeStore
    private lateinit var alarms: FakeAlarms
    private lateinit var notifier: FakeNotifier
    private lateinit var clock: FakeClock
    private lateinit var engine: ReminderEngine

    private val monday = LocalDate.of(2026, 9, 7)

    private fun at(y: Int, m: Int, d: Int, h: Int, min: Int): Long =
        ZonedDateTime.of(y, m, d, h, min, 0, 0, zone).toInstant().toEpochMilli()

    @Before
    fun setUp() {
        store = FakeStore()
        alarms = FakeAlarms()
        notifier = FakeNotifier()
        clock = FakeClock(zone, at(2026, 9, 7, 7, 0))
        engine = ReminderEngine(store, alarms, notifier, clock)
    }

    private fun vitamins(enabled: Boolean = true): ReminderRow = store.addReminder(
        title = "Take vitamins", start = 8 * 60, end = 18 * 60, interval = 30, days = 0x1F, enabled = enabled,
    )

    @Test
    fun `scheduling a new reminder sets exactly one alarm at the first fire`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)

        assertEquals(1, alarms.pending.size)
        assertEquals(at(2026, 9, 7, 8, 0), alarms.pending[reminder.id]!!.fireAt)
        assertEquals(monday, alarms.pending[reminder.id]!!.date)
    }

    @Test
    fun `alarm fired shows the notification, creates the occurrence and chains the next alarm`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        clock.now = at(2026, 9, 7, 8, 0)

        engine.onAlarmFired(reminder.id, monday, at(2026, 9, 7, 8, 0))

        assertEquals(1, notifier.shown.size)
        assertEquals("Take vitamins", notifier.shown.single().reminder.title)
        assertEquals(at(2026, 9, 7, 8, 30), notifier.shown.single().nextFireAt)
        val occurrence = store.getOccurrence(reminder.id, monday)!!
        assertEquals(OccurrenceStatus.ACTIVE, occurrence.status)
        assertEquals(1, occurrence.notificationCount)
        assertEquals(at(2026, 9, 7, 8, 30), alarms.pending[reminder.id]!!.fireAt)
    }

    @Test
    fun `done from the notification stops today's notifications and moves to tomorrow`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        for (minute in listOf(8 * 60, 8 * 60 + 30, 9 * 60)) {
            clock.now = at(2026, 9, 7, minute / 60, minute % 60)
            engine.onAlarmFired(reminder.id, monday, clock.now)
        }
        assertEquals(3, notifier.shown.size)

        // 09:17 - user taps Done on the notification (Flutter not running).
        clock.now = at(2026, 9, 7, 9, 17)
        engine.complete(reminder.id, monday)

        val occurrence = store.getOccurrence(reminder.id, monday)!!
        assertEquals(OccurrenceStatus.COMPLETED, occurrence.status)
        assertEquals(at(2026, 9, 7, 9, 17), occurrence.completedAtMillis)
        assertTrue(notifier.cancelled.contains(reminder.id))
        // 09:30 is gone; the next alarm is Tuesday 08:00.
        assertEquals(at(2026, 9, 8, 8, 0), alarms.pending[reminder.id]!!.fireAt)
        assertEquals(LocalDate.of(2026, 9, 8), alarms.pending[reminder.id]!!.date)

        // Even a stale 09:30 delivery would not notify again for Monday.
        clock.now = at(2026, 9, 7, 9, 30)
        engine.onAlarmFired(reminder.id, monday, clock.now)
        assertEquals(3, notifier.shown.size)

        // Tuesday starts a fresh occurrence.
        clock.now = at(2026, 9, 8, 8, 0)
        engine.onAlarmFired(reminder.id, LocalDate.of(2026, 9, 8), clock.now)
        assertEquals(4, notifier.shown.size)
        assertEquals(OccurrenceStatus.ACTIVE, store.getOccurrence(reminder.id, LocalDate.of(2026, 9, 8))!!.status)
    }

    @Test
    fun `done before the first notification creates a completed occurrence`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        clock.now = at(2026, 9, 7, 8, 10)
        engine.complete(reminder.id, null)

        assertEquals(OccurrenceStatus.COMPLETED, store.getOccurrence(reminder.id, monday)!!.status)
        assertEquals(at(2026, 9, 8, 8, 0), alarms.pending[reminder.id]!!.fireAt)
    }

    @Test
    fun `disabled reminder has no alarm and no notification`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        store.setEnabled(reminder.id, false)

        engine.cancel(reminder.id)
        assertNull(alarms.pending[reminder.id])
        assertTrue(notifier.cancelled.contains(reminder.id))

        // An alarm that slipped through is ignored for a disabled reminder.
        clock.now = at(2026, 9, 7, 8, 0)
        engine.onAlarmFired(reminder.id, monday, clock.now)
        assertTrue(notifier.shown.isEmpty())
        assertNull(alarms.pending[reminder.id])

        // Re-enabling restores the schedule.
        store.setEnabled(reminder.id, true)
        engine.scheduleNext(reminder.id)
        assertEquals(at(2026, 9, 7, 8, 30), alarms.pending[reminder.id]!!.fireAt)
    }

    @Test
    fun `editing a reminder replaces the pending alarm`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        assertEquals(at(2026, 9, 7, 8, 0), alarms.pending[reminder.id]!!.fireAt)

        store.update(reminder.copy(startMinutes = 10 * 60, intervalMinutes = 60))
        engine.scheduleNext(reminder.id)

        assertEquals(1, alarms.pending.size)
        assertEquals(at(2026, 9, 7, 10, 0), alarms.pending[reminder.id]!!.fireAt)
        // Every scheduleNext cancels the previous alarm before setting the new one.
        assertEquals(2, alarms.cancelCount(reminder.id))
    }

    @Test
    fun `deleted reminder cancels everything when its alarm arrives`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        store.delete(reminder.id)
        clock.now = at(2026, 9, 7, 8, 0)
        engine.onAlarmFired(reminder.id, monday, clock.now)
        assertTrue(notifier.shown.isEmpty())
        assertNull(alarms.pending[reminder.id])
        assertTrue(notifier.cancelled.contains(reminder.id))
    }

    @Test
    fun `reboot restores alarms for every enabled reminder only`() {
        val vitaminsRow = vitamins()
        val callMom = store.addReminder("Call Mom", 10 * 60, 20 * 60, 60, 1 shl 6, enabled = true)
        val paused = store.addReminder("Paused", 9 * 60, 10 * 60, 15, 0x7F, enabled = false)
        // Simulate the reboot wiping all alarms.
        alarms.pending.clear()
        clock.now = at(2026, 9, 7, 9, 17) // Monday morning after reboot

        engine.rescheduleAll()

        assertEquals(2, alarms.pending.size)
        assertEquals(at(2026, 9, 7, 9, 30), alarms.pending[vitaminsRow.id]!!.fireAt)
        assertEquals(at(2026, 9, 13, 10, 0), alarms.pending[callMom.id]!!.fireAt)
        assertNull(alarms.pending[paused.id])
        assertTrue(notifier.cancelled.contains(paused.id))
    }

    @Test
    fun `missed notifications do not produce a backlog`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        // Device was off from 08:00 to 12:10; boot triggers rescheduleAll.
        alarms.pending.clear()
        clock.now = at(2026, 9, 7, 12, 10)
        engine.rescheduleAll()
        assertTrue(notifier.shown.isEmpty())
        assertEquals(at(2026, 9, 7, 12, 30), alarms.pending[reminder.id]!!.fireAt)
    }

    @Test
    fun `alarm delivered after the window ended does not notify`() {
        val reminder = vitamins()
        engine.scheduleNext(reminder.id)
        clock.now = at(2026, 9, 7, 18, 12) // 18:00 alarm delayed by Doze
        engine.onAlarmFired(reminder.id, monday, at(2026, 9, 7, 18, 0))
        assertTrue(notifier.shown.isEmpty())
        assertEquals(at(2026, 9, 8, 8, 0), alarms.pending[reminder.id]!!.fireAt)
    }

    @Test
    fun `stale occurrences expire on housekeeping`() {
        val reminder = vitamins()
        clock.now = at(2026, 9, 7, 8, 0)
        engine.onAlarmFired(reminder.id, monday, clock.now)
        clock.now = at(2026, 9, 7, 18, 30)
        engine.rescheduleAll()
        assertEquals(OccurrenceStatus.EXPIRED, store.getOccurrence(reminder.id, monday)!!.status)
        assertFalse(alarms.pending.isEmpty())
    }

    // -------------------------------------------------------------------------
    // Fakes
    // -------------------------------------------------------------------------

    class FakeClock(private val zone: ZoneId, var now: Long) : EngineClock {
        override fun nowMillis(): Long = now
        override fun zone(): ZoneId = zone
    }

    class FakeAlarms : AlarmGateway {
        data class Pending(val fireAt: Long, val date: LocalDate)

        val pending = LinkedHashMap<Long, Pending>()
        private val cancels = HashMap<Long, Int>()

        override fun schedule(reminderId: Long, fireAtMillis: Long, occurrenceDate: LocalDate) {
            pending[reminderId] = Pending(fireAtMillis, occurrenceDate)
        }

        override fun cancel(reminderId: Long) {
            pending.remove(reminderId)
            cancels[reminderId] = (cancels[reminderId] ?: 0) + 1
        }

        fun cancelCount(reminderId: Long): Int = cancels[reminderId] ?: 0
    }

    class FakeNotifier : NotificationGateway {
        data class Shown(val reminder: ReminderRow, val occurrence: OccurrenceRow, val nextFireAt: Long?)

        val shown = ArrayList<Shown>()
        val cancelled = ArrayList<Long>()

        override fun show(reminder: ReminderRow, occurrence: OccurrenceRow, nextFireAtMillis: Long?) {
            shown.add(Shown(reminder, occurrence, nextFireAtMillis))
        }

        override fun cancel(reminderId: Long) {
            cancelled.add(reminderId)
        }
    }

    class FakeStore : ReminderStore {
        private val reminders = LinkedHashMap<Long, ReminderRow>()
        private val occurrences = LinkedHashMap<Long, OccurrenceRow>()
        private var nextReminderId = 1L
        private var nextOccurrenceId = 1L

        fun addReminder(title: String, start: Int, end: Int, interval: Int, days: Int, enabled: Boolean): ReminderRow {
            val row = ReminderRow(nextReminderId++, title, "", start, end, interval, days, enabled)
            reminders[row.id] = row
            return row
        }

        fun update(row: ReminderRow) {
            reminders[row.id] = row
        }

        fun setEnabled(id: Long, enabled: Boolean) {
            reminders[id] = reminders[id]!!.copy(enabled = enabled)
        }

        fun delete(id: Long) {
            reminders.remove(id)
            occurrences.values.removeAll { it.reminderId == id }
        }

        override fun getAllReminders(): List<ReminderRow> = reminders.values.toList()

        override fun getReminder(id: Long): ReminderRow? = reminders[id]

        override fun getOccurrence(reminderId: Long, date: LocalDate): OccurrenceRow? =
            occurrences.values.firstOrNull { it.reminderId == reminderId && it.date == date }

        override fun insertOccurrence(
            reminderId: Long,
            date: LocalDate,
            status: OccurrenceStatus,
            windowStartMillis: Long,
            windowEndMillis: Long,
            completedAtMillis: Long?,
        ): OccurrenceRow {
            getOccurrence(reminderId, date)?.let { return it }
            val row = OccurrenceRow(
                nextOccurrenceId++, reminderId, date, status, windowStartMillis, windowEndMillis,
                completedAtMillis, 0, null,
            )
            occurrences[row.id] = row
            return row
        }

        override fun updateOccurrenceStatus(id: Long, status: OccurrenceStatus, completedAtMillis: Long?) {
            occurrences[id] = occurrences[id]!!.copy(status = status, completedAtMillis = completedAtMillis)
        }

        override fun recordNotification(id: Long, atMillis: Long): OccurrenceRow {
            val updated = occurrences[id]!!.let {
                it.copy(notificationCount = it.notificationCount + 1, lastNotifiedAtMillis = atMillis)
            }
            occurrences[id] = updated
            return updated
        }

        override fun expireStaleOccurrences(nowMillis: Long): Int {
            var count = 0
            for ((id, row) in occurrences.entries.toList()) {
                if (row.status == OccurrenceStatus.ACTIVE && row.windowEndMillis < nowMillis) {
                    occurrences[id] = row.copy(status = OccurrenceStatus.EXPIRED)
                    count++
                }
            }
            return count
        }
    }
}
