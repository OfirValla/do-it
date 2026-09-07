import 'package:do_it/core/database/app_database.dart';
import 'package:do_it/core/scheduling/schedule_calculator.dart';
import 'package:do_it/core/utils/clock.dart';
import 'package:do_it/core/utils/local_time.dart';
import 'package:do_it/features/reminders/application/reminder_service.dart';
import 'package:do_it/features/reminders/data/reminder_repository.dart';
import 'package:do_it/features/reminders/domain/reminder.dart';
import 'package:do_it/features/reminders/domain/reminder_occurrence.dart';
import 'package:do_it/features/reminders/domain/reminder_overview.dart';
import 'package:do_it/features/reminders/domain/weekday.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_scheduler.dart';
import '../../support/test_database.dart';
import '../../support/time_helpers.dart';

void main() {
  late AppDatabase db;
  late ReminderRepository repository;
  late FakeReminderScheduler scheduler;
  late ScheduleCalculator calculator;
  late FixedClock clock;
  late ReminderService service;

  late DateTime mondayMorning; // 2026-09-07 09:17 Berlin

  const vitamins = ReminderDraft(
    title: 'Take vitamins',
    description: 'With water',
    startTime: LocalTime(8, 0),
    endTime: LocalTime(18, 0),
    intervalMinutes: 30,
    days: DaysOfWeek.weekdays,
  );

  setUp(() {
    final berlin = location('Europe/Berlin');
    calculator = ScheduleCalculator(berlin);
    mondayMorning = at(berlin, 2026, 9, 7, 9, 17);
    clock = FixedClock(mondayMorning);
    db = openTestDatabase();
    repository = ReminderRepository(db);
    scheduler = FakeReminderScheduler();
    service = ReminderService(
      repository: repository,
      scheduler: scheduler,
      calculator: calculator,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<ReminderOverview> overviewOf(int id) async {
    final reminder = (await repository.getById(id))!;
    final occurrences = await repository.getOccurrencesOn(
      calculator.localDateOf(clock.nowUtc()),
    );
    return ReminderOverview.compute(
      reminder: reminder,
      occurrences: occurrences,
      now: clock.nowUtc(),
      calculator: calculator,
    );
  }

  group('create', () {
    test('persists and schedules an enabled reminder', () async {
      final id = await service.create(vitamins);
      final stored = await repository.getById(id);
      expect(stored, isNotNull);
      expect(stored!.title, 'Take vitamins');
      expect(stored.days, DaysOfWeek.weekdays);
      expect(stored.createdAt, mondayMorning);
      expect(scheduler.calls, ['schedule:$id']);
    });

    test('stores the requested alarm duration', () async {
      final id = await service.create(
        const ReminderDraft(
          title: 'Quiet one',
          startTime: LocalTime(8, 0),
          endTime: LocalTime(9, 0),
          intervalMinutes: 15,
          days: DaysOfWeek.everyDay,
          ringMinutes: 0,
        ),
      );
      final stored = (await repository.getById(id))!;
      expect(stored.ringMinutes, 0);
      expect(stored.ringsLikeAlarm, isFalse);
    });

    test('stopRinging is forwarded without touching the database', () async {
      final id = await service.create(vitamins);
      scheduler.clear();
      await service.stopRinging(id);
      expect(scheduler.calls, ['stopRinging:$id']);
    });

    test('does not schedule a disabled reminder', () async {
      final id = await service.create(
        const ReminderDraft(
          title: 'Later',
          startTime: LocalTime(8, 0),
          endTime: LocalTime(9, 0),
          intervalMinutes: 15,
          days: DaysOfWeek.everyDay,
          enabled: false,
        ),
      );
      expect(scheduler.calls, isEmpty);
      final overview = await overviewOf(id);
      expect(overview.state, ReminderState.disabled);
      expect(overview.nextFireAt, isNull);
    });

    test('rejects invalid drafts before touching the scheduler', () async {
      expect(
        () => service.create(
          const ReminderDraft(
            title: '   ',
            startTime: LocalTime(8, 0),
            endTime: LocalTime(9, 0),
            intervalMinutes: 15,
            days: DaysOfWeek.everyDay,
          ),
        ),
        throwsA(isA<ReminderValidationException>()),
      );
      expect(
        () => service.create(
          const ReminderDraft(
            title: 'No days',
            startTime: LocalTime(8, 0),
            endTime: LocalTime(9, 0),
            intervalMinutes: 15,
            days: DaysOfWeek.none,
          ),
        ),
        throwsA(isA<ReminderValidationException>()),
      );
      expect(
        () => service.create(
          const ReminderDraft(
            title: 'Same start and end',
            startTime: LocalTime(8, 0),
            endTime: LocalTime(8, 0),
            intervalMinutes: 15,
            days: DaysOfWeek.everyDay,
          ),
        ),
        throwsA(isA<ReminderValidationException>()),
      );
      expect(
        () => service.create(
          const ReminderDraft(
            title: 'Rings too long',
            startTime: LocalTime(8, 0),
            endTime: LocalTime(9, 0),
            intervalMinutes: 15,
            days: DaysOfWeek.everyDay,
            ringMinutes: 9,
          ),
        ),
        throwsA(isA<ReminderValidationException>()),
      );
      expect(scheduler.calls, isEmpty);
      expect(await repository.getAll(), isEmpty);
    });
  });

  group('edit', () {
    test('cancels old alarms, updates, then schedules again', () async {
      final id = await service.create(vitamins);
      scheduler.clear();
      clock.advance(const Duration(minutes: 5));

      final reminder = (await repository.getById(id))!;
      await service.update(
        reminder.copyWith(startTime: const LocalTime(10, 0), intervalMinutes: 60),
      );

      expect(scheduler.calls, ['cancel:$id', 'schedule:$id']);
      final updated = (await repository.getById(id))!;
      expect(updated.startTime, const LocalTime(10, 0));
      expect(updated.intervalMinutes, 60);
      expect(updated.updatedAt.isAfter(updated.createdAt), isTrue);
      expect(updated.createdAt, reminder.createdAt);
    });

    test('editing into a disabled state only cancels', () async {
      final id = await service.create(vitamins);
      scheduler.clear();
      final reminder = (await repository.getById(id))!;
      await service.update(reminder.copyWith(enabled: false));
      expect(scheduler.calls, ['cancel:$id']);
    });
  });

  group('disable / enable', () {
    test('disable cancels, enable restores scheduling', () async {
      final id = await service.create(vitamins);
      scheduler.clear();

      await service.setEnabled(id, false);
      expect(scheduler.calls, ['cancel:$id']);
      expect((await overviewOf(id)).state, ReminderState.disabled);
      expect(scheduler.scheduled, isEmpty);

      await service.setEnabled(id, true);
      expect(scheduler.calls.last, 'schedule:$id');
      expect(scheduler.scheduled, {id});
      final overview = await overviewOf(id);
      expect(overview.state, ReminderState.active);
      // 09:17 -> next grid time is 09:30.
      expect(overview.nextFireAt, at(calculator.location, 2026, 9, 7, 9, 30));
    });
  });

  group('delete', () {
    test('cancels alarms and removes reminder with its occurrences', () async {
      final id = await service.create(vitamins);
      await service.markDone(id);
      expect(await repository.getOccurrencesOn(calculator.localDateOf(clock.nowUtc())), hasLength(1));
      scheduler.clear();

      await service.delete(id);

      expect(scheduler.calls, ['cancel:$id']);
      expect(await repository.getById(id), isNull);
      expect(await repository.getOccurrencesOn(calculator.localDateOf(clock.nowUtc())), isEmpty);
    });
  });

  group('done', () {
    test('completes today and moves the next fire to tomorrow', () async {
      final id = await service.create(vitamins);
      scheduler.clear();
      expect((await overviewOf(id)).state, ReminderState.active);

      final done = await service.markDone(id);
      expect(done, isTrue);

      final today = calculator.localDateOf(clock.nowUtc());
      final occurrence = await repository.getOccurrence(id, today);
      expect(occurrence, isNotNull);
      expect(occurrence!.status, OccurrenceStatus.completed);
      expect(occurrence.completedAt, clock.nowUtc());
      expect(occurrence.windowStart, at(calculator.location, 2026, 9, 7, 8, 0));
      expect(occurrence.windowEnd, at(calculator.location, 2026, 9, 7, 18, 0));

      // The scheduler is asked to recompute; the native engine then finds the
      // completed occurrence and skips to Tuesday 08:00. The same rule applied
      // in Dart predicts exactly that.
      expect(scheduler.calls, ['schedule:$id']);
      final overview = await overviewOf(id);
      expect(overview.state, ReminderState.completedToday);
      expect(overview.nextFireAt, at(calculator.location, 2026, 9, 8, 8, 0));
    });

    test('marking done twice keeps a single completed occurrence', () async {
      final id = await service.create(vitamins);
      await service.markDone(id);
      await service.markDone(id);
      final today = calculator.localDateOf(clock.nowUtc());
      expect(await repository.getOccurrencesOn(today), hasLength(1));
    });

    test('outside any window nothing is completed', () async {
      final id = await service.create(vitamins);
      clock.set(at(calculator.location, 2026, 9, 7, 6, 0));
      scheduler.clear();
      expect(await service.markDone(id), isFalse);
      expect(scheduler.calls, isEmpty);
    });

    test('shortly after the window ended completes that window', () async {
      final id = await service.create(vitamins);
      clock.set(at(calculator.location, 2026, 9, 7, 18, 20));
      expect(await service.markDone(id), isTrue);
      final occurrence = await repository.getOccurrence(id, calculator.localDateOf(clock.nowUtc()));
      expect(occurrence!.status, OccurrenceStatus.completed);
    });

    test('a new day starts a new occurrence', () async {
      final id = await service.create(vitamins);
      await service.markDone(id);
      clock.set(at(calculator.location, 2026, 9, 8, 8, 5));
      final overview = await overviewOf(id);
      expect(overview.state, ReminderState.active);
      expect(overview.nextFireAt, at(calculator.location, 2026, 9, 8, 8, 30));
    });
  });

  group('housekeeping', () {
    test('expires active occurrences whose window ended', () async {
      final id = await service.create(vitamins);
      final today = calculator.localDateOf(clock.nowUtc());
      final window = calculator.windowFor((await repository.getById(id))!.rule, today);
      // Simulate the native engine having created an active occurrence.
      await repository.completeOccurrence(reminderId: id, window: window, now: clock.nowUtc());
      // Re-open it as active to emulate an un-completed day.
      await db.customStatement(
        "UPDATE occurrences SET status = 'active', completed_at = NULL WHERE reminder_id = $id",
      );
      clock.set(at(calculator.location, 2026, 9, 7, 19, 0));

      await service.expireStaleOccurrences();

      final occurrence = await repository.getOccurrence(id, today);
      expect(occurrence!.status, OccurrenceStatus.expired);
    });

    test('rescheduleAll is forwarded to the scheduler', () async {
      await service.rescheduleAll();
      expect(scheduler.calls, ['rescheduleAll']);
    });
  });
}
