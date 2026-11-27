import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/theme/app_theme.dart';
import '../../models/kitchen.dart';
import '../auth/auth_controller.dart';
import '../auth/lock_overlay.dart';
import '../../core/sse/notifications_service.dart';
import '../../shared/widgets/printer_status.dart';
import '../../shared/widgets/sync_status.dart';
import 'kitchen_providers.dart';

/// KDS home: one card per station with its pending-ticket count (port of kitchen/page.tsx).
class KitchenDashboardPage extends ConsumerWidget {
  const KitchenDashboardPage({super.key});

  static IconData iconFor(KitchenStation s) {
    final n = s.name.toLowerCase();
    if (n.contains('grill') || s.type == 'GRILL') return LucideIcons.flame;
    if (n.contains('bar') || n.contains('boisson') || s.type == 'BAR') return LucideIcons.beer;
    if (n.contains('café') || n.contains('cafe')) return LucideIcons.coffee;
    return LucideIcons.utensils;
  }

  static Color colorFor(KitchenStation s, Color fallback) {
    final n = s.name.toLowerCase();
    if (n.contains('grill') || s.type == 'GRILL') return AppColors.orange;
    if (n.contains('bar') || n.contains('boisson') || s.type == 'BAR') return AppColors.info;
    if (n.contains('café') || n.contains('cafe')) return const Color(0xFF92400E);
    return fallback;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stations = ref.watch(stationsProvider);

    // A new ticket always changes some station's counter.
    ref.listen(sseEventsProvider, (_, next) {
      final n = next.value?.name;
      if (n == 'ticket.created' || n == 'ticket.updated') ref.read(stationsRefreshProvider).trigger();
    });

    return Scaffold(
      backgroundColor: dark ? AppColors.slate950 : AppColors.slate50,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(stationsProvider.future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                sliver: SliverToBoxAdapter(child: _Header(ref: ref)),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: stations.when(
                  loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()))),
                  error: (e, _) => SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(children: [
                        Text(errorMessage(e, 'Erreur chargement stations')),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: () => ref.invalidate(stationsProvider), child: const Text('Réessayer')),
                      ]),
                    ),
                  ),
                  data: (list) => list.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: Center(child: Text('AUCUNE STATION CONFIGURÉE', style: microLabelStyle.copyWith(color: scheme.onSurfaceVariant))),
                          ),
                        )
                      : SliverGrid.builder(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 420,
                            mainAxisSpacing: 24,
                            crossAxisSpacing: 24,
                            mainAxisExtent: 220,
                          ),
                          itemCount: list.length,
                          itemBuilder: (_, i) => _StationCard(station: list[i], dark: dark),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final cardBg = dark ? AppColors.slate900 : Colors.white;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: 16,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.layoutGrid, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Text('SYSTÈME KDS', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 4)),
          ]),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'STATIONS DE '),
              TextSpan(text: 'CUISINE', style: TextStyle(color: scheme.onSurfaceVariant)),
            ]),
            style: titleStyle.copyWith(fontSize: 34),
          ),
          const SizedBox(height: 6),
          Text('Sélectionnez une station pour voir les commandes en cours.', style: TextStyle(color: scheme.onSurfaceVariant)),
        ]),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const PrinterStatus(),
          const SyncStatus(),
          _RoundAction(icon: LucideIcons.printer, tooltip: 'Imprimante USB', background: cardBg, onTap: () => openUsbPrinterSettings(context, ref)),
          _RoundAction(icon: LucideIcons.alarmClock, tooltip: 'Pointage', background: cardBg, onTap: () => context.push('/pos/clock')),
          _RoundAction(icon: LucideIcons.lock, tooltip: 'Verrouiller', background: cardBg, onTap: () => ref.read(lockProvider.notifier).lock()),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => ref.read(authProvider.notifier).logout(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text((user?.name ?? 'Session').toUpperCase(), style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 1.5)),
                  const Text('QUITTER', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                ]),
                const SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: dark ? AppColors.darkMuted : const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(LucideIcons.logOut, size: 20),
                ),
              ]),
            ),
          ),
        ]),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.tooltip, required this.background, required this.onTap});
  final IconData icon;
  final String tooltip;
  final Color background;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon),
          ),
        ),
      );
}

class _StationCard extends StatelessWidget {
  const _StationCard({required this.station, required this.dark});
  final KitchenStation station;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = KitchenDashboardPage.colorFor(station, scheme.primary);
    final icon = KitchenDashboardPage.iconFor(station);
    final pending = station.pendingTicketsCount;

    return Material(
      color: dark ? AppColors.slate900 : Colors.white,
      borderRadius: BorderRadius.circular(40),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () => context.push('/kitchen/tickets?station=${station.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: dark ? AppColors.slate900 : Colors.white, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(children: [
            Positioned(right: -10, top: -10, child: Opacity(opacity: 0.06, child: Icon(icon, size: 120, color: color))),
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: dark ? AppColors.darkMuted : AppColors.slate50, borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, size: 32, color: color),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(station.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle.copyWith(fontSize: 24, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: pending > 0 ? const Color(0xFFEF4444) : (dark ? AppColors.darkMuted : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$pending EN ATTENTE',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: pending > 0 ? Colors.white : const Color(0xFF64748B)),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
