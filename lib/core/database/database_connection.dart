import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../platform/do_it_platform.dart';

/// File name of the shared database. Mirrored by `DoItDatabase.kt`.
const String databaseFileName = 'do_it.sqlite';

/// Resolves where the database lives.
///
/// On Android the *native* side owns the location (`Context.filesDir`), so we
/// ask it, guaranteeing both runtimes open the same file. Elsewhere fall back
/// to the platform's application-support directory.
Future<String> resolveDatabasePath(DoItPlatform platform) async {
  final nativePath = await platform.getDatabasePath();
  if (nativePath != null && nativePath.isNotEmpty) return nativePath;
  final directory = await getApplicationSupportDirectory();
  return p.join(directory.path, databaseFileName);
}

/// Opens the database on a background isolate.
QueryExecutor openDatabaseConnection(String path) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  return NativeDatabase.createInBackground(file, setup: configureSqlite);
}

/// Per-connection SQLite settings. Runs inside the database isolate, so it
/// must remain a top-level function without captured state.
///
/// WAL mode allows the Kotlin engine (a second connection to the same file,
/// possibly at the same time) to read while Drift writes and vice versa. The
/// busy timeout makes the rare lock collision wait instead of failing.
void configureSqlite(Database database) {
  database.execute('PRAGMA journal_mode = WAL;');
  database.execute('PRAGMA busy_timeout = 5000;');
  database.execute('PRAGMA synchronous = NORMAL;');
}
