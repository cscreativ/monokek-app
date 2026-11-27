import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/sse/coalescer.dart';
import '../../models/kitchen.dart';

/// GET /api/kitchen/stations — bare array, includes each station's pending-ticket count.
final stationsProvider = FutureProvider.autoDispose<List<KitchenStation>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/api/kitchen/stations');
  return (res.data as List).map((e) => KitchenStation.fromJson(e as Map<String, dynamic>)).toList();
});

/// Live ticket board of one station. The server remains the source of truth: SSE only
/// triggers [refresh]; status changes are applied locally right after the PATCH succeeds.
class TicketsNotifier extends AsyncNotifier<List<KitchenTicket>> {
  TicketsNotifier(this.stationId);
  final int stationId;

  @override
  Future<List<KitchenTicket>> build() async {
    final res = await ref.watch(apiClientProvider).get('/api/kitchen/tickets', queryParameters: {'stationId': stationId});
    return (res.data as List).map((e) => KitchenTicket.fromJson(e as Map<String, dynamic>)).toList();
  }

  void refresh() => ref.invalidateSelf();

  /// Throws on failure so the UI can toast. `ready` tickets leave the board.
  Future<void> setStatus(int ticketId, TicketStatus next) async {
    await ref.read(apiClientProvider).patch('/api/kitchen/tickets/$ticketId/status', data: {'status': next.name});
    final current = state.value ?? const <KitchenTicket>[];
    state = AsyncData(
      next == TicketStatus.ready
          ? current.where((t) => t.id != ticketId).toList()
          : [for (final t in current) t.id == ticketId ? t.copyWith(status: next) : t],
    );
  }
}

final ticketsProvider = AsyncNotifierProvider.autoDispose.family<TicketsNotifier, List<KitchenTicket>, int>(TicketsNotifier.new);

/// The station list (counters) refreshes at most once per second however many ticket events arrive.
final stationsRefreshProvider = Provider.autoDispose<Coalescer>((ref) {
  final c = Coalescer(() => ref.invalidate(stationsProvider), interval: const Duration(seconds: 1));
  ref.onDispose(c.dispose);
  return c;
});

/// Refreshes one station's board AT MOST once per second however many events arrive (a kitchen wants it fresh, not once per event).
final stationBoardRefreshProvider = Provider.autoDispose.family<Coalescer, int>((ref, stationId) {
  final c = Coalescer(() => ref.read(ticketsProvider(stationId).notifier).refresh(), interval: const Duration(seconds: 1));
  ref.onDispose(c.dispose);
  return c;
});

final _player = AudioPlayer();

/// Chime on a new ticket. Best-effort: never let audio failures reach the UI.
Future<void> playNewTicketSound() async {
  try {
    await _player.stop();
    await _player.play(AssetSource('sounds/notification.mp3'));
  } catch (_) {}
}
