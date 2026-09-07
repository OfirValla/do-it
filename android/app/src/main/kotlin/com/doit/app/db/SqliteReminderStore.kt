package com.doit.app.db

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.time.LocalDate

/**
 * Reads and writes the very same SQLite file that Drift owns on the Flutter side.
 *
 * Both connections use WAL mode so that a Drift write and an engine read never
 * block each other for longer than the busy timeout. The schema is created and
 * migrated exclusively by Drift; this class only touches rows, never DDL.
 *
 * Column and table names are the ones declared in lib/core/database/tables.dart.
 */
class SqliteReminderStore private constructor(private val db: SQLiteDatabase) : ReminderStore, AutoCloseable {

    companion object {
        private const val TAG = "DoIt.Store"
        private const val TABLE_REMINDERS = "reminders"
        private const val TABLE_OCCURRENCES = "occurrences"

        /**
         * Opens the shared database, or returns null when Flutter has not created
         * it yet (nothing can be scheduled in that case anyway).
         */
        fun openIfExists(context: Context): SqliteReminderStore? {
            val file = DoItDatabase.file(context)
            if (!file.exists()) {
                Log.i(TAG, "Database does not exist yet at ${file.path}")
                return null
            }
            return try {
                val db = SQLiteDatabase.openDatabase(
                    file.path,
                    null,
                    SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
                )
                db.setForeignKeyConstraintsEnabled(true)
                if (!hasTable(db, TABLE_REMINDERS) || !hasTable(db, TABLE_OCCURRENCES)) {
                    Log.w(TAG, "Schema not created yet; skipping")
                    db.close()
                    null
                } else {
                    SqliteReminderStore(db)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open database", e)
                null
            }
        }

        private fun hasTable(db: SQLiteDatabase, name: String): Boolean {
            db.rawQuery(
                "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
                arrayOf(name),
            ).use { return it.moveToFirst() }
        }
    }

    override fun close() {
        db.close()
    }

    // -------------------------------------------------------------------------
    // Reminders
    // -------------------------------------------------------------------------

    override fun getAllReminders(): List<ReminderRow> {
        db.rawQuery("SELECT * FROM $TABLE_REMINDERS ORDER BY id", null).use { cursor ->
            val result = ArrayList<ReminderRow>(cursor.count)
            while (cursor.moveToNext()) result.add(readReminder(cursor))
            return result
        }
    }

    override fun getReminder(id: Long): ReminderRow? {
        db.rawQuery("SELECT * FROM $TABLE_REMINDERS WHERE id = ?", arrayOf(id.toString())).use { cursor ->
            return if (cursor.moveToFirst()) readReminder(cursor) else null
        }
    }

    private fun readReminder(c: Cursor): ReminderRow {
        // Added in schema v2. The engine can run (boot, package replaced) before
        // the user opens the updated app and Drift migrates, so tolerate absence.
        val ringIndex = c.getColumnIndex("ring_minutes")
        val ringMinutes = if (ringIndex >= 0 && !c.isNull(ringIndex)) {
            c.getInt(ringIndex).coerceIn(0, ReminderRow.MAX_RING_MINUTES)
        } else {
            ReminderRow.DEFAULT_RING_MINUTES
        }
        return ReminderRow(
            id = c.getLong(c.getColumnIndexOrThrow("id")),
            title = c.getString(c.getColumnIndexOrThrow("title")) ?: "",
            description = c.getString(c.getColumnIndexOrThrow("description")) ?: "",
            startMinutes = c.getInt(c.getColumnIndexOrThrow("start_minutes")),
            endMinutes = c.getInt(c.getColumnIndexOrThrow("end_minutes")),
            intervalMinutes = c.getInt(c.getColumnIndexOrThrow("interval_minutes")).coerceAtLeast(1),
            daysMask = c.getInt(c.getColumnIndexOrThrow("days_of_week")) and 0x7F,
            enabled = c.getInt(c.getColumnIndexOrThrow("enabled")) != 0,
            ringMinutes = ringMinutes,
        )
    }

    // -------------------------------------------------------------------------
    // Occurrences
    // -------------------------------------------------------------------------

    override fun getOccurrence(reminderId: Long, date: LocalDate): OccurrenceRow? {
        db.rawQuery(
            "SELECT * FROM $TABLE_OCCURRENCES WHERE reminder_id = ? AND occurrence_date = ?",
            arrayOf(reminderId.toString(), date.toString()),
        ).use { cursor ->
            return if (cursor.moveToFirst()) readOccurrence(cursor) else null
        }
    }

    private fun getOccurrenceById(id: Long): OccurrenceRow? {
        db.rawQuery("SELECT * FROM $TABLE_OCCURRENCES WHERE id = ?", arrayOf(id.toString())).use { cursor ->
            return if (cursor.moveToFirst()) readOccurrence(cursor) else null
        }
    }

    override fun insertOccurrence(
        reminderId: Long,
        date: LocalDate,
        status: OccurrenceStatus,
        windowStartMillis: Long,
        windowEndMillis: Long,
        completedAtMillis: Long?,
    ): OccurrenceRow {
        val values = ContentValues().apply {
            put("reminder_id", reminderId)
            put("occurrence_date", date.toString())
            put("status", status.dbValue)
            put("window_start", windowStartMillis)
            put("window_end", windowEndMillis)
            if (completedAtMillis == null) putNull("completed_at") else put("completed_at", completedAtMillis)
            put("notification_count", 0)
            putNull("last_notified_at")
        }
        // Flutter may have inserted the same (reminder, date) concurrently; the
        // UNIQUE constraint makes the second insert fail, in which case we
        // simply return the existing row.
        val id = db.insertWithOnConflict(TABLE_OCCURRENCES, null, values, SQLiteDatabase.CONFLICT_IGNORE)
        if (id != -1L) {
            return OccurrenceRow(
                id = id,
                reminderId = reminderId,
                date = date,
                status = status,
                windowStartMillis = windowStartMillis,
                windowEndMillis = windowEndMillis,
                completedAtMillis = completedAtMillis,
                notificationCount = 0,
                lastNotifiedAtMillis = null,
            )
        }
        val existing = getOccurrence(reminderId, date)
            ?: throw IllegalStateException("Occurrence insert ignored but row not found")
        if (status == OccurrenceStatus.COMPLETED && existing.status != OccurrenceStatus.COMPLETED) {
            updateOccurrenceStatus(existing.id, status, completedAtMillis)
            return existing.copy(status = status, completedAtMillis = completedAtMillis)
        }
        return existing
    }

    override fun updateOccurrenceStatus(id: Long, status: OccurrenceStatus, completedAtMillis: Long?) {
        val values = ContentValues().apply {
            put("status", status.dbValue)
            if (completedAtMillis == null) putNull("completed_at") else put("completed_at", completedAtMillis)
        }
        db.update(TABLE_OCCURRENCES, values, "id = ?", arrayOf(id.toString()))
    }

    override fun recordNotification(id: Long, atMillis: Long): OccurrenceRow {
        db.execSQL(
            "UPDATE $TABLE_OCCURRENCES SET notification_count = notification_count + 1, last_notified_at = ? WHERE id = ?",
            arrayOf<Any>(atMillis, id),
        )
        return getOccurrenceById(id) ?: throw IllegalStateException("Occurrence $id vanished")
    }

    override fun expireStaleOccurrences(nowMillis: Long): Int {
        val values = ContentValues().apply { put("status", OccurrenceStatus.EXPIRED.dbValue) }
        return db.update(
            TABLE_OCCURRENCES,
            values,
            "status = ? AND window_end < ?",
            arrayOf(OccurrenceStatus.ACTIVE.dbValue, nowMillis.toString()),
        )
    }

    private fun readOccurrence(c: Cursor): OccurrenceRow {
        val completedIdx = c.getColumnIndexOrThrow("completed_at")
        val lastNotifiedIdx = c.getColumnIndexOrThrow("last_notified_at")
        return OccurrenceRow(
            id = c.getLong(c.getColumnIndexOrThrow("id")),
            reminderId = c.getLong(c.getColumnIndexOrThrow("reminder_id")),
            date = LocalDate.parse(c.getString(c.getColumnIndexOrThrow("occurrence_date"))),
            status = OccurrenceStatus.fromDb(c.getString(c.getColumnIndexOrThrow("status"))),
            windowStartMillis = c.getLong(c.getColumnIndexOrThrow("window_start")),
            windowEndMillis = c.getLong(c.getColumnIndexOrThrow("window_end")),
            completedAtMillis = if (c.isNull(completedIdx)) null else c.getLong(completedIdx),
            notificationCount = c.getInt(c.getColumnIndexOrThrow("notification_count")),
            lastNotifiedAtMillis = if (c.isNull(lastNotifiedIdx)) null else c.getLong(lastNotifiedIdx),
        )
    }
}
