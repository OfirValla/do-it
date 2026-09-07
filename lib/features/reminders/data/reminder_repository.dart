import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/scheduling/schedule_calculator.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/utils/local_time.dart';
import '../domain/reminder.dart';
import '../domain/reminder_occurrence.dart';
import '../domain/weekday.dart';

/// Persistence for reminders and their occurrences.
///
/// The repository is the only place that knows about Drift row classes; the
/// rest of the app works with the domain types in `../domain`.
class ReminderRepository {
  ReminderRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Reminders
  // ---------------------------------------------------------------------------

  Stream<List<Reminder>> watchAll() => _orderedReminders().watch().map(_mapAll);

  Future<List<Reminder>> getAll() async => _mapAll(await _orderedReminders().get());

  Future<List<Reminder>> getEnabled() async {
    final rows = await (_orderedReminders()
          ..where((t) => t.enabled.equals(true)))
        .get();
    return _mapAll(rows);
  }

  Future<Reminder?> getById(int id) async {
    final row = await (_db.select(_db.reminders)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toReminder(row);
  }

  Stream<Reminder?> watchById(int id) =>
      (_db.select(_db.reminders)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _toReminder(row));

  /// Inserts a new reminder and returns its id.
  Future<int> insert(ReminderDraft draft, DateTime now) {
    final millis = now.toUtc().millisecondsSinceEpoch;
    return _db.into(_db.reminders).insert(
          RemindersCompanion.insert(
            title: draft.title.trim(),
            description: Value(draft.description.trim()),
            startMinutes: draft.startTime.minutesSinceMidnight,
            endMinutes: draft.endTime.minutesSinceMidnight,
            intervalMinutes: draft.intervalMinutes,
            daysOfWeek: draft.days.mask,
            enabled: Value(draft.enabled),
            ringMinutes: Value(draft.ringMinutes),
            createdAt: millis,
            updatedAt: millis,
          ),
        );
  }

  Future<void> update(Reminder reminder, DateTime now) async {
    await (_db.update(_db.reminders)..where((t) => t.id.equals(reminder.id)))
        .write(
      RemindersCompanion(
        title: Value(reminder.title.trim()),
        description: Value(reminder.description.trim()),
        startMinutes: Value(reminder.startTime.minutesSinceMidnight),
        endMinutes: Value(reminder.endTime.minutesSinceMidnight),
        intervalMinutes: Value(reminder.intervalMinutes),
        daysOfWeek: Value(reminder.days.mask),
        enabled: Value(reminder.enabled),
        ringMinutes: Value(reminder.ringMinutes),
        updatedAt: Value(now.toUtc().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> setEnabled(int id, bool enabled, DateTime now) async {
    await (_db.update(_db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        enabled: Value(enabled),
        updatedAt: Value(now.toUtc().millisecondsSinceEpoch),
      ),
    );
  }

  /// Deletes the reminder and (explicitly, in addition to the FK cascade) all
  /// of its occurrences.
  Future<void> delete(int id) {
    return _db.transaction(() async {
      await (_db.delete(_db.occurrences)
            ..where((t) => t.reminderId.equals(id)))
          .go();
      await (_db.delete(_db.reminders)..where((t) => t.id.equals(id))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Occurrences
  // ---------------------------------------------------------------------------

  /// All occurrences whose window started on or after [since], newest first.
  /// The home screen uses yesterday as [since] to cover windows that cross
  /// midnight.
  Stream<List<ReminderOccurrence>> watchOccurrencesSince(LocalDate since) {
    final query = _db.select(_db.occurrences)
      ..where((t) => t.occurrenceDate.isBiggerOrEqualValue(since.toIso()))
      ..orderBy([(t) => OrderingTerm.desc(t.occurrenceDate)]);
    return query.watch().map(_mapOccurrences);
  }

  /// History of a single reminder, newest first.
  Stream<List<ReminderOccurrence>> watchOccurrencesOf(
    int reminderId, {
    int limit = 60,
  }) {
    final query = _db.select(_db.occurrences)
      ..where((t) => t.reminderId.equals(reminderId))
      ..orderBy([(t) => OrderingTerm.desc(t.occurrenceDate)])
      ..limit(limit);
    return query.watch().map(_mapOccurrences);
  }

  Future<List<ReminderOccurrence>> getOccurrencesOn(LocalDate date) async {
    final rows = await (_db.select(_db.occurrences)
          ..where((t) => t.occurrenceDate.equals(date.toIso())))
        .get();
    return _mapOccurrences(rows);
  }

  Future<ReminderOccurrence?> getOccurrence(int reminderId, LocalDate date) async {
    final row = await (_db.select(_db.occurrences)
          ..where((t) =>
              t.reminderId.equals(reminderId) &
              t.occurrenceDate.equals(date.toIso())))
        .getSingleOrNull();
    return row == null ? null : _toOccurrence(row);
  }

  /// Occurrences that are still active right now (their window contains
  /// [now] and they were not completed).
  Future<List<ReminderOccurrence>> getActiveOccurrences(DateTime now) async {
    final millis = now.toUtc().millisecondsSinceEpoch;
    final rows = await (_db.select(_db.occurrences)
          ..where((t) =>
              t.status.equals(OccurrenceStatus.active.dbValue) &
              t.windowStart.isSmallerOrEqualValue(millis) &
              t.windowEnd.isBiggerOrEqualValue(millis)))
        .get();
    return _mapOccurrences(rows);
  }

  /// Marks the occurrence of [reminderId] in [window] as completed, creating
  /// the row if no notification has fired yet for that date.
  ///
  /// Uses select-then-write instead of UPSERT so the semantics match the
  /// Kotlin implementation exactly (which must run on older system SQLite).
  Future<void> completeOccurrence({
    required int reminderId,
    required OccurrenceWindow window,
    required DateTime now,
  }) {
    final millis = now.toUtc().millisecondsSinceEpoch;
    return _db.transaction(() async {
      final existing = await (_db.select(_db.occurrences)
            ..where((t) =>
                t.reminderId.equals(reminderId) &
                t.occurrenceDate.equals(window.date.toIso())))
          .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.occurrences).insert(
              OccurrencesCompanion.insert(
                reminderId: reminderId,
                occurrenceDate: window.date.toIso(),
                status: OccurrenceStatus.completed.dbValue,
                windowStart: window.start.millisecondsSinceEpoch,
                windowEnd: window.end.millisecondsSinceEpoch,
                completedAt: Value(millis),
              ),
            );
      } else {
        await (_db.update(_db.occurrences)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          OccurrencesCompanion(
            status: Value(OccurrenceStatus.completed.dbValue),
            completedAt: Value(millis),
          ),
        );
      }
    });
  }

  /// Housekeeping: any active occurrence whose window has ended becomes
  /// expired. Idempotent; also executed by the native engine.
  Future<int> expireStaleOccurrences(DateTime now) {
    final millis = now.toUtc().millisecondsSinceEpoch;
    return (_db.update(_db.occurrences)
          ..where((t) =>
              t.status.equals(OccurrenceStatus.active.dbValue) &
              t.windowEnd.isSmallerThanValue(millis)))
        .write(
      OccurrencesCompanion(status: Value(OccurrenceStatus.expired.dbValue)),
    );
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  SimpleSelectStatement<$RemindersTable, ReminderRow> _orderedReminders() =>
      _db.select(_db.reminders)
        ..orderBy([
          (t) => OrderingTerm.asc(t.startMinutes),
          (t) => OrderingTerm.asc(t.title),
        ]);

  static List<Reminder> _mapAll(List<ReminderRow> rows) =>
      rows.map(_toReminder).toList(growable: false);

  static List<ReminderOccurrence> _mapOccurrences(List<OccurrenceRow> rows) =>
      rows.map(_toOccurrence).toList(growable: false);

  static Reminder _toReminder(ReminderRow row) => Reminder(
        id: row.id,
        title: row.title,
        description: row.description,
        startTime: LocalTime.fromMinutes(row.startMinutes),
        endTime: LocalTime.fromMinutes(row.endMinutes),
        intervalMinutes: row.intervalMinutes,
        days: DaysOfWeek(row.daysOfWeek & 0x7F),
        enabled: row.enabled,
        ringMinutes: row.ringMinutes.clamp(0, 5),
        createdAt: _utc(row.createdAt),
        updatedAt: _utc(row.updatedAt),
      );

  static ReminderOccurrence _toOccurrence(OccurrenceRow row) =>
      ReminderOccurrence(
        id: row.id,
        reminderId: row.reminderId,
        date: LocalDate.parse(row.occurrenceDate),
        status: OccurrenceStatus.fromDb(row.status),
        windowStart: _utc(row.windowStart),
        windowEnd: _utc(row.windowEnd),
        completedAt: row.completedAt == null ? null : _utc(row.completedAt!),
        notificationCount: row.notificationCount,
        lastNotifiedAt:
            row.lastNotifiedAt == null ? null : _utc(row.lastNotifiedAt!),
      );

  static DateTime _utc(int millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}
