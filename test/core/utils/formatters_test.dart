import 'package:do_it/core/utils/formatters.dart';
import 'package:do_it/core/utils/local_date.dart';
import 'package:do_it/core/utils/local_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../support/time_helpers.dart';

void main() {
  group('Formatters.interval', () {
    test('minutes, hours and mixed', () {
      expect(Formatters.interval(1), 'Every minute');
      expect(Formatters.interval(5), 'Every 5 minutes');
      expect(Formatters.interval(30), 'Every 30 minutes');
      expect(Formatters.interval(60), 'Every hour');
      expect(Formatters.interval(120), 'Every 2 hours');
      expect(Formatters.interval(90), 'Every 1 h 30 min');
      expect(Formatters.intervalShort(15), '15 min');
      expect(Formatters.intervalShort(60), '1 h');
      expect(Formatters.intervalShort(150), '2 h 30');
    });
  });

  group('Formatters.nextFire', () {
    late tz.Location berlin;
    const today = LocalDate(2026, 9, 7);
    String fmt(LocalTime t) => t.toHHmm();

    setUpAll(() => berlin = location('Europe/Berlin'));

    test('today shows the time only', () {
      final next = tz.TZDateTime(berlin, 2026, 9, 7, 9, 30);
      expect(Formatters.nextFire(next, today, fmt), '09:30');
    });

    test('tomorrow and weekdays are named', () {
      expect(
        Formatters.nextFire(tz.TZDateTime(berlin, 2026, 9, 8, 8, 0), today, fmt),
        'Tomorrow 08:00',
      );
      expect(
        Formatters.nextFire(tz.TZDateTime(berlin, 2026, 9, 13, 10, 0), today, fmt),
        'Sunday 10:00',
      );
    });

    test('a week or more away shows the date', () {
      final label = Formatters.nextFire(tz.TZDateTime(berlin, 2026, 9, 14, 10, 0), today, fmt);
      expect(label, contains('Sep 14'));
      expect(label, endsWith('10:00'));
    });

    test('relativeDay', () {
      expect(Formatters.relativeDay(today, today), 'Today');
      expect(Formatters.relativeDay(today.plusDays(-1), today), 'Yesterday');
      expect(Formatters.relativeDay(today.plusDays(3), today), 'Thursday');
    });
  });
}
