import '../sse/notifications_service.dart';

/// What a waiter terminal rings for. Each kind has its own sound so the waiter knows what happened without looking.
enum AlertKind {
  /// One of MY orders is ready to be served.
  ready,

  /// A ticket has waited too long for the kitchen.
  delayed,

  /// One of MY orders was paid or cancelled.
  orderClosed,
}

/// The alert an SSE event deserves for the signed-in user, or null for silence. Pure: no audio, no state.
///
/// The server already addresses `ticket.updated` / `ticket.delayed` to the staff member who sent the round (plus till and
/// management), so for a waiter they are about their own orders. `order.updated` goes to the whole branch: it only rings when
/// the payload names this user as the order's waiter (`orderUserId`), otherwise every phone would ring for every payment.
AlertKind? alertFor(SseEvent event, {required int? myUserId}) {
  final data = event.map;
  switch (event.name) {
    case 'ticket.updated':
      return data['status'] == 'ready'
          ? AlertKind.ready
          : null; // "preparing" etc. stay silent
    case 'ticket.delayed':
      return AlertKind.delayed;
    case 'order.updated':
      final status = data['newStatus'];
      if (status != 'paid' && status != 'cancelled') return null;
      final owner = data['orderUserId'];
      return myUserId != null && owner != null && '$owner' == '$myUserId'
          ? AlertKind.orderClosed
          : null;
    default:
      return null;
  }
}

/// Keeps a burst of events from becoming a burst of sounds.
///
/// - the same alert for the same order is played once within [duplicateWindow] (the live event and its catch-up copy);
/// - two sounds are never closer than [minGap];
/// - updates replayed after a reconnection ring at most once per [replayWindow], however many there are.
class AlertGate {
  AlertGate({
    this.duplicateWindow = const Duration(seconds: 5),
    this.minGap = const Duration(milliseconds: 700),
    this.replayWindow = const Duration(seconds: 10),
  });

  final Duration duplicateWindow;
  final Duration minGap;
  final Duration replayWindow;

  final Map<String, DateTime> _seen = {};
  DateTime? _lastPlayed;
  DateTime? _lastReplayPlayed;

  bool shouldPlay(AlertKind kind, SseEvent event, DateTime now) {
    _seen.removeWhere((_, at) => now.difference(at) > duplicateWindow);

    final key =
        '${kind.name}:${event.map['orderId'] ?? event.map['ticketId'] ?? ''}';
    if (_seen.containsKey(key)) return false;
    if (_lastPlayed != null && now.difference(_lastPlayed!) < minGap) {
      return false;
    }
    if (event.replayed && _lastReplayPlayed != null && now.difference(_lastReplayPlayed!) < replayWindow) {
      return false;
    }

    _seen[key] = now;
    _lastPlayed = now;
    if (event.replayed) _lastReplayPlayed = now;
    return true;
  }
}
