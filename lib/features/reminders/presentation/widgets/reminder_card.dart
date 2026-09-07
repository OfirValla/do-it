import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/time_format.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../../shared/widgets/weekday_strip.dart';
import '../../domain/reminder_overview.dart';
import '../providers.dart';

/// One reminder on the home screen. Makes an active occurrence unmistakable
/// and lets the user finish it right there.
class ReminderCard extends ConsumerWidget {
  const ReminderCard({
    super.key,
    required this.overview,
    required this.onTap,
    required this.onToggle,
    required this.onDone,
  });

  final ReminderOverview overview;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reminder = overview.reminder;
    final calculator = ref.watch(scheduleCalculatorProvider);
    final today = ref.watch(todayProvider);

    final nextLabel = overview.nextFireAt == null
        ? null
        : context.formatNextFire(calculator.toLocal(overview.nextFireAt!), today);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reminder.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: reminder.enabled
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${Formatters.interval(reminder.intervalMinutes)} · '
                          '${context.formatTimeRange(reminder.startTime, reminder.endTime)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: reminder.enabled, onChanged: onToggle),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    WeekdayStrip(reminder.days),
                    const Spacer(),
                    if (reminder.ringsLikeAlarm) ...[
                      Icon(
                        Icons.alarm_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${Formatters.ringDurationShort(reminder.ringMinutes)} · ',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    Text(
                      reminder.days.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: switch (overview.state) {
                  ReminderState.active => _ActivePanel(
                      nextLabel: nextLabel,
                      onDone: onDone,
                    ),
                  ReminderState.completedToday => _StatusLine(
                      icon: Icons.check_circle_rounded,
                      color: scheme.tertiary,
                      text: nextLabel == null
                          ? 'Done for today'
                          : 'Done for today · Next: $nextLabel',
                    ),
                  ReminderState.idle => _StatusLine(
                      icon: Icons.schedule_rounded,
                      color: scheme.onSurfaceVariant,
                      text: nextLabel == null
                          ? 'No days selected'
                          : 'Next: $nextLabel',
                    ),
                  ReminderState.disabled => _StatusLine(
                      icon: Icons.pause_circle_outline_rounded,
                      color: scheme.onSurfaceVariant,
                      text: 'Paused',
                    ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivePanel extends StatelessWidget {
  const _ActivePanel({required this.nextLabel, required this.onDone});

  final String? nextLabel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(
                  label: 'Active',
                  background: scheme.primary,
                  foreground: scheme.onPrimary,
                  icon: Icons.notifications_active_rounded,
                ),
                const SizedBox(height: 8),
                Text(
                  nextLabel == null
                      ? 'Last reminder for today sent'
                      : 'Next reminder $nextLabel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onDone,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
