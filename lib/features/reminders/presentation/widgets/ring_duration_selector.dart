import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/reminder.dart';

/// Picks how long a reminder rings like an alarm clock: Off or 1..5 minutes.
class RingDurationSelector extends StatelessWidget {
  const RingDurationSelector({
    super.key,
    required this.minutes,
    required this.onChanged,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in Reminder.ringOptions)
          ChoiceChip(
            avatar: option == 0
                ? null
                : Icon(
                    Icons.alarm_rounded,
                    size: 16,
                    color: minutes == option
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
            label: Text(Formatters.ringDurationShort(option)),
            selected: minutes == option,
            onSelected: (_) => onChanged(option),
          ),
      ],
    );
  }
}
