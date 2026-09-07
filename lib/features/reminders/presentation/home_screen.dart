import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/permission_banner.dart';
import '../../settings/presentation/settings_screen.dart';
import '../domain/reminder_overview.dart';
import 'providers.dart';
import 'reminder_detail_screen.dart';
import 'reminder_edit_screen.dart';
import 'widgets/reminder_card.dart';

/// "My reminders": every reminder with its live status, plus the big
/// "Add Reminder" call to action.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final overviews = ref.watch(reminderOverviewsProvider);
    final permissions = ref.watch(permissionStatusProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Do It'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ReminderEditScreen()),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Reminder'),
      ),
      body: overviews.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: '$error',
        ),
        data: (items) {
          final activeCount = items.where((o) => o.isActive).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My reminders',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeCount == 0
                          ? "Don't forget it. Get it done."
                          : activeCount == 1
                              ? '1 thing is waiting for you.'
                              : '$activeCount things are waiting for you.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (permissions != null && permissions.needsAttention)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: PermissionBanner(
                    status: permissions,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ),
              if (items.isEmpty)
                EmptyState(
                  icon: Icons.notifications_active_outlined,
                  title: 'Nothing to do yet',
                  message:
                      'Add a reminder and Do It will keep nudging you until '
                      "it's done.",
                )
              else
                for (final overview in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReminderTile(overview: overview),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.overview});

  final ReminderOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(reminderServiceProvider);
    final id = overview.reminder.id;
    return ReminderCard(
      overview: overview,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReminderDetailScreen(reminderId: id),
        ),
      ),
      onToggle: (enabled) => service.setEnabled(id, enabled),
      onDone: () async {
        final messenger = ScaffoldMessenger.of(context);
        await service.markDone(id);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('${overview.reminder.title} — done!')),
          );
      },
    );
  }
}
