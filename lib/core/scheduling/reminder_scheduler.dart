/// Boundary between Flutter business logic and the operating system's
/// persistent scheduling facilities.
///
/// The Flutter side never talks to `AlarmManager` directly. Implementations
/// live behind this interface; on Android the implementation forwards to the
/// Kotlin `ReminderEngine`, which owns the alarm chain, the notification, the
/// ringing alarm and the "Done" action so that everything keeps working while
/// the Flutter process is dead.
///
/// All methods take reminder ids only: the native engine reads the rule and
/// occurrence state from the shared SQLite database, the single source of
/// truth for both sides.
abstract class ReminderScheduler {
  /// (Re)computes and schedules the next notification of the reminder.
  /// Cancels any previously pending alarm first, so it is safe to call after
  /// create, edit, enable, or after an occurrence was completed.
  Future<void> scheduleReminder(int reminderId);

  /// Cancels the pending alarm, stops any ringing and removes any visible
  /// notification. Used on disable and delete.
  Future<void> cancelReminder(int reminderId);

  /// Rebuilds the alarm chain for every enabled reminder. Used on app start
  /// (re-anchoring after a force stop) and mirrored natively on boot,
  /// app update, time and timezone changes.
  Future<void> rescheduleAll();

  /// Silences a ringing alarm without completing the occurrence; the reminder
  /// stays active and rings again at the next interval.
  Future<void> stopRinging(int reminderId);
}

/// Scheduler used on platforms without a native engine (desktop/web builds
/// used for UI development). It intentionally does nothing.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> cancelReminder(int reminderId) async {}

  @override
  Future<void> rescheduleAll() async {}

  @override
  Future<void> scheduleReminder(int reminderId) async {}

  @override
  Future<void> stopRinging(int reminderId) async {}
}
