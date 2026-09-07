import '../../../core/database/app_database.dart';

/// User preferences persisted in the `settings` key/value table.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const String _defaultIntervalKey = 'default_interval_minutes';
  static const int defaultIntervalFallback = 30;

  Stream<int> watchDefaultIntervalMinutes() => _watch(_defaultIntervalKey)
      .map((value) => int.tryParse(value ?? '') ?? defaultIntervalFallback);

  Future<int> getDefaultIntervalMinutes() async =>
      int.tryParse(await _get(_defaultIntervalKey) ?? '') ??
      defaultIntervalFallback;

  Future<void> setDefaultIntervalMinutes(int minutes) =>
      _set(_defaultIntervalKey, minutes.toString());

  static const String _defaultRingKey = 'default_ring_minutes';
  static const int defaultRingFallback = 2;

  Stream<int> watchDefaultRingMinutes() => _watch(_defaultRingKey)
      .map((value) => int.tryParse(value ?? '') ?? defaultRingFallback);

  Future<int> getDefaultRingMinutes() async =>
      int.tryParse(await _get(_defaultRingKey) ?? '') ?? defaultRingFallback;

  Future<void> setDefaultRingMinutes(int minutes) =>
      _set(_defaultRingKey, minutes.toString());

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.settings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> _watch(String key) =>
      (_db.select(_db.settings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<void> _set(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
