import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Drift database. Also read and written by the Kotlin engine (see
/// `SqliteReminderStore.kt`), so all schema changes must stay backwards
/// compatible with it and ship as a numbered migration below.
@DriftDatabase(tables: [Reminders, Occurrences, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump when the schema changes and add a step to [migration].
  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // One `if (from < N)` block per version. Never drop or rename the
          // columns listed in tables.dart without updating
          // SqliteReminderStore.kt in the same release (it tolerates missing
          // columns added in later versions until the app has migrated).
          if (from < 2) {
            await m.addColumn(reminders, reminders.ringMinutes);
          }
        },
        beforeOpen: (details) async {
          // Foreign keys are per-connection in SQLite.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// The native engine writes to this database outside of Drift, so its
  /// change tracking does not see those writes. Call this to make every open
  /// stream (`watch*` queries) re-run.
  void notifyExternalChange() {
    notifyUpdates({
      TableUpdate.onTable(reminders),
      TableUpdate.onTable(occurrences),
    });
  }
}
