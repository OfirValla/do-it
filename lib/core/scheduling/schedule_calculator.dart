import 'package:timezone/timezone.dart' as tz;

import '../utils/local_date.dart';
import 'reminder_rule.dart';

/// One daily occurrence window of a reminder, resolved to absolute instants.
class OccurrenceWindow {
  const OccurrenceWindow({
    required this.date,
    required this.start,
    required this.end,
  });

  /// Local calendar date on which the window starts. This is the key that
  /// identifies the occurrence in the database.
  final LocalDate date;

  /// First instant of the window (UTC).
  final DateTime start;

  /// Last instant of the window (UTC, inclusive).
  final DateTime end;

  bool contains(DateTime instant) =>
      !instant.isBefore(start) && !instant.isAfter(end);

  @override
  String toString() => 'OccurrenceWindow($date, $start .. $end)';
}

/// A concrete moment at which a notification should be shown.
class FireTime {
  const FireTime({required this.at, required this.window});

  /// UTC instant.
  final DateTime at;

  /// The occurrence this notification belongs to.
  final OccurrenceWindow window;

  @override
  String toString() => 'FireTime($at in ${window.date})';
}

/// Tells the calculator that the occurrence on [date] no longer needs
/// notifications (completed or expired), so its remaining fires are skipped.
typedef DateClosedPredicate = bool Function(LocalDate date);

/// Timezone-aware scheduling math, mirrored one-to-one by the Kotlin
/// `ScheduleCalculator` in the Android module.
///
/// Semantics:
///  * Windows and fire times are defined on the wall clock of [location].
///  * Fire times are `start + k * interval` for every `k` that stays inside the
///    window (the end time itself is included when it lands on the grid).
///  * Wall-clock times that do not exist (DST spring-forward) are shifted
///    forward by the size of the gap; ambiguous times (fall-back) resolve to
///    the earlier offset. These are exactly the rules of
///    `java.time.ZonedDateTime.of(LocalDateTime, ZoneId)` used on Android.
///  * Consecutive fire times that collapse onto the same instant after DST
///    normalisation are de-duplicated, so no duplicate notifications occur.
class ScheduleCalculator {
  ScheduleCalculator(this.location);

  final tz.Location location;

  /// The occurrence of a day may start on the previous local date when the
  /// window crosses midnight, hence one day of look-back.
  static const int lookBackDays = 1;

  /// A single selected weekday is at most 7 days away.
  static const int lookAheadDays = 7;

  static const int _millisPerDay = 24 * 60 * 60 * 1000;

  /// Local calendar date of [instant] in [location].
  LocalDate localDateOf(DateTime instant) =>
      LocalDate.of(tz.TZDateTime.from(instant, location));

  /// Wall clock representation of [instant] in [location].
  tz.TZDateTime toLocal(DateTime instant) =>
      tz.TZDateTime.from(instant, location);

  /// Resolves a wall-clock time on [date] to an absolute instant.
  /// [minutesOfDay] may exceed 1439, in which case it rolls into later dates.
  DateTime toInstant(LocalDate date, int minutesOfDay) {
    final dayOffset = minutesOfDay ~/ ReminderRule.minutesPerDay;
    final minutes = minutesOfDay % ReminderRule.minutesPerDay;
    final day = dayOffset == 0 ? date : date.plusDays(dayOffset);

    final localAsUtc = DateTime.utc(
      day.year,
      day.month,
      day.day,
      minutes ~/ 60,
      minutes % 60,
    ).millisecondsSinceEpoch;

    final offsetBefore = _offsetAt(localAsUtc - _millisPerDay);
    final offsetAfter = _offsetAt(localAsUtc + _millisPerDay);

    if (offsetBefore == offsetAfter) {
      return _utc(localAsUtc - offsetBefore);
    }

    final candidateBefore = localAsUtc - offsetBefore;
    final candidateAfter = localAsUtc - offsetAfter;
    final beforeIsValid = _offsetAt(candidateBefore) == offsetBefore;
    final afterIsValid = _offsetAt(candidateAfter) == offsetAfter;

    if (beforeIsValid) {
      // Unambiguous, or an overlap where the earlier offset wins.
      return _utc(candidateBefore);
    }
    if (afterIsValid) {
      return _utc(candidateAfter);
    }
    // Gap: interpreting the wall clock with the pre-transition offset shifts
    // the time forward by exactly the length of the gap.
    return _utc(candidateBefore);
  }

  /// The occurrence window of [rule] whose start falls on [date].
  OccurrenceWindow windowFor(ReminderRule rule, LocalDate date) {
    return OccurrenceWindow(
      date: date,
      start: toInstant(date, rule.startMinutes),
      end: toInstant(date, rule.startMinutes + rule.windowLengthMinutes),
    );
  }

  /// All notification instants of the occurrence starting on [date], in order,
  /// without duplicates. Does not check whether [date] is an eligible weekday.
  List<DateTime> firesFor(ReminderRule rule, LocalDate date) {
    final fires = <DateTime>[];
    final length = rule.windowLengthMinutes;
    DateTime? last;
    for (var offset = 0; offset <= length; offset += rule.intervalMinutes) {
      final instant = toInstant(date, rule.startMinutes + offset);
      if (last == null || instant.isAfter(last)) {
        fires.add(instant);
        last = instant;
      }
    }
    return fires;
  }

  /// The window that contains [now], if the rule is currently inside one.
  OccurrenceWindow? currentWindow(ReminderRule rule, DateTime now) {
    final today = localDateOf(now);
    // Today first: if a 24h window ends exactly when the next one starts, the
    // newer occurrence wins.
    for (var back = 0; back <= lookBackDays; back++) {
      final date = today.plusDays(-back);
      if (!rule.includesWeekday(date.weekday)) continue;
      final window = windowFor(rule, date);
      if (window.contains(now)) return window;
    }
    return null;
  }

  /// The first notification strictly after [after], skipping occurrences for
  /// which [isDateClosed] returns true. Returns null when the rule has no
  /// eligible days.
  FireTime? nextFireAfter(
    ReminderRule rule,
    DateTime after, {
    DateClosedPredicate? isDateClosed,
  }) {
    if (!rule.hasAnyDay) return null;
    final today = localDateOf(after);
    for (var i = -lookBackDays; i <= lookAheadDays; i++) {
      final date = today.plusDays(i);
      if (!rule.includesWeekday(date.weekday)) continue;
      final window = windowFor(rule, date);
      if (!window.end.isAfter(after)) continue;
      if (isDateClosed != null && isDateClosed(date)) continue;
      for (final fire in firesFor(rule, date)) {
        if (fire.isAfter(after)) {
          return FireTime(at: fire, window: window);
        }
      }
    }
    return null;
  }

  /// Start of the first occurrence window that begins strictly after [after].
  /// Used for "Next: Sunday 10:00" labels once today's occurrence is closed.
  OccurrenceWindow? nextWindowStartingAfter(ReminderRule rule, DateTime after) {
    if (!rule.hasAnyDay) return null;
    final today = localDateOf(after);
    for (var i = 0; i <= lookAheadDays; i++) {
      final date = today.plusDays(i);
      if (!rule.includesWeekday(date.weekday)) continue;
      final window = windowFor(rule, date);
      if (window.start.isAfter(after)) return window;
    }
    return null;
  }

  int _offsetAt(int millisSinceEpoch) =>
      location.timeZone(millisSinceEpoch).offset.inMilliseconds;

  static DateTime _utc(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}
