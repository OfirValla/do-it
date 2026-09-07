import 'package:do_it/core/scheduling/reminder_rule.dart';
import 'package:do_it/core/utils/local_date.dart';
import 'package:do_it/core/utils/local_time.dart';
import 'package:do_it/features/reminders/domain/weekday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DaysOfWeek', () {
    test('bitmask encoding matches the Kotlin engine (Mon=1 .. Sun=64)', () {
      expect(Weekday.monday.bit, 1);
      expect(Weekday.wednesday.bit, 4);
      expect(Weekday.sunday.bit, 64);
      expect(DaysOfWeek.everyDay.mask, 0x7F);
      expect(DaysOfWeek.weekdays.mask, 0x1F);
      expect(DaysOfWeek.weekends.mask, 0x60);
    });

    test('presets have the right labels', () {
      expect(DaysOfWeek.everyDay.label, 'Every day');
      expect(DaysOfWeek.weekdays.label, 'Weekdays');
      expect(DaysOfWeek.weekends.label, 'Weekends');
      expect(DaysOfWeek.none.label, 'No days selected');
      expect(DaysOfWeek.of([Weekday.sunday]).label, 'Sunday');
      expect(
        DaysOfWeek.of([Weekday.monday, Weekday.wednesday, Weekday.friday]).label,
        'Mon Wed Fri',
      );
    });

    test('toggle and withDay are immutable operations', () {
      const base = DaysOfWeek.weekdays;
      final withSaturday = base.toggle(Weekday.saturday);
      expect(base.contains(Weekday.saturday), isFalse);
      expect(withSaturday.contains(Weekday.saturday), isTrue);
      expect(withSaturday.withDay(Weekday.monday, false).contains(Weekday.monday), isFalse);
      expect(withSaturday.count, 6);
    });

    test('rule.includesWeekday agrees with DaysOfWeek.contains', () {
      final days = DaysOfWeek.of([Weekday.tuesday, Weekday.sunday]);
      final rule = ReminderRule(
        startMinutes: 0,
        endMinutes: 60,
        intervalMinutes: 30,
        daysMask: days.mask,
      );
      for (final day in Weekday.values) {
        expect(rule.includesWeekday(day.isoValue), days.contains(day));
      }
    });
  });

  group('LocalDate / LocalTime', () {
    test('LocalDate round-trips through ISO and knows weekdays', () {
      const date = LocalDate(2026, 9, 7);
      expect(date.toIso(), '2026-09-07');
      expect(LocalDate.parse('2026-09-07'), date);
      expect(date.weekday, DateTime.monday);
      expect(date.plusDays(6).weekday, DateTime.sunday);
      expect(date.plusDays(30), const LocalDate(2026, 10, 7));
      expect(date.daysUntil(const LocalDate(2026, 9, 10)), 3);
    });

    test('LocalTime converts to and from minutes', () {
      expect(const LocalTime(8, 30).minutesSinceMidnight, 510);
      expect(LocalTime.fromMinutes(1439), const LocalTime(23, 59));
      expect(LocalTime.fromMinutes(1440), const LocalTime(0, 0));
      expect(const LocalTime(9, 5).toHHmm(), '09:05');
    });

    test('rule window length handles midnight crossing', () {
      const normal = ReminderRule(startMinutes: 480, endMinutes: 1080, intervalMinutes: 30, daysMask: 1);
      expect(normal.crossesMidnight, isFalse);
      expect(normal.windowLengthMinutes, 600);
      const night = ReminderRule(startMinutes: 1320, endMinutes: 120, intervalMinutes: 60, daysMask: 1);
      expect(night.crossesMidnight, isTrue);
      expect(night.windowLengthMinutes, 240);
    });
  });
}
