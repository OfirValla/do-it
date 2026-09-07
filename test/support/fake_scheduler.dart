import 'package:do_it/core/scheduling/reminder_scheduler.dart';

/// Records every call so tests can assert on ordering and arguments.
class FakeReminderScheduler implements ReminderScheduler {
  final List<String> calls = [];

  /// Reminder ids that currently have an alarm pending (as the native engine
  /// would after `scheduleReminder`).
  final Set<int> scheduled = {};

  @override
  Future<void> scheduleReminder(int reminderId) async {
    calls.add('schedule:$reminderId');
    scheduled.add(reminderId);
  }

  @override
  Future<void> cancelReminder(int reminderId) async {
    calls.add('cancel:$reminderId');
    scheduled.remove(reminderId);
  }

  @override
  Future<void> rescheduleAll() async {
    calls.add('rescheduleAll');
  }

  @override
  Future<void> stopRinging(int reminderId) async {
    calls.add('stopRinging:$reminderId');
  }

  void clear() {
    calls.clear();
  }
}
