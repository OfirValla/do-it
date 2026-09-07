import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/permission_status.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/section_header.dart';
import '../../reminders/domain/reminder.dart';
import '../../reminders/presentation/providers.dart';
import '../../reminders/presentation/widgets/interval_selector.dart';
import '../../reminders/presentation/widgets/ring_duration_selector.dart';

/// Notification reliability, defaults and about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String appVersion = '1.0.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final permissions = ref.watch(permissionStatusProvider);
    final service = ref.read(permissionServiceProvider);
    final defaultInterval = ref.watch(defaultIntervalProvider).value ?? 30;
    final defaultRing = ref.watch(defaultRingMinutesProvider).value ??
        Reminder.defaultRingMinutes;

    Future<void> refresh() async {
      ref.invalidate(permissionStatusProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        titleTextStyle: theme.textTheme.titleLarge,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          const SectionHeader(
            'Reliability',
            icon: Icons.verified_rounded,
            subtitle: 'Everything Do It needs to reach you on time.',
          ),
          permissions.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text('Could not read permission state: $error'),
            data: (status) => _ReliabilitySection(
              status: status,
              onRequestNotifications: () async {
                await service.requestNotificationPermission();
                await refresh();
              },
              onOpenNotificationSettings: service.openNotificationSettings,
              onOpenExactAlarmSettings: service.openExactAlarmSettings,
              onOpenBatterySettings: service.openBatteryOptimizationSettings,
              onOpenFullScreenSettings: service.openFullScreenIntentSettings,
              onTestNotification: () async {
                await service.showTestNotification();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Test alarm started. It rings for a minute unless you '
                        'tap Done or Stop.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          const SectionHeader('Defaults', icon: Icons.tune_rounded),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.repeat_rounded, color: theme.colorScheme.primary),
            title: const Text('Default repeat interval'),
            subtitle: const Text('Pre-selected when you create a reminder'),
            trailing: Text(
              Formatters.intervalShort(defaultInterval),
              style: theme.textTheme.titleMedium,
            ),
            onTap: () async {
              final picked = await _pickDefaultInterval(context, defaultInterval);
              if (picked != null) {
                await ref
                    .read(settingsRepositoryProvider)
                    .setDefaultIntervalMinutes(picked);
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.alarm_rounded, color: theme.colorScheme.primary),
            title: const Text('Default alarm duration'),
            subtitle: const Text(
              'How long new reminders ring until you tap Done or Stop',
            ),
            trailing: Text(
              Formatters.ringDurationShort(defaultRing),
              style: theme.textTheme.titleMedium,
            ),
            onTap: () async {
              final picked = await _pickDefaultRing(context, defaultRing);
              if (picked != null) {
                await ref
                    .read(settingsRepositoryProvider)
                    .setDefaultRingMinutes(picked);
              }
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.music_note_rounded,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Notification sound & vibration'),
            subtitle: const Text(
              'Managed by Android for the "Reminders" channel',
            ),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: service.openNotificationChannelSettings,
          ),
          const SectionHeader('About', icon: Icons.info_outline_rounded),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Do It', style: theme.textTheme.headlineMedium),
                Text(
                  'Version $appVersion',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Do It won't stop reminding you until it's done.",
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Reminders are scheduled with Android\'s alarm system, so they '
                  'arrive even when the app is closed, the phone is locked, or '
                  'after a reboot. Tap Done on a notification to stop the nagging '
                  'for the day; tomorrow it starts fresh.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<int?> _pickDefaultInterval(BuildContext context, int current) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default repeat interval',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            IntervalSelector(
              minutes: current,
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
            ),
          ],
        ),
      ),
    );
  }

  Future<int?> _pickDefaultRing(BuildContext context, int current) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default alarm duration',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Reminders ring like an alarm clock for this long, or until you '
              'tap Done or Stop. Off shows a normal notification instead.',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            RingDurationSelector(
              minutes: current,
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReliabilitySection extends StatelessWidget {
  const _ReliabilitySection({
    required this.status,
    required this.onRequestNotifications,
    required this.onOpenNotificationSettings,
    required this.onOpenExactAlarmSettings,
    required this.onOpenBatterySettings,
    required this.onOpenFullScreenSettings,
    required this.onTestNotification,
  });

  final PermissionStatusSnapshot status;
  final Future<void> Function() onRequestNotifications;
  final Future<void> Function() onOpenNotificationSettings;
  final Future<void> Function() onOpenExactAlarmSettings;
  final Future<void> Function() onOpenBatterySettings;
  final Future<void> Function() onOpenFullScreenSettings;
  final Future<void> Function() onTestNotification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!status.isSupported) {
      return Text(
        'The native scheduling engine is only available on Android. '
        'On this platform the UI runs without notifications.',
        style: theme.textTheme.bodyMedium,
      );
    }

    final (summaryIcon, summaryColor, summaryText) = switch (status.reliability) {
      ReliabilityLevel.full => (
          Icons.check_circle_rounded,
          scheme.tertiary,
          'All set. Reminders will arrive on time.',
        ),
      ReliabilityLevel.reduced => (
          Icons.warning_amber_rounded,
          scheme.secondary,
          'Reminders work, but may be delayed by the system.',
        ),
      ReliabilityLevel.broken => (
          Icons.error_rounded,
          scheme.error,
          'Reminders cannot be shown right now.',
        ),
      ReliabilityLevel.unsupported => (
          Icons.info_outline_rounded,
          scheme.onSurfaceVariant,
          'Not available on this platform.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(summaryIcon, color: summaryColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(summaryText, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _PermissionTile(
          ok: status.notificationsEnabled,
          title: 'Notifications',
          okText: 'Enabled',
          problemText: 'Disabled. Do It cannot show reminders.',
          actionLabel: status.canRequestNotificationPermission
              ? 'Allow'
              : 'Open settings',
          onAction: status.canRequestNotificationPermission
              ? onRequestNotifications
              : onOpenNotificationSettings,
          secondaryLabel:
              status.canRequestNotificationPermission ? 'Settings' : null,
          onSecondary: onOpenNotificationSettings,
        ),
        _PermissionTile(
          ok: status.exactAlarmsAllowed,
          title: 'Exact alarms',
          okText: status.exactAlarmPermissionRequired
              ? 'Allowed. Reminders fire at the exact minute.'
              : 'Not needed on this Android version.',
          problemText:
              'Not allowed. Android may delay reminders by several minutes.',
          actionLabel: 'Allow',
          onAction: status.exactAlarmPermissionRequired
              ? onOpenExactAlarmSettings
              : null,
        ),
        _PermissionTile(
          ok: status.ignoringBatteryOptimizations,
          title: 'Battery optimisation',
          okText: 'Unrestricted. Background delivery is not throttled.',
          problemText:
              'Optimised. Some manufacturers delay or drop alarms for '
              'optimised apps. Choose "Don\'t optimise" for Do It.',
          actionLabel: 'Open settings',
          onAction: onOpenBatterySettings,
          warnOnly: true,
        ),
        if (status.fullScreenIntentPermissionRequired)
          _PermissionTile(
            ok: status.fullScreenIntentAllowed,
            title: 'Full-screen alarm',
            okText: 'Allowed. Ringing reminders wake the screen like an alarm clock.',
            problemText:
                'Not allowed. Ringing reminders show as a banner instead of '
                'waking the screen.',
            actionLabel: 'Allow',
            onAction: onOpenFullScreenSettings,
            warnOnly: true,
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onTestNotification,
          icon: const Icon(Icons.alarm_on_rounded),
          label: const Text('Test alarm (rings for 1 minute)'),
        ),
      ],
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.ok,
    required this.title,
    required this.okText,
    required this.problemText,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.warnOnly = false,
  });

  final bool ok;
  final String title;
  final String okText;
  final String problemText;
  final String actionLabel;
  final Future<void> Function()? onAction;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;

  /// Battery optimisation is a recommendation, not a blocker.
  final bool warnOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = ok
        ? scheme.tertiary
        : warnOnly
            ? scheme.secondary
            : scheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok
            ? Icons.check_circle_rounded
            : warnOnly
                ? Icons.warning_amber_rounded
                : Icons.error_rounded,
        color: color,
      ),
      title: Text(title),
      subtitle: Text(ok ? okText : problemText),
      isThreeLine: !ok,
      trailing: ok || onAction == null
          ? null
          : Wrap(
              spacing: 4,
              children: [
                if (secondaryLabel != null && onSecondary != null)
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ],
            ),
    );
  }
}
