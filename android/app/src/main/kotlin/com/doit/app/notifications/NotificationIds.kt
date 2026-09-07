package com.doit.app.notifications

/**
 * Deterministic identifiers.
 *
 * The engine keeps exactly one pending alarm and at most one visible
 * notification per reminder: every re-notification updates the same
 * notification in place (re-alerting), which is what makes "cancel everything
 * for this occurrence" a single `cancel(id)` call and prevents a tray full of
 * duplicates after a missed hour.
 *
 * Reminder ids are SQLite AUTOINCREMENT values starting at 1, so they map 1:1
 * onto notification ids and PendingIntent request codes. Alarm, Done and Open
 * PendingIntents share the request code but differ in action and data URI, so
 * Android treats them as distinct. Id 0 is reserved for the test notification.
 *
 * The occurrence date and the intended fire time are carried as intent extras
 * and validated on delivery, so a stale alarm can never notify for the wrong
 * day.
 */
object NotificationIds {
    const val TEST_REMINDER_ID = 0L

    fun notificationId(reminderId: Long): Int = toInt(reminderId)
    fun alarmRequestCode(reminderId: Long): Int = toInt(reminderId)
    fun doneRequestCode(reminderId: Long): Int = toInt(reminderId)
    fun openRequestCode(reminderId: Long): Int = toInt(reminderId)

    private fun toInt(reminderId: Long): Int = (reminderId and 0x7FFFFFFFL).toInt()
}
