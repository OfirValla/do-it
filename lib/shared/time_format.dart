import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/formatters.dart';
import '../core/utils/local_date.dart';
import '../core/utils/local_time.dart';

/// Locale-aware time formatting that honours the device's 12/24-hour setting.
extension TimeFormatContext on BuildContext {
  String formatLocalTime(LocalTime time) {
    return MaterialLocalizations.of(this).formatTimeOfDay(
      TimeOfDay(hour: time.hour, minute: time.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(this),
    );
  }

  /// "08:00 – 18:00"
  String formatTimeRange(LocalTime start, LocalTime end) =>
      '${formatLocalTime(start)} – ${formatLocalTime(end)}';

  /// "09:30", "Tomorrow 08:00", "Sunday 10:00"
  String formatNextFire(tz.TZDateTime next, LocalDate today) =>
      Formatters.nextFire(next, today, formatLocalTime);

  /// Time part of an instant already converted to the local zone.
  String formatLocalDateTime(tz.TZDateTime local) =>
      formatLocalTime(LocalTime(local.hour, local.minute));
}
