import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/local_date.dart';
import '../../../shared/time_format.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_header.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/weekday_strip.dart';
import '../domain/reminder_occurrence.dart';
import '../domain/reminder_overview.dart';
import 'providers.dart';
import 'reminder_edit_screen.dart';

/// Status, schedule and completion history of one reminder.
class ReminderDetailScreen extends ConsumerWidget {
  const ReminderDetailScreen({super.key, required this.reminderId});

  final int reminderId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: const Text(
          'Its schedule and completion history will be removed. '
          'Pending notifications are cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(reminderServiceProvider).delete(reminderId);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(reminderOverviewProvider(reminderId));
    final history = ref.watch(occurrenceHistoryProvider(reminderId)).value ??
        const <ReminderOccurrence>[];

    return overview.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load reminder',
          message: '$error',
        ),
      ),
      data: (data) {
        if (data == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'This reminder is gone',
              message: 'It was deleted.',
            ),
          );
        }
        return _DetailBody(
          overview: data,
          history: history,
          onDelete: () => _confirmDelete(context, ref),
        );
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.overview,
    required this.history,
    required this.onDelete,
  });

  final ReminderOverview overview;
  final List<ReminderOccurrence> history;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reminder = overview.reminder;
    final calculator = ref.watch(scheduleCalculatorProvider);
    final today = ref.watch(todayProvider);
    final service = ref.read(reminderServiceProvider);
    final ringing = ref.watch(ringingReminderProvider).value == reminder.id;

    final nextLabel = overview.nextFireAt == null
        ? null
        : context.formatNextFire(calculator.toLocal(overview.nextFireAt!), today);

    return Scaffold(
      appBar: AppBar(
        title: Text(reminder.title),
        titleTextStyle: theme.textTheme.titleLarge,
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReminderEditScreen(existing: reminder),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: onDelete,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _StatusCard(
            overview: overview,
            nextLabel: nextLabel,
            ringing: ringing,
            onStopRinging: () => service.stopRinging(reminder.id),
            onDone: () async {
              final messenger = ScaffoldMessenger.of(context);
              await service.markDone(reminder.id);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Done. Nice.')));
            },
            onToggle: (enabled) => service.setEnabled(reminder.id, enabled),
          ),
          if (reminder.hasDescription) ...[
            const SizedBox(height: 16),
            Text(reminder.description, style: theme.textTheme.bodyLarge),
          ],
          const SectionHeader('Schedule', icon: Icons.schedule_rounded),
          _FactTile(
            icon: Icons.hourglass_bottom_rounded,
            label: 'Window',
            value: context.formatTimeRange(reminder.startTime, reminder.endTime),
            hint: reminder.rule.crossesMidnight ? 'ends the next day' : null,
          ),
          _FactTile(
            icon: Icons.repeat_rounded,
            label: 'Repeat',
            value: Formatters.interval(reminder.intervalMinutes),
            hint: 'until you mark it done',
          ),
          _FactTile(
            icon: Icons.alarm_rounded,
            label: 'Alarm',
            value: Formatters.ringDurationShort(reminder.ringMinutes),
            hint: Formatters.ringDuration(reminder.ringMinutes),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.calendar_month_rounded, color: scheme.primary),
            title: const Text('Days'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: WeekdayStrip(reminder.days, compact: false),
            ),
            trailing: Text(
              reminder.days.label,
              style: theme.textTheme.labelLarge,
            ),
          ),
          SectionHeader(
            'History',
            icon: Icons.history_rounded,
            subtitle: history.isEmpty
                ? 'No occurrences yet.'
                : '${history.where((o) => o.isCompleted).length} of '
                    '${history.length} completed',
          ),
          for (final occurrence in history)
            _HistoryTile(occurrence: occurrence, today: today),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.overview,
    required this.nextLabel,
    required this.ringing,
    required this.onStopRinging,
    required this.onDone,
    required this.onToggle,
  });

  final ReminderOverview overview;
  final String? nextLabel;
  final bool ringing;
  final VoidCallback onStopRinging;
  final VoidCallback onDone;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = overview.isActive;

    final (badgeLabel, badgeBg, badgeFg, icon) = switch (overview.state) {
      ReminderState.active => (
          'Active',
          scheme.primary,
          scheme.onPrimary,
          Icons.notifications_active_rounded,
        ),
      ReminderState.completedToday => (
          'Done for today',
          scheme.tertiary,
          scheme.onTertiary,
          Icons.check_circle_rounded,
        ),
      ReminderState.idle => (
          'Scheduled',
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.schedule_rounded,
        ),
      ReminderState.disabled => (
          'Paused',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.pause_circle_outline_rounded,
        ),
    };

    final headline = switch (overview.state) {
      ReminderState.active => nextLabel == null
          ? 'Waiting for you'
          : 'Next reminder $nextLabel',
      ReminderState.completedToday =>
        nextLabel == null ? 'See you next time' : 'Next: $nextLabel',
      ReminderState.idle =>
        nextLabel == null ? 'No days selected' : 'Next: $nextLabel',
      ReminderState.disabled => 'Turn it on to get reminded',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(
                label: badgeLabel,
                background: badgeBg,
                foreground: badgeFg,
                icon: icon,
              ),
              const Spacer(),
              Switch(value: overview.reminder.enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: active ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
          if (active) ...[
            const SizedBox(height: 6),
            Text(
              overview.currentOccurrence == null ||
                      overview.currentOccurrence!.notificationCount == 0
                  ? "You haven't completed this yet."
                  : "You haven't completed this yet · "
                      '${overview.currentOccurrence!.notificationCount} '
                      'reminder${overview.currentOccurrence!.notificationCount == 1 ? '' : 's'} sent',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            if (ringing) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ringing now',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onStopRinging,
                      icon: const Icon(Icons.notifications_off_rounded),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Mark as Done'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      subtitle: hint == null ? null : Text(hint!),
      trailing: Text(value, style: theme.textTheme.titleMedium),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.occurrence, required this.today});

  final ReminderOccurrence occurrence;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final calculator = ref.watch(scheduleCalculatorProvider);
    final count = occurrence.notificationCount;
    final sent = count == 0
        ? 'no notifications'
        : '$count notification${count == 1 ? '' : 's'}';

    final (icon, color, status) = switch (occurrence.status) {
      OccurrenceStatus.completed => (
          Icons.check_circle_rounded,
          scheme.tertiary,
          occurrence.completedAt == null
              ? 'Completed'
              : 'Completed at '
                  '${context.formatLocalDateTime(calculator.toLocal(occurrence.completedAt!))}',
        ),
      OccurrenceStatus.expired => (
          Icons.cancel_rounded,
          scheme.error,
          'Not done',
        ),
      OccurrenceStatus.active => (
          Icons.notifications_active_rounded,
          scheme.primary,
          'In progress',
        ),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(Formatters.historyDate(occurrence.date)),
      subtitle: Text('$status · $sent'),
      trailing: Text(
        Formatters.relativeDay(occurrence.date, today),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
