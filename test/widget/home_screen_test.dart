import 'package:do_it/app.dart';
import 'package:do_it/core/database/app_database.dart';
import 'package:do_it/core/platform/do_it_platform.dart';
import 'package:do_it/core/utils/clock.dart';
import 'package:do_it/core/utils/local_time.dart';
import 'package:do_it/features/reminders/domain/reminder.dart';
import 'package:do_it/features/reminders/domain/weekday.dart';
import 'package:do_it/features/reminders/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';
import '../support/time_helpers.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;

  setUp(() {
    db = openTestDatabase();
    clock = FixedClock(at(location('Europe/Berlin'), 2026, 9, 7, 9, 17));
  });

  tearDown(() => db.close());

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        platformProvider.overrideWithValue(const UnsupportedDoItPlatform()),
        appDatabaseProvider.overrideWithValue(db),
        timeZoneLocationProvider.overrideWithValue(location('Europe/Berlin')),
        clockProvider.overrideWithValue(clock),
        // The periodic ticker would leave a pending timer in widget tests.
        tickerProvider.overrideWith((ref) => Stream.value(clock.nowUtc())),
      ],
      child: const DoItApp(),
    );
  }

  testWidgets('shows the empty state and the add button', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Do It'), findsOneWidget);
    expect(find.text('Nothing to do yet'), findsOneWidget);
    expect(find.text('Add Reminder'), findsOneWidget);
  });

  testWidgets('renders an active reminder with a Done button that completes it',
      (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(reminderServiceProvider).create(
          const ReminderDraft(
            title: 'Take vitamins',
            startTime: LocalTime(8, 0),
            endTime: LocalTime(18, 0),
            intervalMinutes: 30,
            days: DaysOfWeek.weekdays,
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('Take vitamins'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.textContaining('Every 30 minutes'), findsOneWidget);
    expect(find.text('Weekdays'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE'), findsNothing);
    expect(find.textContaining('Done for today'), findsOneWidget);
    expect(find.textContaining('Tomorrow'), findsOneWidget);

    // Let the confirmation SnackBar time out so no timer is left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('add flow creates a reminder from the form', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Reminder'));
    await tester.pumpAndSettle();

    expect(find.text('New reminder'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Call Mom');
    await tester.tap(find.text('Weekends'));
    await tester.pump();
    await tester.tap(find.text('1 h'));
    await tester.pump();

    await tester.ensureVisible(find.text('Create Reminder'));
    await tester.tap(find.text('Create Reminder'));
    await tester.pumpAndSettle();

    expect(find.text('Call Mom'), findsOneWidget);
    expect(find.textContaining('Every hour'), findsOneWidget);
    expect(find.text('Weekends'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
