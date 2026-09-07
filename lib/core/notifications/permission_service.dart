import '../platform/do_it_platform.dart';
import 'permission_status.dart';

/// Reads and requests the permissions that reminder delivery depends on.
///
/// Everything is optional: the app never crashes when something is denied, it
/// only shows the reduced reliability in Settings and on the home screen.
abstract class NotificationPermissionService {
  Future<PermissionStatusSnapshot> status();

  /// Android 13+: shows the POST_NOTIFICATIONS dialog. Older versions and
  /// permanently denied states resolve to the current enabled flag.
  Future<bool> requestNotificationPermission();

  /// Opens the app's notification settings page.
  Future<void> openNotificationSettings();

  /// Opens the sound/vibration settings of the reminder notification channel.
  Future<void> openNotificationChannelSettings();

  /// Android 12+: opens the "Alarms & reminders" special access page.
  Future<void> openExactAlarmSettings();

  /// Opens the battery optimisation list so the user can exempt the app.
  Future<void> openBatteryOptimizationSettings();

  /// Android 14+: opens the full-screen notification special access page.
  Future<void> openFullScreenIntentSettings();

  /// Rings a sample alarm through the native engine.
  Future<void> showTestNotification();
}

class PlatformNotificationPermissionService
    implements NotificationPermissionService {
  PlatformNotificationPermissionService(this._platform);

  final DoItPlatform _platform;

  @override
  Future<PermissionStatusSnapshot> status() => _platform.getPermissionStatus();

  @override
  Future<bool> requestNotificationPermission() =>
      _platform.requestNotificationPermission();

  @override
  Future<void> openNotificationSettings() =>
      _platform.openNotificationSettings();

  @override
  Future<void> openNotificationChannelSettings() =>
      _platform.openNotificationChannelSettings();

  @override
  Future<void> openExactAlarmSettings() => _platform.openExactAlarmSettings();

  @override
  Future<void> openBatteryOptimizationSettings() =>
      _platform.openBatteryOptimizationSettings();

  @override
  Future<void> openFullScreenIntentSettings() =>
      _platform.openFullScreenIntentSettings();

  @override
  Future<void> showTestNotification() => _platform.showTestNotification();
}
