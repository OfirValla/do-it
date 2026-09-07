import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/notifications/permission_service.dart';
import '../../../core/notifications/permission_status.dart';
import '../../../core/platform/do_it_platform.dart';
import '../../../core/scheduling/android_reminder_scheduler.dart';
import '../../../core/scheduling/reminder_scheduler.dart';
import '../../../core/scheduling/schedule_calculator.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/local_date.dart';
import '../../settings/data/settings_repository.dart';
import '../application/reminder_service.dart';
import '../data/reminder_repository.dart';
import '../domain/reminder.dart';
import '../domain/reminder_occurrence.dart';
import '../domain/reminder_overview.dart';

// -----------------------------------------------------------------------------
// Infrastructure (overridden in main.dart once the async bootstrap finished)
// -----------------------------------------------------------------------------

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final platformProvider = Provider<DoItPlatform>(
  (ref) => throw UnimplementedError('platformProvider must be overridden'),
);

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

final timeZoneLocationProvider = Provider<tz.Location>(
  (ref) =>
      throw UnimplementedError('timeZoneLocationProvider must be overridden'),
);

final scheduleCalculatorProvider = Provider<ScheduleCalculator>(
  (ref) => ScheduleCalculator(ref.watch(timeZoneLocationProvider)),
);

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  final platform = ref.watch(platformProvider);
  return platform.isSupported
      ? AndroidReminderScheduler(platform)
      : const NoopReminderScheduler();
});

final permissionServiceProvider = Provider<NotificationPermissionService>(
  (ref) => PlatformNotificationPermissionService(ref.watch(platformProvider)),
);

final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository(ref.watch(appDatabaseProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(
    repository: ref.watch(reminderRepositoryProvider),
    scheduler: ref.watch(reminderSchedulerProvider),
    calculator: ref.watch(scheduleCalculatorProvider),
    clock: ref.watch(clockProvider),
  ),
);

// -----------------------------------------------------------------------------
// Time
// -----------------------------------------------------------------------------

/// Emits "now" immediately and then twice a minute, so "Next: 09:30" labels
/// and ACTIVE badges update while the screen is open.
final tickerProvider = StreamProvider<DateTime>((ref) async* {
  final clock = ref.watch(clockProvider);
  yield clock.nowUtc();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => clock.nowUtc());
});

final nowProvider = Provider<DateTime>((ref) {
  return ref.watch(tickerProvider).value ?? ref.watch(clockProvider).nowUtc();
});

/// Local calendar date; only notifies dependents when the date changes.
final todayProvider = Provider<LocalDate>((ref) {
  final calculator = ref.watch(scheduleCalculatorProvider);
  return calculator.localDateOf(ref.watch(nowProvider));
});

// -----------------------------------------------------------------------------
// Reminders
// -----------------------------------------------------------------------------

final remindersProvider = StreamProvider<List<Reminder>>(
  (ref) => ref.watch(reminderRepositoryProvider).watchAll(),
);

/// Occurrences from yesterday onwards (windows may cross midnight).
final recentOccurrencesProvider = StreamProvider<List<ReminderOccurrence>>(
  (ref) {
    final since = ref.watch(todayProvider).plusDays(-1);
    return ref.watch(reminderRepositoryProvider).watchOccurrencesSince(since);
  },
);

final reminderOverviewsProvider =
    Provider<AsyncValue<List<ReminderOverview>>>((ref) {
  final now = ref.watch(nowProvider);
  final calculator = ref.watch(scheduleCalculatorProvider);
  final occurrences =
      ref.watch(recentOccurrencesProvider).value ?? const <ReminderOccurrence>[];
  return ref.watch(remindersProvider).whenData(
        (reminders) => [
          for (final reminder in reminders)
            ReminderOverview.compute(
              reminder: reminder,
              occurrences: occurrences,
              now: now,
              calculator: calculator,
            ),
        ],
      );
});

final reminderProvider = StreamProvider.family<Reminder?, int>(
  (ref, id) => ref.watch(reminderRepositoryProvider).watchById(id),
);

final occurrenceHistoryProvider =
    StreamProvider.family<List<ReminderOccurrence>, int>(
  (ref, id) => ref.watch(reminderRepositoryProvider).watchOccurrencesOf(id),
);

final reminderOverviewProvider =
    Provider.family<AsyncValue<ReminderOverview?>, int>((ref, id) {
  final now = ref.watch(nowProvider);
  final calculator = ref.watch(scheduleCalculatorProvider);
  final history =
      ref.watch(occurrenceHistoryProvider(id)).value ?? const <ReminderOccurrence>[];
  return ref.watch(reminderProvider(id)).whenData((reminder) {
    if (reminder == null) return null;
    return ReminderOverview.compute(
      reminder: reminder,
      occurrences: history,
      now: now,
      calculator: calculator,
    );
  });
});

// -----------------------------------------------------------------------------
// Settings & permissions
// -----------------------------------------------------------------------------

final permissionStatusProvider = FutureProvider<PermissionStatusSnapshot>(
  (ref) => ref.watch(permissionServiceProvider).status(),
);

final defaultIntervalProvider = StreamProvider<int>(
  (ref) => ref.watch(settingsRepositoryProvider).watchDefaultIntervalMinutes(),
);

final defaultRingMinutesProvider = StreamProvider<int>(
  (ref) => ref.watch(settingsRepositoryProvider).watchDefaultRingMinutes(),
);

/// Id of the reminder whose alarm is ringing right now (null when silent).
/// Seeded from native state, then follows native ring start/stop events.
final ringingReminderProvider = StreamProvider<int?>((ref) async* {
  final platform = ref.watch(platformProvider);
  yield await platform.getRingingReminderId();
  yield* platform.ringingChanges;
});
