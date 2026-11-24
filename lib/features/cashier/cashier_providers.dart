import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sse/notifications_service.dart';
import '../../data/cashier_api.dart';
import '../../data/pos_api.dart';
import '../../models/cashier.dart';
import '../../models/kitchen.dart';
import '../../models/ordering.dart';

/// Server-side cash session state (CashSyncProvider): the backend decides whether a shift is open.
final cashStatusProvider = FutureProvider.autoDispose<CashStatus>((ref) => ref.watch(cashierApiProvider).status());

/// Orders of the current shift. SSE payloads carry ids only, so each event refetches the list.
final salesOrdersProvider = FutureProvider.autoDispose<List<Order>>((ref) {
  final sub = ref.listen(sseEventsProvider, (_, next) {
    final n = next.value?.name;
    if (n == 'order.created' || n == 'order.updated' || n == 'ticket.created' || n == 'ticket.updated') ref.invalidateSelf();
  });
  ref.onDispose(sub.close);
  return ref.watch(posApiProvider).historyPos();
});

final roomChargeEnabledProvider = FutureProvider<bool>((ref) => ref.watch(posApiProvider).roomChargeEnabled());

/// The branch's BAR station (null when none is configured).
final barStationProvider = FutureProvider.autoDispose<KitchenStation?>((ref) => ref.watch(cashierApiProvider).barStation());

/// Bar counter tickets. Finishing a ticket here means "served" and removes it from the board.
class ComptoirTicketsNotifier extends AsyncNotifier<List<KitchenTicket>> {
  ComptoirTicketsNotifier(this.stationId);
  final int stationId;

  @override
  Future<List<KitchenTicket>> build() => ref.watch(cashierApiProvider).stationTickets(stationId);

  void refresh() => ref.invalidateSelf();

  Future<void> setStatus(int ticketId, TicketStatus next) async {
    await ref.read(cashierApiProvider).setDirectTicketStatus(ticketId, next.name);
    final current = state.value ?? const <KitchenTicket>[];
    state = AsyncData(
      next == TicketStatus.served
          ? current.where((t) => t.id != ticketId).toList()
          : [for (final t in current) t.id == ticketId ? t.copyWith(status: next) : t],
    );
    // The shift screen shows order statuses: keep it from serving a stale list.
    ref.invalidate(salesOrdersProvider);
  }
}

final comptoirTicketsProvider =
    AsyncNotifierProvider.autoDispose.family<ComptoirTicketsNotifier, List<KitchenTicket>, int>(ComptoirTicketsNotifier.new);
