import 'package:do_it/core/database/app_database.dart';
import 'package:drift/native.dart';

/// In-memory Drift database for tests. Uses the same schema and migration
/// strategy as production.
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());
