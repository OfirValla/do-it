import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/formatters.dart';

/// Preset interval chips plus a "Custom…" option.
class IntervalSelector extends StatelessWidget {
  const IntervalSelector({
    super.key,
    required this.minutes,
    required this.onChanged,
  });

  static const List<int> presets = [5, 10, 15, 30, 60, 120];

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCustom = !presets.contains(minutes);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in presets)
          ChoiceChip(
            label: Text(Formatters.intervalShort(preset)),
            selected: minutes == preset,
            onSelected: (_) => onChanged(preset),
          ),
        ChoiceChip(
          avatar: Icon(
            Icons.tune_rounded,
            size: 18,
            color: isCustom
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          label: Text(
            isCustom ? 'Custom · ${Formatters.intervalShort(minutes)}' : 'Custom…',
          ),
          selected: isCustom,
          onSelected: (_) async {
            final result = await showCustomIntervalDialog(context, minutes);
            if (result != null) onChanged(result);
          },
        ),
      ],
    );
  }
}

/// Dialog returning an interval in minutes, or null when cancelled.
Future<int?> showCustomIntervalDialog(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (_) => _CustomIntervalDialog(initialMinutes: current),
  );
}

class _CustomIntervalDialog extends StatefulWidget {
  const _CustomIntervalDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_CustomIntervalDialog> createState() => _CustomIntervalDialogState();
}

class _CustomIntervalDialogState extends State<_CustomIntervalDialog> {
  late final TextEditingController _controller;
  bool _hours = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMinutes;
    _hours = initial >= 60 && initial % 60 == 0;
    _controller = TextEditingController(
      text: (_hours ? initial ~/ 60 : initial).toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1) {
      setState(() => _error = 'Enter a number greater than 0');
      return;
    }
    final minutes = _hours ? value * 60 : value;
    if (minutes > 24 * 60) {
      setState(() => _error = 'Keep it within 24 hours');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom interval'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Remind me every',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Minutes')),
              ButtonSegment(value: true, label: Text('Hours')),
            ],
            selected: {_hours},
            onSelectionChanged: (selection) =>
                setState(() => _hours = selection.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Use interval')),
      ],
    );
  }
}
