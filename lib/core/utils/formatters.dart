import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/reminders/domain/weekday.dart';
import 'local_date.dart';
import 'local_time.dart';

/// Pure formatting helpers (no BuildContext) so they can be unit tested.
class Formatters {
  Formatters._();

  /// "Every 30 minutes", "Every hour", "Every 2 hours", "Every 1 h 30 min".
  static String interval(int minutes) {
    if (minutes < 60) {
      return minutes == 1 ? 'Every minute' : 'Every $minutes minutes';
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) {
      return hours == 1 ? 'Every hour' : 'Every $hours hours';
    }
    return 'Every $hours h $rest min';
  }

  /// Short form used in chips: "5 min", "30 min", "1 h", "2 h", "1 h 30".
  static String intervalShort(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest';
  }

  /// "Notification only", "Rings for 1 minute", "Rings for 3 minutes".
  static String ringDuration(int minutes) {
    if (minutes <= 0) return 'Notification only';
    return minutes == 1 ? 'Rings for 1 minute' : 'Rings for $minutes minutes';
  }

  /// Chip label: "Off", "1 min", "5 min".
  static String ringDurationShort(int minutes) =>
      minutes <= 0 ? 'Off' : '$minutes min';

  /// "Today", "Tomorrow", "Yesterday" or the weekday name relative to [today].
  static String relativeDay(LocalDate date, LocalDate today) {
    final delta = today.daysUntil(date);
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Tomorrow';
    if (delta == -1) return 'Yesterday';
    if (delta > 1 && delta < 7) return Weekday.fromIso(date.weekday).longLabel;
    return DateFormat.MMMEd().format(DateTime(date.year, date.month, date.day));
  }

  /// Label for the next notification: "09:30" when it is today, otherwise
  /// "Tomorrow 08:00" / "Sunday 10:00". [formatTime] lets the UI apply the
  /// device's 12/24-hour preference.
  static String nextFire(
    tz.TZDateTime next,
    LocalDate today,
    String Function(LocalTime time) formatTime,
  ) {
    final date = LocalDate.of(next);
    final time = formatTime(LocalTime(next.hour, next.minute));
    if (date == today) return time;
    return '${relativeDay(date, today)} $time';
  }

  /// "Mon, Sep 7" style date for history lists.
  static String historyDate(LocalDate date) =>
      DateFormat.MMMEd().format(DateTime(date.year, date.month, date.day));
}
