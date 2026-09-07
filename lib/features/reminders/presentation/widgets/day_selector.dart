import 'package:flutter/material.dart';

import '../../domain/weekday.dart';

/// Weekday picker with "Every day / Weekdays / Weekends" shortcuts.
class DaySelector extends StatelessWidget {
  const DaySelector({super.key, required this.value, required this.onChanged});

  final DaysOfWeek value;
  final ValueChanged<DaysOfWeek> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Shortcut('Every day', DaysOfWeek.everyDay, value, onChanged),
            _Shortcut('Weekdays', DaysOfWeek.weekdays, value, onChanged),
            _Shortcut('Weekends', DaysOfWeek.weekends, value, onChanged),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final day in Weekday.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _DayToggle(
                    day: day,
                    selected: value.contains(day),
                    onTap: () => onChanged(value.toggle(day)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.label, this.preset, this.current, this.onChanged);

  final String label;
  final DaysOfWeek preset;
  final DaysOfWeek current;
  final ValueChanged<DaysOfWeek> onChanged;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: current == preset,
      onSelected: (_) => onChanged(preset),
    );
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final Weekday day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: day.longLabel,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                day.shortLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
