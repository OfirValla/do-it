import '../platform/do_it_platform.dart';
import 'reminder_scheduler.dart';

/// [ReminderScheduler] backed by the Kotlin `ReminderEngine`.
///
/// Each call crosses the platform channel once; the engine then reads the
/// reminder and its occurrences from the shared database, cancels the pending
/// `AlarmManager` alarm (request code = reminder id) and sets the next one.
class AndroidReminderScheduler implements ReminderScheduler {
  AndroidReminderScheduler(this._platform);

  final DoItPlatform _platform;

  @override
  Future<void> scheduleReminder(int reminderId) =>
      _platform.scheduleReminder(reminderId);

  @override
  Future<void> cancelReminder(int reminderId) =>
      _platform.cancelReminder(reminderId);

  @override
  Future<void> rescheduleAll() => _platform.rescheduleAll();

  @override
  Future<void> stopRinging(int reminderId) => _platform.stopRinging(reminderId);
}
