import 'package:do_it/core/scheduling/reminder_rule.dart';
import 'package:do_it/core/scheduling/schedule_calculator.dart';
import 'package:do_it/core/utils/local_date.dart';
import 'package:do_it/features/reminders/domain/weekday.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/time_helpers.dart';

/// Mirrors android/app/src/test/.../ScheduleCalculatorTest.kt so both
/// implementations are held to the same expectations.
void main() {
  late ScheduleCalculator berlin;
  late ScheduleCalculator newYork;

  // Monday 2026-09-07, a plain CEST day.
  const monday = LocalDate(2026, 9, 7);

  ReminderRule rule(int start, int end, int interval, DaysOfWeek days) =>
      ReminderRule(
        startMinutes: start,
        endMinutes: end,
        intervalMinutes: interval,
        daysMask: days.mask,
      );

  setUpAll(() {
    berlin = ScheduleCalculator(location('Europe/Berlin'));
    newYork = ScheduleCalculator(location('America/New_York'));
  });

  group('daily reminder', () {
    final r = rule(8 * 60, 18 * 60, 30, DaysOfWeek.everyDay);

    test('fires every 30 minutes from start to end inclusive', () {
      final fires = berlin.firesFor(r, monday);
      expect(fires, hasLength(21));
      expect(fires.first, at(berlin.location, 2026, 9, 7, 8, 0));
      expect(fires[3], at(berlin.location, 2026, 9, 7, 9, 30));
      expect(fires.last, at(berlin.location, 2026, 9, 7, 18, 0));
    });

    test('next fire after a grid time is strictly later', () {
      final next = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 7, 9, 0));
      expect(next!.at, at(berlin.location, 2026, 9, 7, 9, 30));
      expect(next.window.date, monday);
    });

    test('mid-interval creation schedules the next grid time', () {
      final next = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 7, 9, 17));
      expect(next!.at, at(berlin.location, 2026, 9, 7, 9, 30));
    });

    test('after the end time the next fire is tomorrow at start', () {
      final next = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 7, 18, 0));
      expect(next!.at, at(berlin.location, 2026, 9, 8, 8, 0));
      expect(next.window.date, const LocalDate(2026, 9, 8));
    });

    test('a completed date is skipped entirely', () {
      final next = berlin.nextFireAfter(
        r,
        at(berlin.location, 2026, 9, 7, 9, 17),
        isDateClosed: (d) => d == monday,
      );
      expect(next!.at, at(berlin.location, 2026, 9, 8, 8, 0));
    });
  });

  group('days of week', () {
    test('weekday reminder skips the weekend', () {
      final r = rule(9 * 60, 10 * 60, 60, DaysOfWeek.weekdays);
      // Friday 2026-09-11 12:00 -> Monday 2026-09-14 09:00.
      final next = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 11, 12, 0));
      expect(next!.at, at(berlin.location, 2026, 9, 14, 9, 0));
    });

    test('weekend reminder waits for Saturday', () {
      final r = rule(10 * 60, 12 * 60, 60, DaysOfWeek.weekends);
      final next = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 7, 8, 0));
      expect(next!.at, at(berlin.location, 2026, 9, 12, 10, 0));
    });

    test('custom days pick the next eligible date', () {
      final r = rule(
        7 * 60,
        8 * 60,
        30,
        DaysOfWeek.of([Weekday.tuesday, Weekday.thursday]),
      );
      final fromMonday = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 7, 9, 0));
      expect(fromMonday!.at, at(berlin.location, 2026, 9, 8, 7, 0));
      final fromTuesdayEvening = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 8, 20, 0));
      expect(fromTuesdayEvening!.at, at(berlin.location, 2026, 9, 10, 7, 0));
    });

    test('single day is at most a week away', () {
      final r = rule(10 * 60, 20 * 60, 60, DaysOfWeek.of([Weekday.sunday]));
      final next = berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 6, 21, 0));
      expect(next!.at, at(berlin.location, 2026, 9, 13, 10, 0));
    });

    test('no days selected yields nothing', () {
      final r = rule(8 * 60, 18 * 60, 30, DaysOfWeek.none);
      expect(berlin.nextFireAfter(r, at(berlin.location, 2026, 9, 7, 9, 0)), isNull);
      expect(berlin.nextWindowStartingAfter(r, at(berlin.location, 2026, 9, 7, 9, 0)), isNull);
    });
  });

  group('intervals', () {
    test('5 minutes', () {
      final r = rule(8 * 60, 9 * 60, 5, DaysOfWeek.everyDay);
      expect(berlin.firesFor(r, monday), hasLength(13));
    });

    test('30 minutes', () {
      final r = rule(8 * 60, 12 * 60, 30, DaysOfWeek.everyDay);
      expect(berlin.firesFor(r, monday), hasLength(9));
    });

    test('1 hour', () {
      final r = rule(10 * 60, 20 * 60, 60, DaysOfWeek.everyDay);
      final fires = berlin.firesFor(r, monday);
      expect(fires, hasLength(11));
      expect(fires[3], at(berlin.location, 2026, 9, 7, 13, 0));
    });

    test('interval longer than the window fires once at start', () {
      final r = rule(8 * 60, 8 * 60 + 20, 60, DaysOfWeek.everyDay);
      expect(berlin.firesFor(r, monday), [at(berlin.location, 2026, 9, 7, 8, 0)]);
    });
  });

  group('boundaries', () {
    final r = rule(8 * 60, 18 * 60, 30, DaysOfWeek.everyDay);

    test('window is inclusive at start and end', () {
      expect(berlin.currentWindow(r, at(berlin.location, 2026, 9, 7, 7, 59)), isNull);
      expect(berlin.currentWindow(r, at(berlin.location, 2026, 9, 7, 8, 0)), isNotNull);
      expect(berlin.currentWindow(r, at(berlin.location, 2026, 9, 7, 18, 0)), isNotNull);
      expect(berlin.currentWindow(r, at(berlin.location, 2026, 9, 7, 18, 1)), isNull);
    });

    test('end time off the grid is not a fire time', () {
      final off = rule(8 * 60, 17 * 60 + 50, 30, DaysOfWeek.everyDay);
      expect(berlin.firesFor(off, monday).last, at(berlin.location, 2026, 9, 7, 17, 30));
    });

    test('just before midnight rolls into the next day correctly', () {
      final late = rule(23 * 60, 23 * 60 + 59, 30, DaysOfWeek.everyDay);
      final next = berlin.nextFireAfter(late, at(berlin.location, 2026, 9, 7, 23, 45));
      expect(next!.at, at(berlin.location, 2026, 9, 8, 23, 0));
    });

    test('window crossing midnight belongs to the start date', () {
      final night = rule(22 * 60, 2 * 60, 60, DaysOfWeek.of([Weekday.monday]));
      final fires = berlin.firesFor(night, monday);
      expect(fires, hasLength(5));
      expect(fires.last, at(berlin.location, 2026, 9, 8, 2, 0));

      final window = berlin.currentWindow(night, at(berlin.location, 2026, 9, 8, 1, 30));
      expect(window!.date, monday);

      final next = berlin.nextFireAfter(night, at(berlin.location, 2026, 9, 8, 0, 10));
      expect(next!.at, at(berlin.location, 2026, 9, 8, 1, 0));
      expect(next.window.date, monday);

      // Tuesday itself is not selected: after the window ends, next Monday.
      final after = berlin.nextFireAfter(night, at(berlin.location, 2026, 9, 8, 2, 0));
      expect(after!.at, at(berlin.location, 2026, 9, 14, 22, 0));
    });

    test('localDateOf uses the zone, not UTC', () {
      // 23:30 UTC on Sep 7 is already Sep 8 in Berlin.
      expect(berlin.localDateOf(utc(2026, 9, 7, 23, 30)), const LocalDate(2026, 9, 8));
      expect(newYork.localDateOf(utc(2026, 9, 7, 23, 30)), const LocalDate(2026, 9, 7));
    });
  });

  group('daylight saving time', () {
    test('spring forward: no duplicate and no missing notifications', () {
      // Berlin 2026-03-29: 02:00 CET -> 03:00 CEST (01:00Z).
      final r = rule(1 * 60, 5 * 60, 30, DaysOfWeek.everyDay);
      final fires = berlin.firesFor(r, const LocalDate(2026, 3, 29));
      expect(fires, [
        utc(2026, 3, 29, 0, 0),
        utc(2026, 3, 29, 0, 30),
        utc(2026, 3, 29, 1, 0),
        utc(2026, 3, 29, 1, 30),
        utc(2026, 3, 29, 2, 0),
        utc(2026, 3, 29, 2, 30),
        utc(2026, 3, 29, 3, 0),
      ]);
    });

    test('fall back: instants stay strictly increasing', () {
      // Berlin 2026-10-25: 03:00 CEST -> 02:00 CET.
      final r = rule(1 * 60, 4 * 60, 30, DaysOfWeek.everyDay);
      final fires = berlin.firesFor(r, const LocalDate(2026, 10, 25));
      expect(fires, hasLength(7));
      for (var i = 1; i < fires.length; i++) {
        expect(fires[i].isAfter(fires[i - 1]), isTrue);
      }
      expect(fires.first, utc(2026, 10, 24, 23, 0));
      expect(fires.last, utc(2026, 10, 25, 3, 0));
    });

    test('gap resolves like java.time (forward by the gap)', () {
      // New York 2026-03-08 02:30 does not exist -> 03:30 EDT = 07:30Z.
      expect(
        newYork.toInstant(const LocalDate(2026, 3, 8), 2 * 60 + 30),
        utc(2026, 3, 8, 7, 30),
      );
    });

    test('overlap resolves to the earlier offset', () {
      // New York 2026-11-01 01:30 exists twice -> EDT wins = 05:30Z.
      expect(
        newYork.toInstant(const LocalDate(2026, 11, 1), 1 * 60 + 30),
        utc(2026, 11, 1, 5, 30),
      );
    });

    test('a window spanning the transition keeps its wall-clock end', () {
      final r = rule(0, 6 * 60, 60, DaysOfWeek.everyDay);
      final window = berlin.windowFor(r, const LocalDate(2026, 3, 29));
      // 00:00 CET = 23:00Z (prev day); 06:00 CEST = 04:00Z: only 5 real hours.
      expect(window.start, utc(2026, 3, 28, 23, 0));
      expect(window.end, utc(2026, 3, 29, 4, 0));
    });
  });

  group('timezone changes', () {
    test('the same wall-clock rule yields different instants per zone', () {
      final r = rule(8 * 60, 18 * 60, 30, DaysOfWeek.everyDay);
      final after = utc(2026, 9, 7, 3, 0);
      expect(berlin.nextFireAfter(r, after)!.at, utc(2026, 9, 7, 6, 0));
      expect(newYork.nextFireAfter(r, after)!.at, utc(2026, 9, 7, 12, 0));
    });

    test('recalculating in a new zone re-anchors the chain', () {
      final r = rule(8 * 60, 18 * 60, 30, DaysOfWeek.everyDay);
      // User flew from Berlin to New York; it is 09:17 in New York.
      final now = at(newYork.location, 2026, 9, 7, 9, 17);
      expect(newYork.nextFireAfter(r, now)!.at, at(newYork.location, 2026, 9, 7, 9, 30));
      // In Berlin it is already 15:17 so the Berlin schedule would be 15:30.
      expect(berlin.nextFireAfter(r, now)!.at, at(berlin.location, 2026, 9, 7, 15, 30));
    });
  });

  group('next window', () {
    test('nextWindowStartingAfter ignores the current window', () {
      final r = rule(8 * 60, 18 * 60, 30, DaysOfWeek.everyDay);
      final next = berlin.nextWindowStartingAfter(r, at(berlin.location, 2026, 9, 7, 9, 0));
      expect(next!.date, const LocalDate(2026, 9, 8));
      expect(next.start, at(berlin.location, 2026, 9, 8, 8, 0));
    });
  });
}
