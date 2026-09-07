import '../../../core/scheduling/reminder_scheduler.dart';
import '../../../core/scheduling/schedule_calculator.dart';
import '../../../core/utils/clock.dart';
import '../data/reminder_repository.dart';
import '../domain/reminder.dart';

/// Thrown when a draft fails validation.
class ReminderValidationException implements Exception {
  ReminderValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Use-cases around reminders: every write goes through here so that the
/// database and the OS scheduler never drift apart.
///
/// Ordering matters and follows the specification:
///   edit   -> cancel old alarms, update the database, schedule anew
///   enable -> update, schedule;   disable -> update, cancel
///   delete -> cancel, delete rows
///   done   -> write the completed occurrence, then let the scheduler skip to
///             the next window (the native side also removes the notification)
class ReminderService {
  ReminderService({
    required ReminderRepository repository,
    required ReminderScheduler scheduler,
    required ScheduleCalculator calculator,
    required Clock clock,
  })  : _repository = repository,
        _scheduler = scheduler,
        _calculator = calculator,
        _clock = clock;

  final ReminderRepository _repository;
  final ReminderScheduler _scheduler;
  final ScheduleCalculator _calculator;
  final Clock _clock;

  Future<int> create(ReminderDraft draft) async {
    _validate(draft);
    final id = await _repository.insert(draft, _clock.nowUtc());
    if (draft.enabled) {
      await _scheduler.scheduleReminder(id);
    }
    return id;
  }

  Future<void> update(Reminder reminder) async {
    _validate(ReminderDraft.fromReminder(reminder));
    await _scheduler.cancelReminder(reminder.id);
    await _repository.update(reminder, _clock.nowUtc());
    if (reminder.enabled) {
      await _scheduler.scheduleReminder(reminder.id);
    }
  }

  Future<void> setEnabled(int reminderId, bool enabled) async {
    await _repository.setEnabled(reminderId, enabled, _clock.nowUtc());
    if (enabled) {
      await _scheduler.scheduleReminder(reminderId);
    } else {
      await _scheduler.cancelReminder(reminderId);
    }
  }

  Future<void> delete(int reminderId) async {
    await _scheduler.cancelReminder(reminderId);
    await _repository.delete(reminderId);
  }

  /// Marks the reminder's current occurrence as done.
  ///
  /// If we are not inside a window (e.g. the user completes a reminder whose
  /// window just ended, from a notification that is still visible), the most
  /// recent window that started today or yesterday is completed instead.
  Future<bool> markDone(int reminderId) async {
    final reminder = await _repository.getById(reminderId);
    if (reminder == null) return false;
    final now = _clock.nowUtc();
    final rule = reminder.rule;

    var window = _calculator.currentWindow(rule, now);
    if (window == null) {
      final today = _calculator.localDateOf(now);
      for (var back = 0; back <= ScheduleCalculator.lookBackDays; back++) {
        final date = today.plusDays(-back);
        if (!rule.includesWeekday(date.weekday)) continue;
        final candidate = _calculator.windowFor(rule, date);
        if (!candidate.start.isAfter(now)) {
          window = candidate;
          break;
        }
      }
    }
    if (window == null) return false;

    await _repository.completeOccurrence(
      reminderId: reminderId,
      window: window,
      now: now,
    );
    await _scheduler.scheduleReminder(reminderId);
    return true;
  }

  /// Silences a ringing alarm; the occurrence stays active and rings again at
  /// the next interval.
  Future<void> stopRinging(int reminderId) => _scheduler.stopRinging(reminderId);

  /// Housekeeping run on start and resume.
  Future<void> expireStaleOccurrences() =>
      _repository.expireStaleOccurrences(_clock.nowUtc());

  /// Re-anchors every alarm. Cheap, idempotent, and the cure for alarms that
  /// were dropped by a force stop.
  Future<void> rescheduleAll() => _scheduler.rescheduleAll();

  void _validate(ReminderDraft draft) {
    final problem = draft.validate();
    if (problem != null) throw ReminderValidationException(problem);
  }
}
