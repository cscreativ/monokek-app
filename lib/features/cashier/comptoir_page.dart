import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/sse/notifications_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/kitchen.dart';
import '../../shared/widgets/pulse.dart';
import '../kitchen/kitchen_providers.dart' show playNewTicketSound;
import '../kitchen/ticket_board.dart';
import 'cashier_providers.dart';

/// Bar counter: tickets of the branch's BAR station, served directly (port of pos/sales/comptoir/page.tsx).
class ComptoirPage extends ConsumerWidget {
  const ComptoirPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final station = ref.watch(barStationProvider);

    return station.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(errorMessage(e, 'Impossible de charger la station')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => ref.invalidate(barStationProvider), child: const Text('Réessayer')),
        ]),
      ),
      data: (s) {
        if (s == null) {
          return Container(
            color: AppColors.slate950,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.chefHat, size: 80, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('AUCUNE STATION DE TYPE BAR CONFIGURÉE', textAlign: TextAlign.center, style: titleStyle.copyWith(fontSize: 14, color: Colors.white, letterSpacing: 2)),
              const SizedBox(height: 8),
              const Text('Créez ou assignez une station de type "Bar" dans les réglages (application desktop) pour activer cet écran.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => context.go('/pos/sales/order'), style: onDarkOutlinedButton, child: const Text('Retour à la vente')),
            ]),
          );
        }

        final id = s.id;
        final tickets = ref.watch(comptoirTicketsProvider(id));

        ref.listen(sseEventsProvider, (_, next) {
          final e = next.value;
          if (e == null || e.name != 'ticket.created' || '${e.map['stationId']}' != '$id') return;
          ref.read(comptoirRefreshProvider(id)).trigger();
          playNewTicketSound();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nouveau ticket : Table ${e.map['tableName'] ?? 'N/A'}')));
        });

        return Container(
          color: dark ? AppColors.slate950 : AppColors.slate50,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: dark ? AppColors.slate900 : Colors.white,
                border: Border(bottom: BorderSide(color: dark ? AppColors.darkMuted : const Color(0xFFF1F5F9), width: 2)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                      Text('COMPTOIR', style: titleStyle.copyWith(fontSize: 24)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                        child: Text('BAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: scheme.primary)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Pulse(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle))),
                      const SizedBox(width: 8),
                      Text('MONITORING EN TEMPS RÉEL', style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 1.5)),
                    ]),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(color: dark ? AppColors.darkMuted : AppColors.slate50, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    Text('${tickets.value?.length ?? 0}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: scheme.primary, height: 1)),
                    Text('EN ATTENTE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: scheme.onSurface.withValues(alpha: 0.5))),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.refresh(comptoirTicketsProvider(id).future),
                child: tickets.when(
                  loading: () => ListView(children: const [SizedBox(height: 160), Center(child: CircularProgressIndicator())]),
                  error: (e, _) => ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(errorMessage(e, 'Impossible de charger les tickets'))),
                    Center(child: TextButton(onPressed: () => ref.invalidate(comptoirTicketsProvider(id)), child: const Text('Réessayer'))),
                  ]),
                  data: (list) => list.isEmpty
                      ? const TicketEmptyState(icon: LucideIcons.beer)
                      : TicketBoard(
                          tickets: list,
                          finalStatus: TicketStatus.served,
                          onChange: (ticketId, next) => ref.read(comptoirTicketsProvider(id).notifier).setStatus(ticketId, next),
                        ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
