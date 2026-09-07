/// A wall-clock time of day (hour + minute) without date or timezone.
///
/// Stored in the database as minutes since midnight (0..1439), which is the
/// representation shared with the native Android scheduling engine.
class LocalTime implements Comparable<LocalTime> {
  const LocalTime(this.hour, this.minute)
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  factory LocalTime.fromMinutes(int minutesSinceMidnight) {
    final normalized = minutesSinceMidnight % (24 * 60);
    return LocalTime(normalized ~/ 60, normalized % 60);
  }

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  /// `HH:mm` (24-hour) representation used for compact labels and logging.
  String toHHmm() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  bool operator ==(Object other) =>
      other is LocalTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toHHmm();
}
