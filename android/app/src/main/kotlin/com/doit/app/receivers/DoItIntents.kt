package com.doit.app.receivers

/** Actions and extras shared by alarms, notification actions, the ring service and the activity. */
object DoItIntents {
    /** AlarmManager -> AlarmReceiver. */
    const val ACTION_FIRE = "com.doit.app.action.FIRE"

    /** Notification "Done" -> NotificationActionReceiver. */
    const val ACTION_DONE = "com.doit.app.action.DONE"

    /** Notification "Stop" -> NotificationActionReceiver: silence the alarm, keep the reminder. */
    const val ACTION_STOP_RINGING = "com.doit.app.action.STOP_RINGING"

    /** Start command of AlarmRingService. */
    const val ACTION_RING = "com.doit.app.action.RING"

    const val EXTRA_REMINDER_ID = "com.doit.app.extra.REMINDER_ID"

    /** ISO-8601 local date (yyyy-MM-dd) of the occurrence the intent refers to. */
    const val EXTRA_OCCURRENCE_DATE = "com.doit.app.extra.OCCURRENCE_DATE"

    /** Epoch millis the alarm was scheduled for. */
    const val EXTRA_FIRE_AT = "com.doit.app.extra.FIRE_AT"

    /** Set on the activity intent launched by a full-screen (lock screen) alarm. */
    const val EXTRA_FULL_SCREEN = "com.doit.app.extra.FULL_SCREEN"

    // Notification payload carried into AlarmRingService so it can rebuild the
    // notification without touching the database.
    const val EXTRA_TITLE = "com.doit.app.extra.TITLE"
    const val EXTRA_TEXT = "com.doit.app.extra.TEXT"
    const val EXTRA_BIG_TEXT = "com.doit.app.extra.BIG_TEXT"
    const val EXTRA_NEXT_FIRE_AT = "com.doit.app.extra.NEXT_FIRE_AT"
    const val EXTRA_RING_MINUTES = "com.doit.app.extra.RING_MINUTES"
    const val EXTRA_COUNT = "com.doit.app.extra.COUNT"

    /**
     * Distinct data URIs make PendingIntents for different reminders (and
     * different purposes) distinguishable: `Intent.filterEquals` compares the
     * data URI and action but ignores extras.
     */
    fun alarmUri(reminderId: Long) = "doit://reminder/$reminderId/alarm"
    fun doneUri(reminderId: Long) = "doit://reminder/$reminderId/done"
    fun stopUri(reminderId: Long) = "doit://reminder/$reminderId/stop"
    fun openUri(reminderId: Long) = "doit://reminder/$reminderId"
    fun fullScreenUri(reminderId: Long) = "doit://reminder/$reminderId/ring"
}
