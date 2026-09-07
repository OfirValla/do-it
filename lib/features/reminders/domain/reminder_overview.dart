import '../../../core/scheduling/schedule_calculator.dart';
import '../../../core/utils/local_date.dart';
import 'reminder.dart';
import 'reminder_occurrence.dart';

/// What the user needs to know about a reminder right now.
enum ReminderState {
  /// Switched off: nothing scheduled.
  disabled,

  /// Inside today's window and not done yet: notifications are coming.
  active,

  /// Today's occurrence was completed; the next window is on a later day.
  completedToday,

  /// Enabled but currently outside of any window.
  idle,
}

/// Presentation-agnostic summary combining a [Reminder], its recent
/// occurrences and the current time.
class ReminderOverview {
  const ReminderOverview({
    required this.reminder,
    required this.state,
    required this.currentWindow,
    required this.currentOccurrence,
    required this.nextFireAt,
  });

  final Reminder reminder;
  final ReminderState state;

  /// The window containing "now", if any (regardless of completion).
  final OccurrenceWindow? currentWindow;

  /// The database row for [currentWindow], if one exists yet.
  final ReminderOccurrence? currentOccurrence;

  /// Next notification instant (UTC), null when disabled or no days selected.
  final DateTime? nextFireAt;

  bool get isActive => state == ReminderState.active;

  /// Computes the overview using the same rules as the native engine:
  /// a date whose occurrence is completed or expired gets no more fires.
  static ReminderOverview compute({
    required Reminder reminder,
    required Iterable<ReminderOccurrence> occurrences,
    required DateTime now,
    required ScheduleCalculator calculator,
  }) {
    final rule = reminder.rule;
    final byDate = <LocalDate, ReminderOccurrence>{
      for (final o in occurrences)
        if (o.reminderId == reminder.id) o.date: o,
    };
    bool isClosed(LocalDate date) => byDate[date]?.isClosed ?? false;

    if (!reminder.enabled) {
      return ReminderOverview(
        reminder: reminder,
        state: ReminderState.disabled,
        currentWindow: null,
        currentOccurrence: null,
        nextFireAt: null,
      );
    }

    final window = calculator.currentWindow(rule, now);
    final occurrence = window == null ? null : byDate[window.date];
    final next = calculator.nextFireAfter(rule, now, isDateClosed: isClosed);

    final ReminderState state;
    if (window != null && !(occurrence?.isClosed ?? false)) {
      state = ReminderState.active;
    } else if (window != null && (occurrence?.isCompleted ?? false)) {
      state = ReminderState.completedToday;
    } else {
      state = ReminderState.idle;
    }

    return ReminderOverview(
      reminder: reminder,
      state: state,
      currentWindow: window,
      currentOccurrence: occurrence,
      nextFireAt: next?.at,
    );
  }
}
