import 'package:drift/drift.dart';

/// Schema shared with the native Android engine.
///
/// IMPORTANT: table and column names are spelled out explicitly because the
/// Kotlin `SqliteReminderStore` queries the very same SQLite file by these
/// names. Any change here must be mirrored there (and shipped as a migration in
/// `AppDatabase`).
///
/// Conventions:
///  * times of day are stored as minutes since midnight (0..1439),
///  * instants are stored as epoch milliseconds (UTC),
///  * calendar dates are stored as ISO strings `yyyy-MM-dd` (local date),
///  * days of the week are a 7-bit mask, Monday = 1 ... Sunday = 64.
@DataClassName('ReminderRow')
class Reminders extends Table {
  @override
  String get tableName => 'reminders';

  IntColumn get id => integer().named('id').autoIncrement()();
  TextColumn get title => text().named('title')();
  TextColumn get description =>
      text().named('description').withDefault(const Constant(''))();
  IntColumn get startMinutes => integer().named('start_minutes')();
  IntColumn get endMinutes => integer().named('end_minutes')();
  IntColumn get intervalMinutes => integer().named('interval_minutes')();
  IntColumn get daysOfWeek => integer().named('days_of_week')();
  BoolColumn get enabled =>
      boolean().named('enabled').withDefault(const Constant(true))();

  /// How long the device rings like an alarm clock when a notification fires:
  /// 0 = notification only, 1..5 minutes. Added in schema version 2.
  IntColumn get ringMinutes =>
      integer().named('ring_minutes').withDefault(const Constant(2))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
}

@DataClassName('OccurrenceRow')
class Occurrences extends Table {
  @override
  String get tableName => 'occurrences';

  IntColumn get id => integer().named('id').autoIncrement()();
  IntColumn get reminderId => integer()
      .named('reminder_id')
      .references(Reminders, #id, onDelete: KeyAction.cascade)();
  TextColumn get occurrenceDate => text().named('occurrence_date')();

  /// One of `active`, `completed`, `expired`.
  TextColumn get status => text().named('status')();
  IntColumn get windowStart => integer().named('window_start')();
  IntColumn get windowEnd => integer().named('window_end')();
  IntColumn get completedAt => integer().named('completed_at').nullable()();
  IntColumn get notificationCount =>
      integer().named('notification_count').withDefault(const Constant(0))();
  IntColumn get lastNotifiedAt =>
      integer().named('last_notified_at').nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {reminderId, occurrenceDate},
      ];
}

/// Simple key/value store for user preferences (Flutter side only).
@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text().named('key')();
  TextColumn get value => text().named('value')();

  @override
  Set<Column> get primaryKey => {key};
}
