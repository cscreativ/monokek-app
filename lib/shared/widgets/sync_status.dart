import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/sse/notifications_service.dart';
import 'pulse.dart';

/// Header pill showing whether the live event stream is connected (replaces Tauri's simulated SyncStatus:
/// this one reflects the real SSE connection, so staff know when tables/tickets may be stale).
class SyncStatus extends ConsumerWidget {
  const SyncStatus({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(sseConnectedProvider).value ?? false;
    final color = online ? const Color(0xFF059669) : const Color(0xFFD97706);
    final pill = Tooltip(
      message: online ? 'Synchronisation en temps réel active' : 'Reconnexion au serveur…',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(online ? LucideIcons.wifi : LucideIcons.wifiOff, size: 14, color: color),
          if (!compact) ...[
            const SizedBox(width: 6),
            Text(online ? 'EN LIGNE' : 'HORS LIGNE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: color)),
          ],
        ]),
      ),
    );
    return online ? pill : Pulse(child: pill);
  }
}
