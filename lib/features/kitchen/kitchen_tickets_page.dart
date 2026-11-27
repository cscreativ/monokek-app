import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/sse/notifications_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/pulse.dart';
import 'kitchen_providers.dart';
import 'ticket_board.dart';

/// Live ticket board of one station (port of kitchen/tickets/TicketsContent.tsx).
class KitchenTicketsPage extends ConsumerWidget {
  const KitchenTicketsPage({super.key, required this.stationId});
  final int? stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = stationId;
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (id == null) {
      return Scaffold(
        backgroundColor: AppColors.slate950,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.chefHat, size: 80, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text('STATION NON RECONNUE', style: titleStyle.copyWith(fontSize: 14, color: Colors.white, letterSpacing: 3)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.go('/kitchen'), style: onDarkOutlinedButton, child: const Text('Retour au dashboard')),
          ]),
        ),
      );
    }

    final tickets = ref.watch(ticketsProvider(id));

    ref.listen(sseEventsProvider, (_, next) {
      final e = next.value;
      // Another screen of the same kitchen moved a ticket: refresh quietly (no sound, no toast).
      if (e != null && e.name == 'ticket.updated' && '${e.map['stationId']}' == '$id') {
        ref.read(stationBoardRefreshProvider(id)).trigger();
        return;
      }
      if (e == null || e.name != 'ticket.created') return;
      if ('${e.map['stationId']}' != '$id') return;
      ref.read(stationBoardRefreshProvider(id)).trigger();
      playNewTicketSound();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nouveau ticket : Table ${e.map['tableName'] ?? 'N/A'}')));
    });

    return Scaffold(
      backgroundColor: dark ? AppColors.slate950 : AppColors.slate50,
      body: SafeArea(
        child: Column(children: [
          _TicketsHeader(stationId: id, count: tickets.value?.length ?? 0),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(ticketsProvider(id).future),
              child: tickets.when(
                loading: () => ListView(children: const [SizedBox(height: 160), Center(child: CircularProgressIndicator())]),
                error: (e, _) => ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text(errorMessage(e, 'Impossible de charger les tickets'))),
                  const SizedBox(height: 12),
                  Center(child: OutlinedButton(onPressed: () => ref.invalidate(ticketsProvider(id)), child: const Text('Réessayer'))),
                ]),
                data: (list) => list.isEmpty
                    ? const TicketEmptyState()
                    : TicketBoard(tickets: list, onChange: (ticketId, next) => ref.read(ticketsProvider(id).notifier).setStatus(ticketId, next)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TicketsHeader extends StatelessWidget {
  const _TicketsHeader({required this.stationId, required this.count});
  final int stationId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.slate900 : Colors.white,
        border: Border(bottom: BorderSide(color: dark ? AppColors.darkMuted : const Color(0xFFF1F5F9), width: 2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.canPop() ? context.pop() : context.go('/kitchen'),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: dark ? AppColors.darkMuted : AppColors.slate50, borderRadius: BorderRadius.circular(16)),
            child: const Icon(LucideIcons.chevronLeft, size: 28),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              Text('PRÉPARATION', style: titleStyle.copyWith(fontSize: 24)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                child: Text('STATION #$stationId', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: scheme.primary)),
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
            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: scheme.primary, height: 1)),
            Text('EN ATTENTE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: scheme.onSurface.withValues(alpha: 0.5))),
          ]),
        ),
      ]),
    );
  }
}
