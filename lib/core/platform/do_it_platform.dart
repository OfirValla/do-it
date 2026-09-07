import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../notifications/permission_status.dart';

/// The single platform channel between Flutter and the native Android engine.
///
/// Method names and payloads are mirrored by `EngineChannel.kt`. Nothing else
/// in the Flutter code base is allowed to talk to Android directly; feature
/// code depends on the higher-level abstractions ([ReminderScheduler],
/// [NotificationPermissionService]) which are implemented on top of this.
abstract class DoItPlatform {
  /// Picks the real channel implementation on Android and a no-op fallback
  /// elsewhere so the UI can still be developed on desktop/web.
  factory DoItPlatform.forCurrentPlatform() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return MethodChannelDoItPlatform();
    }
    return const UnsupportedDoItPlatform();
  }

  bool get isSupported;

  /// Absolute path of the SQLite file shared with the native engine.
  Future<String?> getDatabasePath();

  /// IANA identifier of the device timezone, e.g. `Europe/Berlin`.
  Future<String?> getLocalTimeZoneName();

  Future<void> scheduleReminder(int reminderId);
  Future<void> cancelReminder(int reminderId);
  Future<void> rescheduleAll();

  /// Silences a ringing alarm without completing the reminder.
  Future<void> stopRinging(int reminderId);

  /// The reminder whose alarm is ringing right now, if any.
  Future<int?> getRingingReminderId();

  Future<PermissionStatusSnapshot> getPermissionStatus();

  /// Shows the Android 13+ runtime permission dialog. Resolves to whether
  /// notifications are enabled afterwards.
  Future<bool> requestNotificationPermission();

  Future<void> openNotificationSettings();
  Future<void> openNotificationChannelSettings();
  Future<void> openExactAlarmSettings();
  Future<void> openBatteryOptimizationSettings();
  Future<void> openFullScreenIntentSettings();

  /// Rings a sample alarm through the exact code path real reminders use, so
  /// the user can verify their device setup.
  Future<void> showTestNotification();

  /// If the app was launched by tapping a reminder notification, returns that
  /// reminder's id once and clears it.
  Future<int?> consumeLaunchReminderId();

  /// Fires whenever native code modified the shared database (an alarm fired,
  /// the user tapped Done on a notification, a boot reschedule ran).
  Stream<void> get dataChanges;

  /// Fires when a notification is tapped while the app is already running.
  Stream<int> get openReminderRequests;

  /// Emits the ringing reminder id when an alarm starts, and null when it stops.
  Stream<int?> get ringingChanges;
}

class MethodChannelDoItPlatform implements DoItPlatform {
  MethodChannelDoItPlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String channelName = 'com.doit.app/engine';

  final MethodChannel _channel;
  final StreamController<void> _dataChanges = StreamController.broadcast();
  final StreamController<int> _openRequests = StreamController.broadcast();
  final StreamController<int?> _ringing = StreamController.broadcast();

  @override
  bool get isSupported => true;

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onDataChanged':
        _dataChanges.add(null);
      case 'onOpenReminder':
        final id = call.arguments;
        if (id is int) _openRequests.add(id);
      case 'onRingingChanged':
        final id = call.arguments;
        _ringing.add(id is int ? id : null);
      default:
        throw MissingPluginException('Unknown native call ${call.method}');
    }
    return null;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      debugPrint('DoItPlatform: $method is not available on this platform');
      return null;
    } on PlatformException catch (e) {
      debugPrint('DoItPlatform: $method failed: ${e.code} ${e.message}');
      return null;
    }
  }

  @override
  Future<String?> getDatabasePath() => _invoke<String>('getDatabasePath');

  @override
  Future<String?> getLocalTimeZoneName() =>
      _invoke<String>('getLocalTimeZone');

  @override
  Future<void> scheduleReminder(int reminderId) =>
      _invoke<void>('scheduleReminder', {'reminderId': reminderId});

  @override
  Future<void> cancelReminder(int reminderId) =>
      _invoke<void>('cancelReminder', {'reminderId': reminderId});

  @override
  Future<void> rescheduleAll() => _invoke<void>('rescheduleAll');

  @override
  Future<void> stopRinging(int reminderId) =>
      _invoke<void>('stopRinging', {'reminderId': reminderId});

  @override
  Future<int?> getRingingReminderId() => _invoke<int>('getRingingReminderId');

  @override
  Future<PermissionStatusSnapshot> getPermissionStatus() async {
    final map = await _invoke<Map<Object?, Object?>>('getPermissionStatus');
    if (map == null) return const PermissionStatusSnapshot.unsupported();
    return PermissionStatusSnapshot.fromMap(map);
  }

  @override
  Future<bool> requestNotificationPermission() async =>
      await _invoke<bool>('requestNotificationPermission') ?? false;

  @override
  Future<void> openNotificationSettings() =>
      _invoke<void>('openNotificationSettings');

  @override
  Future<void> openNotificationChannelSettings() =>
      _invoke<void>('openNotificationChannelSettings');

  @override
  Future<void> openExactAlarmSettings() =>
      _invoke<void>('openExactAlarmSettings');

  @override
  Future<void> openBatteryOptimizationSettings() =>
      _invoke<void>('openBatteryOptimizationSettings');

  @override
  Future<void> openFullScreenIntentSettings() =>
      _invoke<void>('openFullScreenIntentSettings');

  @override
  Future<void> showTestNotification() => _invoke<void>('showTestNotification');

  @override
  Future<int?> consumeLaunchReminderId() =>
      _invoke<int>('consumeLaunchReminderId');

  @override
  Stream<void> get dataChanges => _dataChanges.stream;

  @override
  Stream<int> get openReminderRequests => _openRequests.stream;

  @override
  Stream<int?> get ringingChanges => _ringing.stream;
}

/// Used on platforms without the Kotlin engine.
class UnsupportedDoItPlatform implements DoItPlatform {
  const UnsupportedDoItPlatform();

  @override
  bool get isSupported => false;

  @override
  Future<String?> getDatabasePath() async => null;

  @override
  Future<String?> getLocalTimeZoneName() async => null;

  @override
  Future<void> scheduleReminder(int reminderId) async {}

  @override
  Future<void> cancelReminder(int reminderId) async {}

  @override
  Future<void> rescheduleAll() async {}

  @override
  Future<void> stopRinging(int reminderId) async {}

  @override
  Future<int?> getRingingReminderId() async => null;

  @override
  Future<PermissionStatusSnapshot> getPermissionStatus() async =>
      const PermissionStatusSnapshot.unsupported();

  @override
  Future<bool> requestNotificationPermission() async => false;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openNotificationChannelSettings() async {}

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openBatteryOptimizationSettings() async {}

  @override
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<void> showTestNotification() async {}

  @override
  Future<int?> consumeLaunchReminderId() async => null;

  @override
  Stream<void> get dataChanges => const Stream.empty();

  @override
  Stream<int> get openReminderRequests => const Stream.empty();

  @override
  Stream<int?> get ringingChanges => const Stream.empty();
}
