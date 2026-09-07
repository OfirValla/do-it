import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/local_time.dart';
import '../../../shared/time_format.dart';
import '../../../shared/widgets/section_header.dart';
import '../application/reminder_service.dart';
import '../domain/reminder.dart';
import '../domain/weekday.dart';
import 'providers.dart';
import 'widgets/day_selector.dart';
import 'widgets/interval_selector.dart';
import 'widgets/ring_duration_selector.dart';

/// Create or edit a reminder.
class ReminderEditScreen extends ConsumerStatefulWidget {
  const ReminderEditScreen({super.key, this.existing});

  /// When non-null the screen edits this reminder instead of creating one.
  final Reminder? existing;

  @override
  ConsumerState<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends ConsumerState<ReminderEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late LocalTime _start;
  late LocalTime _end;
  late int _intervalMinutes;
  late DaysOfWeek _days;
  late bool _enabled;
  late int _ringMinutes;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _start = existing?.startTime ?? const LocalTime(8, 0);
    _end = existing?.endTime ?? const LocalTime(18, 0);
    _intervalMinutes = existing?.intervalMinutes ??
        ref.read(defaultIntervalProvider).value ??
        30;
    _days = existing?.days ?? DaysOfWeek.everyDay;
    _enabled = existing?.enabled ?? true;
    _ringMinutes = existing?.ringMinutes ??
        ref.read(defaultRingMinutesProvider).value ??
        Reminder.defaultRingMinutes;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  ReminderDraft _draft() => ReminderDraft(
        title: _title.text,
        description: _description.text,
        startTime: _start,
        endTime: _end,
        intervalMinutes: _intervalMinutes,
        days: _days,
        enabled: _enabled,
        ringMinutes: _ringMinutes,
      );

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: start ? 'Start reminding at' : 'Stop reminding at',
    );
    if (picked == null) return;
    setState(() {
      final time = LocalTime(picked.hour, picked.minute);
      if (start) {
        _start = time;
      } else {
        _end = time;
      }
    });
  }

  Future<void> _save() async {
    final draft = _draft();
    final problem = draft.validate();
    if (problem != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _saving = true);
    final service = ref.read(reminderServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await service.create(draft);
      } else {
        await service.update(
          existing.copyWith(
            title: draft.title,
            description: draft.description,
            startTime: draft.startTime,
            endTime: draft.endTime,
            intervalMinutes: draft.intervalMinutes,
            days: draft.days,
            enabled: draft.enabled,
            ringMinutes: draft.ringMinutes,
          ),
        );
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              existing == null ? 'Reminder created. Now do it!' : 'Changes saved.',
            ),
          ),
        );
      navigator.pop(true);
    } on ReminderValidationException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final crossesMidnight = _end.compareTo(_start) <= 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit reminder' : 'New reminder'),
        titleTextStyle: theme.textTheme.titleLarge,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            const SectionHeader('What?', icon: Icons.edit_note_rounded),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              autofocus: !_isEditing,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Take vitamins',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Anything that helps you actually do it',
              ),
            ),
            const SectionHeader(
              'When?',
              icon: Icons.schedule_rounded,
              subtitle: 'Reminders repeat only inside this daily window.',
            ),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Start',
                    value: context.formatLocalTime(_start),
                    onTap: () => _pickTime(start: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    label: 'End',
                    value: context.formatLocalTime(_end),
                    onTap: () => _pickTime(start: false),
                  ),
                ),
              ],
            ),
            if (crossesMidnight && _start != _end)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ends after midnight, on the next day.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SectionHeader(
              'Repeat',
              icon: Icons.repeat_rounded,
              subtitle: 'How often to come back until you mark it done.',
            ),
            IntervalSelector(
              minutes: _intervalMinutes,
              onChanged: (value) => setState(() => _intervalMinutes = value),
            ),
            const SizedBox(height: 20),
            Text('Days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            DaySelector(
              value: _days,
              onChanged: (value) => setState(() => _days = value),
            ),
            const SectionHeader(
              'Alarm',
              icon: Icons.alarm_rounded,
              subtitle: 'Ring like an alarm clock until you tap Done or Stop.',
            ),
            RingDurationSelector(
              minutes: _ringMinutes,
              onChanged: (value) => setState(() => _ringMinutes = value),
            ),
            const SectionHeader('Status', icon: Icons.power_settings_new_rounded),
            SwitchListTile(
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
              title: const Text('Enabled'),
              subtitle: Text(
                _enabled
                    ? 'Do It will remind you on the schedule above.'
                    : 'Saved, but no notifications until you turn it on.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: Icon(_isEditing ? Icons.save_rounded : Icons.bolt_rounded),
              label: Text(_isEditing ? 'Save Changes' : 'Create Reminder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}
