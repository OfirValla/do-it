import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../platform/do_it_platform.dart';

/// Initialises the `timezone` database and resolves the device's location.
///
/// The Kotlin engine schedules with `ZoneId.systemDefault()`; the Dart side
/// must use the same zone so that predicted times ("Next: 09:30") match what
/// Android actually fires. The IANA name therefore comes from the platform.
class TimeZoneService {
  TimeZoneService._();

  static bool _initialised = false;

  static Future<tz.Location> initialize(DoItPlatform platform) async {
    ensureDatabaseLoaded();
    final name = await platform.getLocalTimeZoneName();
    final location = resolveLocation(name, DateTime.now());
    tz.setLocalLocation(location);
    return location;
  }

  static void ensureDatabaseLoaded() {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    _initialised = true;
  }

  /// Picks the location for [name]; if it is unknown to the bundled database
  /// (some vendors report non-IANA ids), falls back to any location with the
  /// same current UTC offset as the Dart runtime, and finally to UTC.
  @visibleForTesting
  static tz.Location resolveLocation(String? name, DateTime now) {
    if (name != null && name.isNotEmpty) {
      try {
        return tz.getLocation(name);
      } on tz.LocationNotFoundException {
        debugPrint('TimeZoneService: unknown zone "$name", using fallback');
      }
    }
    final offset = now.timeZoneOffset;
    final millis = now.millisecondsSinceEpoch;
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.timeZone(millis).offset == offset) return location;
    }
    return tz.UTC;
  }
}
