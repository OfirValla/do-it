import '../../../core/scheduling/reminder_rule.dart';
import '../../../core/utils/local_time.dart';
import 'weekday.dart';

/// A recurring reminder rule as created by the user.
///
/// Individual daily instances are modelled separately as
/// `ReminderOccurrence`s; this class only describes *when* occurrences happen.
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.intervalMinutes,
    required this.days,
    required this.enabled,
    required this.ringMinutes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Allowed alarm durations in minutes; 0 means "notification only".
  static const List<int> ringOptions = [0, 1, 2, 3, 4, 5];
  static const int defaultRingMinutes = 2;

  final int id;
  final String title;
  final String description;

  /// Wall-clock start of the daily window.
  final LocalTime startTime;

  /// Wall-clock end of the daily window. If it is not after [startTime], the
  /// window crosses midnight into the next day.
  final LocalTime endTime;

  /// How often the notification comes back while not completed.
  final int intervalMinutes;
  final DaysOfWeek days;
  final bool enabled;

  /// How long each notification rings like an alarm clock (0 = silent
  /// notification only, otherwise 1..5 minutes until Done or Stop is tapped).
  final int ringMinutes;

  /// UTC instants.
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get ringsLikeAlarm => ringMinutes > 0;

  ReminderRule get rule => ReminderRule(
        startMinutes: startTime.minutesSinceMidnight,
        endMinutes: endTime.minutesSinceMidnight,
        intervalMinutes: intervalMinutes,
        daysMask: days.mask,
      );

  bool get hasDescription => description.trim().isNotEmpty;

  Reminder copyWith({
    String? title,
    String? description,
    LocalTime? startTime,
    LocalTime? endTime,
    int? intervalMinutes,
    DaysOfWeek? days,
    bool? enabled,
    int? ringMinutes,
    DateTime? updatedAt,
  }) {
    return Reminder(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      days: days ?? this.days,
      enabled: enabled ?? this.enabled,
      ringMinutes: ringMinutes ?? this.ringMinutes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.intervalMinutes == intervalMinutes &&
      other.days == days &&
      other.enabled == enabled &&
      other.ringMinutes == ringMinutes &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        description,
        startTime,
        endTime,
        intervalMinutes,
        days,
        enabled,
        ringMinutes,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'Reminder(#$id "$title" $startTime-$endTime '
      'every ${intervalMinutes}m ${days.label}${enabled ? '' : ' [off]'})';
}

/// User input for creating or editing a reminder, before it has an identity.
class ReminderDraft {
  const ReminderDraft({
    required this.title,
    this.description = '',
    required this.startTime,
    required this.endTime,
    required this.intervalMinutes,
    required this.days,
    this.enabled = true,
    this.ringMinutes = Reminder.defaultRingMinutes,
  });

  factory ReminderDraft.fromReminder(Reminder reminder) => ReminderDraft(
        title: reminder.title,
        description: reminder.description,
        startTime: reminder.startTime,
        endTime: reminder.endTime,
        intervalMinutes: reminder.intervalMinutes,
        days: reminder.days,
        enabled: reminder.enabled,
        ringMinutes: reminder.ringMinutes,
      );

  final String title;
  final String description;
  final LocalTime startTime;
  final LocalTime endTime;
  final int intervalMinutes;
  final DaysOfWeek days;
  final bool enabled;
  final int ringMinutes;

  /// Returns a human readable validation problem, or null when valid.
  String? validate() {
    if (title.trim().isEmpty) return 'Give your reminder a title.';
    if (intervalMinutes < 1) return 'The interval must be at least 1 minute.';
    if (intervalMinutes > 24 * 60) {
      return 'The interval cannot be longer than a day.';
    }
    if (startTime == endTime) {
      return 'End time must be different from start time.';
    }
    if (days.isEmpty) return 'Pick at least one day.';
    if (!Reminder.ringOptions.contains(ringMinutes)) {
      return 'Alarm duration must be between 0 and 5 minutes.';
    }
    return null;
  }
}
