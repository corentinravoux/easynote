import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'theme.dart';

/// Sync state in a few words; tapping it syncs, or opens Settings when the
/// token was refused.
class SyncBadge extends StatelessWidget {
  final SyncStatus status;
  final VoidCallback onSync;
  final VoidCallback onSettings;
  final bool compact;

  const SyncBadge({
    super.key,
    required this.status,
    required this.onSync,
    required this.onSettings,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = status.pending;
    final (IconData icon, String label, Color color) = switch (status.phase) {
      SyncPhase.localOnly => (Icons.cloud_off_outlined, 'Local only', p.muted),
      SyncPhase.idle => (Icons.cloud_outlined, 'Not synced yet', p.muted),
      SyncPhase.syncing => (Icons.sync, 'Syncing', p.muted),
      SyncPhase.synced => (Icons.cloud_done_outlined, status.message ?? 'Synced', status.message == null ? p.muted : p.accent),
      SyncPhase.pending => (Icons.cloud_upload_outlined, '$n unsynced', p.ink),
      SyncPhase.offline => (Icons.cloud_off_outlined, n > 0 ? 'Offline, $n unsynced' : 'Offline', p.ink),
      SyncPhase.authError => (Icons.key_off_outlined, 'Token refused', p.accent),
      SyncPhase.error => (Icons.error_outline, status.message ?? 'Sync failed', p.accent),
    };
    final tooltip = switch (status.phase) {
      SyncPhase.authError => 'GitHub refused the token. Update it in Settings.',
      SyncPhase.localOnly => 'Add a GitHub repo in Settings to sync.',
      _ => status.message ?? 'Sync now',
    };
    final onTap = status.phase == SyncPhase.authError || status.phase == SyncPhase.localOnly
        ? onSettings
        : onSync;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: status.phase == SyncPhase.syncing ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: color),
            if (!compact) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontSize: 13, color: color)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
