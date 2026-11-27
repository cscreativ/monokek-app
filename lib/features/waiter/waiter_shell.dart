import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/roles.dart';
import '../auth/auth_controller.dart';
import '../auth/lock_overlay.dart';
import '../../shared/widgets/printer_status.dart';
import '../../shared/widgets/sync_status.dart';
import 'security_dialog.dart';
import 'waiter_alerts.dart';

/// Top bar + Tables / Commandes tabs around the waiter screens (port of pos/tables/layout.tsx).
typedef ShellTab = (String label, IconData icon, String route);

const waiterTabs = <ShellTab>[
  ('Tables', LucideIcons.table, '/pos/tables'),
  ('Commandes', LucideIcons.history, '/pos/tables/history'),
];

const cashierTabs = <ShellTab>[
  ('Vente', LucideIcons.layoutGrid, '/pos/sales/order'),
  ('Tables', LucideIcons.table2, '/pos/sales/tables'),
  ('Comptoir Bar', LucideIcons.beer, '/pos/sales/comptoir'),
  ('Historiques', LucideIcons.history, '/pos/sales/history'),
];

/// Top bar + tabs around the waiter / cashier screens (port of pos/tables/layout.tsx and pos/sales/layout.tsx).
/// The cashier variant shows the assigned register's name and a logout button.
class WaiterShell extends ConsumerWidget {
  const WaiterShell({super.key, required this.child, this.tabs = waiterTabs, this.registerName, this.showLogout = false, this.alerts = false});
  final Widget child;
  final List<ShellTab> tabs;
  final String? registerName;
  final bool showLogout;

  /// The waiter variant rings for the waiter's own orders (ready, late, paid, cancelled).
  final bool alerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(authProvider).user;
    final role = roleThemes[user?.role];
    final width = MediaQuery.sizeOf(context).width;
    // Phone: secondary actions fold into a menu. Tab labels only when they actually fit.
    final compact = width < 720;
    final tabLabels = width >= (tabs.length > 2 ? 1180 : 640);
    final actionLabels = width >= 1000;

    Widget tab(String label, IconData icon, String route) {
      final on = location == route;
      return Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(route),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: tabLabels ? 12 : 10, vertical: 7),
            decoration: BoxDecoration(
              color: on ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: on ? scheme.primary : scheme.onSurfaceVariant),
              if (tabLabels) ...[
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? scheme.primary : scheme.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
      );
    }

    Widget pillButton(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: fg),
              if (actionLabels) ...[
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
              ],
            ]),
          ),
        );

    final actions = compact
        ? [
            const PrinterStatus(compact: true),
            SyncStatus(compact: true),
            PopupMenuButton<String>(
              tooltip: 'Menu',
              icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
              onSelected: (v) {
                switch (v) {
                  case 'clock':
                    context.push('/pos/clock');
                  case 'printer':
                    openUsbPrinterSettings(context, ref);
                  case 'sound':
                    showSoundSettings(context);
                  case 'security':
                    showSecurityDialog(context);
                  case 'lock':
                    ref.read(lockProvider.notifier).lock();
                  case 'logout':
                    ref.read(authProvider.notifier).logout();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'clock', child: Text('Pointage')),
                const PopupMenuItem(value: 'printer', child: Text('Imprimante USB')),
                if (alerts) const PopupMenuItem(value: 'sound', child: Text('Sons de notification')),
                const PopupMenuItem(value: 'security', child: Text('Sécurité du compte')),
                const PopupMenuItem(value: 'lock', child: Text('Verrouiller')),
                if (showLogout) const PopupMenuItem(value: 'logout', child: Text('Déconnexion')),
              ],
            ),
          ]
        : [
            const PrinterStatus(),
            const SizedBox(width: 8),
            const SyncStatus(),
            const SizedBox(width: 4),
            IconButton(tooltip: 'Imprimante USB', icon: const Icon(LucideIcons.printer, size: 18), onPressed: () => openUsbPrinterSettings(context, ref)),
            if (alerts) IconButton(tooltip: 'Sons de notification', icon: const Icon(LucideIcons.volume2, size: 18), onPressed: () => showSoundSettings(context)),
            IconButton(tooltip: 'Pointage', icon: const Icon(LucideIcons.alarmClock, size: 18), onPressed: () => context.push('/pos/clock')),
            IconButton(tooltip: 'Sécurité', icon: const Icon(LucideIcons.userCog, size: 18), onPressed: () => showSecurityDialog(context)),
            const SizedBox(width: 4),
            pillButton('VERROUILLER', LucideIcons.lock, const Color(0xFFFFEDD5), const Color(0xFFC2410C), () => ref.read(lockProvider.notifier).lock()),
            if (showLogout) ...[
              const SizedBox(width: 8),
              pillButton('DÉCONNEXION', LucideIcons.logOut, const Color(0xFFFEE2E2), const Color(0xFFB91C1C), () => ref.read(authProvider.notifier).logout()),
            ],
          ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (alerts) const WaiterAlerts(),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: scheme.outline))),
            child: Row(children: [
              Icon(LucideIcons.monitor, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              if (width >= 860)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text.rich(
                    TextSpan(children: [
                      if (registerName == null) const TextSpan(text: 'TERMINAL '),
                      TextSpan(text: (registerName ?? role?.label ?? '').toUpperCase(), style: TextStyle(color: role?.color ?? scheme.primary)),
                    ]),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: -0.5),
                  ),
                ),
              // Tabs take whatever is left and scroll sideways rather than overflow.
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [for (final (label, icon, route) in tabs) tab(label, icon, route)]),
                  ),
                ),
              ),
              const Spacer(),
              ...actions,
            ]),
          ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}
