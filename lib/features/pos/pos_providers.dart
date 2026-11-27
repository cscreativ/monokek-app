import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sse/coalescer.dart';
import '../../core/sse/notifications_service.dart';
import '../../data/pos_api.dart';
import '../../models/catalog.dart';
import '../../models/floorplan.dart';
import '../../models/ordering.dart';
import '../auth/auth_controller.dart';

/// Floors with their tables. The SSE payload is only ids, so events just trigger a refetch:
/// the server stays the single source of truth.
final floorsProvider = FutureProvider.autoDispose<List<Floor>>((ref) async {
  // A table changes state when an order is opened, paid, cancelled or moved: kitchen tickets never touch it, so they no longer refetch the plan.
  // And a burst of events refetches once (see Coalescer), not once per event.
  final refresh = Coalescer(ref.invalidateSelf);
  ref.onDispose(refresh.dispose);
  final sub = ref.listen(sseEventsProvider, (_, next) {
    final n = next.value?.name;
    if (n == 'order.created' || n == 'order.updated') refresh.trigger();
  });
  ref.onDispose(sub.close);
  return ref.watch(posApiProvider).listFloors();
});

/// The menu. Kept alive for the whole session (the old autoDispose version re-downloaded it, behind a
/// spinner, every time a table was opened): after an invalidation Riverpod keeps showing the previous
/// list while the new one loads. Tied to the user id so a different login never sees another menu.
final productsProvider = FutureProvider<List<Product>>((ref) {
  ref.watch(authProvider.select((a) => a.user?.id));
  return ref.watch(posApiProvider).listProducts();
});

final allowOversellProvider = FutureProvider<bool>((ref) => ref.watch(posApiProvider).allowOversell());

/// Open order of a table; null when none. Writes after send-round/edit go straight into state
/// (a virtual table always reports "no active order", so a refetch would erase the new round).
class ActiveOrderNotifier extends AsyncNotifier<Order?> {
  ActiveOrderNotifier(this.tableId);
  final int tableId;

  @override
  Future<Order?> build() => ref.watch(posApiProvider).getActiveOrder(tableId);

  void setOrder(Order order) => state = AsyncData(order);
}

final activeOrderProvider = AsyncNotifierProvider.autoDispose.family<ActiveOrderNotifier, Order?, int>(ActiveOrderNotifier.new);
