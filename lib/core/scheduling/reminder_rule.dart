/// The pure recurrence rule of a reminder, decoupled from its presentation
/// fields (title, description) and its persistence identity.
///
/// This is the exact set of values the native Android engine reads from the
/// shared database, and [ScheduleCalculator] in Dart mirrors the Kotlin
/// `ScheduleCalculator` so that what the UI predicts is what Android fires.
class ReminderRule {
  const ReminderRule({
    required this.startMinutes,
    required this.endMinutes,
    required this.intervalMinutes,
    required this.daysMask,
  })  : assert(startMinutes >= 0 && startMinutes < 24 * 60),
        assert(endMinutes >= 0 && endMinutes < 24 * 60),
        assert(intervalMinutes >= 1);

  /// Wall-clock start of the daily window, minutes since midnight.
  final int startMinutes;

  /// Wall-clock end of the daily window, minutes since midnight. When it is not
  /// after [startMinutes] the window crosses midnight into the following day.
  final int endMinutes;

  /// Re-notification interval while the occurrence is not completed.
  final int intervalMinutes;

  /// Bitmask of eligible start days: Monday = 1 << 0 ... Sunday = 1 << 6.
  final int daysMask;

  static const int minutesPerDay = 24 * 60;

  bool get crossesMidnight => endMinutes <= startMinutes;

  /// Total length of the window in minutes (always between 1 and 1440).
  int get windowLengthMinutes => crossesMidnight
      ? endMinutes + minutesPerDay - startMinutes
      : endMinutes - startMinutes;

  bool get hasAnyDay => daysMask != 0;

  /// [isoWeekday] uses the [DateTime.weekday] convention (Monday = 1).
  bool includesWeekday(int isoWeekday) =>
      (daysMask & (1 << (isoWeekday - 1))) != 0;

  @override
  bool operator ==(Object other) =>
      other is ReminderRule &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes &&
      other.intervalMinutes == intervalMinutes &&
      other.daysMask == daysMask;

  @override
  int get hashCode =>
      Object.hash(startMinutes, endMinutes, intervalMinutes, daysMask);

  @override
  String toString() =>
      'ReminderRule(start: $startMinutes, end: $endMinutes, '
      'every: $intervalMinutes, days: $daysMask)';
}
