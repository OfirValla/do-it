/// How confident we can be that notifications will actually be delivered.
enum ReliabilityLevel {
  /// Notifications on, exact alarms allowed, battery optimisation off.
  full,

  /// Notifications on, but alarms may be delayed (inexact alarms or battery
  /// optimisation active).
  reduced,

  /// Notifications are blocked: nothing will be shown.
  broken,

  /// Not running on Android: no native engine is available.
  unsupported,
}

/// Snapshot of the Android permission state relevant to reminder delivery.
class PermissionStatusSnapshot {
  const PermissionStatusSnapshot({
    required this.isSupported,
    required this.notificationsEnabled,
    required this.canRequestNotificationPermission,
    required this.exactAlarmsAllowed,
    required this.exactAlarmPermissionRequired,
    required this.ignoringBatteryOptimizations,
    required this.fullScreenIntentAllowed,
    required this.fullScreenIntentPermissionRequired,
    required this.sdkInt,
  });

  const PermissionStatusSnapshot.unsupported()
      : isSupported = false,
        notificationsEnabled = false,
        canRequestNotificationPermission = false,
        exactAlarmsAllowed = false,
        exactAlarmPermissionRequired = false,
        ignoringBatteryOptimizations = false,
        fullScreenIntentAllowed = false,
        fullScreenIntentPermissionRequired = false,
        sdkInt = 0;

  factory PermissionStatusSnapshot.fromMap(Map<Object?, Object?> map) {
    bool flag(String key) => map[key] == true;
    return PermissionStatusSnapshot(
      isSupported: true,
      notificationsEnabled: flag('notificationsEnabled'),
      canRequestNotificationPermission:
          flag('canRequestNotificationPermission'),
      exactAlarmsAllowed: flag('exactAlarmsAllowed'),
      exactAlarmPermissionRequired: flag('exactAlarmPermissionRequired'),
      ignoringBatteryOptimizations: flag('ignoringBatteryOptimizations'),
      fullScreenIntentAllowed: flag('fullScreenIntentAllowed'),
      fullScreenIntentPermissionRequired:
          flag('fullScreenIntentPermissionRequired'),
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    );
  }

  final bool isSupported;

  /// `NotificationManagerCompat.areNotificationsEnabled()`, which is false when
  /// the runtime permission is denied *or* the user turned the app off in
  /// system settings.
  final bool notificationsEnabled;

  /// Android 13+ exposes POST_NOTIFICATIONS as a runtime permission dialog.
  final bool canRequestNotificationPermission;

  /// `AlarmManager.canScheduleExactAlarms()` (always true below Android 12).
  final bool exactAlarmsAllowed;

  /// Whether this Android version gates exact alarms behind a permission.
  final bool exactAlarmPermissionRequired;

  /// `PowerManager.isIgnoringBatteryOptimizations()`.
  final bool ignoringBatteryOptimizations;

  /// Whether a ringing alarm may wake and take over the lock screen
  /// (`NotificationManager.canUseFullScreenIntent()`, Android 14+).
  final bool fullScreenIntentAllowed;

  /// Whether this Android version gates full-screen intents behind a setting.
  final bool fullScreenIntentPermissionRequired;
  final int sdkInt;

  ReliabilityLevel get reliability {
    if (!isSupported) return ReliabilityLevel.unsupported;
    if (!notificationsEnabled) return ReliabilityLevel.broken;
    if (!exactAlarmsAllowed || !ignoringBatteryOptimizations) {
      return ReliabilityLevel.reduced;
    }
    return ReliabilityLevel.full;
  }

  /// True when something needs the user's attention on the home screen.
  bool get needsAttention =>
      isSupported && (!notificationsEnabled || !exactAlarmsAllowed);
}
