import 'package:flutter/material.dart';

import '../../core/notifications/permission_status.dart';

/// Home-screen warning shown while notifications cannot be delivered
/// reliably. Tapping it opens Settings where the problem can be fixed.
class PermissionBanner extends StatelessWidget {
  const PermissionBanner({super.key, required this.status, required this.onTap});

  final PermissionStatusSnapshot status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final broken = !status.notificationsEnabled;
    // Secondary (amber) is the app's "needs attention" role.
    final background =
        broken ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground =
        broken ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    final title = broken
        ? 'Notifications are off'
        : 'Exact alarms are not allowed';
    final message = broken
        ? 'Do It cannot remind you until notifications are enabled.'
        : 'Reminders may arrive a few minutes late. Tap to fix.';

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                broken ? Icons.notifications_off_rounded : Icons.timer_off_rounded,
                color: foreground,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: foreground),
                    ),
                    Text(
                      message,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
