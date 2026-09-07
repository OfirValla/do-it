import 'package:flutter/material.dart';

import '../../features/reminders/domain/weekday.dart';

/// Read-only Mon..Sun strip highlighting the selected days.
class WeekdayStrip extends StatelessWidget {
  const WeekdayStrip(this.days, {super.key, this.compact = true});

  final DaysOfWeek days;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final day in Weekday.values)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: compact ? 28 : 36,
              height: compact ? 22 : 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: days.contains(day)
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                compact ? day.shortLabel.substring(0, 1) : day.shortLabel,
                style: style?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: days.contains(day)
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
