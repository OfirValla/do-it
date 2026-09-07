import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/reminders/presentation/home_screen.dart';
import 'features/reminders/presentation/providers.dart';
import 'features/reminders/presentation/reminder_detail_screen.dart';
import 'shared/theme/app_theme.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Root widget. Besides the MaterialApp it wires the process-level glue:
///  * native -> Flutter events (database changed, notification tapped),
///  * lifecycle: refresh streams and permission state on resume,
///  * start-up housekeeping: expire stale occurrences, re-anchor all alarms.
class DoItApp extends ConsumerStatefulWidget {
  const DoItApp({super.key});

  @override
  ConsumerState<DoItApp> createState() => _DoItAppState();
}

class _DoItAppState extends ConsumerState<DoItApp> with WidgetsBindingObserver {
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final platform = ref.read(platformProvider);
    _subscriptions.add(platform.dataChanges.listen((_) => _refreshFromNative()));
    _subscriptions.add(platform.openReminderRequests.listen(_openReminder));

    WidgetsBinding.instance.addPostFrameCallback((_) => _onStarted());
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onStarted() async {
    final service = ref.read(reminderServiceProvider);
    await service.expireStaleOccurrences();
    // Re-anchoring is cheap (one alarm per reminder) and heals alarms lost to
    // a force stop or a cleared app state.
    unawaited(service.rescheduleAll());

    final launchId = await ref.read(platformProvider).consumeLaunchReminderId();
    if (launchId != null) _openReminder(launchId);
  }

  Future<void> _onResumed() async {
    _refreshFromNative();
    ref.invalidate(permissionStatusProvider);
    ref.invalidate(ringingReminderProvider);
    ref.invalidate(tickerProvider);
    await ref.read(reminderServiceProvider).expireStaleOccurrences();
  }

  /// The Kotlin engine wrote to the database behind Drift's back; poke every
  /// open stream so the UI reflects the new state.
  void _refreshFromNative() {
    ref.read(appDatabaseProvider).notifyExternalChange();
  }

  void _openReminder(int reminderId) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ReminderDetailScreen(reminderId: reminderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Do It',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en')],
      home: const HomeScreen(),
    );
  }
}
