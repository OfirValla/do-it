import 'package:do_it/core/database/app_database.dart';
import 'package:do_it/core/scheduling/schedule_calculator.dart';
import 'package:do_it/core/utils/local_date.dart';
import 'package:do_it/core/utils/local_time.dart';
import 'package:do_it/features/reminders/data/reminder_repository.dart';
import 'package:do_it/features/reminders/domain/reminder.dart';
import 'package:do_it/features/reminders/domain/reminder_occurrence.dart';
import 'package:do_it/features/reminders/domain/weekday.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';
import '../../support/time_helpers.dart';

void main() {
  late AppDatabase db;
  late ReminderRepository repository;
  late ScheduleCalculator calculator;
  final now = DateTime.utc(2026, 9, 7, 7, 17);

  const draft = ReminderDraft(
    title: 'Call Mom',
    startTime: LocalTime(10, 0),
    endTime: LocalTime(20, 0),
    intervalMinutes: 60,
    days: DaysOfWeek(64), // Sunday
  );

  setUp(() {
    db = openTestDatabase();
    repository = ReminderRepository(db);
    calculator = ScheduleCalculator(location('Europe/Berlin'));
  });

  tearDown(() => db.close());

  test('insert, read, update, delete', () async {
    final id = await repository.insert(draft, now);
    final stored = (await repository.getById(id))!;
    expect(stored.title, 'Call Mom');
    expect(stored.startTime, const LocalTime(10, 0));
    expect(stored.endTime, const LocalTime(20, 0));
    expect(stored.intervalMinutes, 60);
    expect(stored.days.toList(), [Weekday.sunday]);
    expect(stored.enabled, isTrue);
    expect(stored.ringMinutes, Reminder.defaultRingMinutes);
    expect(stored.ringsLikeAlarm, isTrue);

    await repository.update(
      stored.copyWith(title: 'Call Dad', days: DaysOfWeek.weekends, ringMinutes: 5),
      now.add(const Duration(minutes: 1)),
    );
    final updated = (await repository.getById(id))!;
    expect(updated.title, 'Call Dad');
    expect(updated.days, DaysOfWeek.weekends);
    expect(updated.ringMinutes, 5);
    expect(updated.updatedAt, now.add(const Duration(minutes: 1)));

    await repository.delete(id);
    expect(await repository.getById(id), isNull);
  });

  test('watchAll orders by start time and emits on changes', () async {
    final stream = repository.watchAll();
    final first = await stream.first;
    expect(first, isEmpty);

    await repository.insert(draft, now);
    await repository.insert(
      const ReminderDraft(
        title: 'Early bird',
        startTime: LocalTime(6, 30),
        endTime: LocalTime(7, 0),
        intervalMinutes: 10,
        days: DaysOfWeek.everyDay,
      ),
      now,
    );
    final all = await repository.getAll();
    expect(all.map((r) => r.title), ['Early bird', 'Call Mom']);
  });

  test('getEnabled only returns enabled reminders', () async {
    final a = await repository.insert(draft, now);
    await repository.insert(draft, now);
    await repository.setEnabled(a, false, now);
    final enabled = await repository.getEnabled();
    expect(enabled, hasLength(1));
    expect(enabled.single.id, isNot(a));
  });

  test("today's occurrences and active occurrences", () async {
    final id = await repository.insert(draft, now);
    const sunday = LocalDate(2026, 9, 13);
    final window = calculator.windowFor((await repository.getById(id))!.rule, sunday);
    final inWindow = window.start.add(const Duration(hours: 2));

    // Emulate the engine's insert of an active occurrence (what the alarm does).
    await db.into(db.occurrences).insert(
          OccurrencesCompanion.insert(
            reminderId: id,
            occurrenceDate: sunday.toIso(),
            status: OccurrenceStatus.active.dbValue,
            windowStart: window.start.millisecondsSinceEpoch,
            windowEnd: window.end.millisecondsSinceEpoch,
          ),
        );

    final today = await repository.getOccurrencesOn(sunday);
    expect(today, hasLength(1));
    expect(today.single.status, OccurrenceStatus.active);
    expect(today.single.windowStart, window.start);

    expect(await repository.getActiveOccurrences(inWindow), hasLength(1));
    expect(await repository.getActiveOccurrences(window.end.add(const Duration(seconds: 1))), isEmpty);

    // Housekeeping after the window: becomes expired.
    final expired = await repository.expireStaleOccurrences(window.end.add(const Duration(minutes: 1)));
    expect(expired, 1);
    expect((await repository.getOccurrence(id, sunday))!.status, OccurrenceStatus.expired);
  });

  test('completeOccurrence upgrades an existing active row', () async {
    final id = await repository.insert(draft, now);
    const sunday = LocalDate(2026, 9, 13);
    final window = calculator.windowFor((await repository.getById(id))!.rule, sunday);
    await db.into(db.occurrences).insert(
          OccurrencesCompanion.insert(
            reminderId: id,
            occurrenceDate: sunday.toIso(),
            status: OccurrenceStatus.active.dbValue,
            windowStart: window.start.millisecondsSinceEpoch,
            windowEnd: window.end.millisecondsSinceEpoch,
          ),
        );
    final completedAt = window.start.add(const Duration(hours: 3, minutes: 24));
    await repository.completeOccurrence(reminderId: id, window: window, now: completedAt);

    final rows = await repository.getOccurrencesOn(sunday);
    expect(rows, hasLength(1));
    expect(rows.single.status, OccurrenceStatus.completed);
    expect(rows.single.completedAt, completedAt);
  });

  test('watchOccurrencesSince covers the previous day', () async {
    final id = await repository.insert(draft, now);
    for (final date in const [LocalDate(2026, 9, 5), LocalDate(2026, 9, 6), LocalDate(2026, 9, 7)]) {
      final window = calculator.windowFor((await repository.getById(id))!.rule, date);
      await repository.completeOccurrence(reminderId: id, window: window, now: window.start);
    }
    final recent = await repository.watchOccurrencesSince(const LocalDate(2026, 9, 6)).first;
    expect(recent.map((o) => o.date.toIso()), ['2026-09-07', '2026-09-06']);

    final history = await repository.watchOccurrencesOf(id).first;
    expect(history, hasLength(3));
    expect(history.first.date, const LocalDate(2026, 9, 7));
  });

  test('deleting a reminder cascades to its occurrences', () async {
    final id = await repository.insert(draft, now);
    const sunday = LocalDate(2026, 9, 13);
    final window = calculator.windowFor((await repository.getById(id))!.rule, sunday);
    await repository.completeOccurrence(reminderId: id, window: window, now: window.start);
    await repository.delete(id);
    expect(await repository.getOccurrencesOn(sunday), isEmpty);
  });
}
