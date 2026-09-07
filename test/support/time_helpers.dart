import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _loaded = false;

/// Loads the bundled timezone database once per test process.
tz.Location location(String name) {
  if (!_loaded) {
    tzdata.initializeTimeZones();
    _loaded = true;
  }
  return tz.getLocation(name);
}

/// A wall-clock time in [zone] as a UTC instant.
DateTime at(tz.Location zone, int y, int m, int d, int h, int min) =>
    DateTime.fromMillisecondsSinceEpoch(
      tz.TZDateTime(zone, y, m, d, h, min).millisecondsSinceEpoch,
      isUtc: true,
    );

DateTime utc(int y, int m, int d, int h, int min) =>
    DateTime.utc(y, m, d, h, min);
