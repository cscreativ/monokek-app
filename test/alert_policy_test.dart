import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/sound/alert_policy.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';

void main() {
  group('alertFor', () {
    test('a ticket that is ready rings; other statuses stay silent', () {
      expect(alertFor(const SseEvent('ticket.updated', {'status': 'ready', 'orderId': 5}), myUserId: 1), AlertKind.ready);
      expect(alertFor(const SseEvent('ticket.updated', {'status': 'preparing', 'orderId': 5}), myUserId: 1), isNull);
      expect(alertFor(const SseEvent('ticket.updated', {'status': 'served', 'orderId': 5}), myUserId: 1), isNull);
    });

    test('a late ticket has its own alert', () {
      expect(alertFor(const SseEvent('ticket.delayed', {'orderId': 5, 'pendingMinutes': 7}), myUserId: 1), AlertKind.delayed);
    });

    test('a paid or cancelled order rings only for ITS waiter', () {
      const mine = SseEvent('order.updated', {'orderId': 9, 'newStatus': 'paid', 'orderUserId': 1});
      const theirs = SseEvent('order.updated', {'orderId': 9, 'newStatus': 'paid', 'orderUserId': 2});
      const unknown = SseEvent('order.updated', {'orderId': 9, 'newStatus': 'paid'}); // older server: no owner in the payload
      expect(alertFor(mine, myUserId: 1), AlertKind.orderClosed);
      expect(alertFor(theirs, myUserId: 1), isNull);
      expect(alertFor(unknown, myUserId: 1), isNull);
      expect(alertFor(const SseEvent('order.updated', {'newStatus': 'cancelled', 'orderUserId': 1}), myUserId: 1), AlertKind.orderClosed);
    });

    test('other status changes and unknown events stay silent', () {
      expect(alertFor(const SseEvent('order.updated', {'newStatus': 'completed', 'orderUserId': 1}), myUserId: 1), isNull);
      expect(alertFor(const SseEvent('order.created', {'orderId': 1}), myUserId: 1), isNull);
      expect(alertFor(const SseEvent('print-job-queued', {}), myUserId: 1), isNull);
    });

    test('nobody signed in: the order sound never rings', () {
      expect(alertFor(const SseEvent('order.updated', {'newStatus': 'paid', 'orderUserId': 1}), myUserId: null), isNull);
    });
  });

  group('AlertGate', () {
    final t0 = DateTime(2026, 1, 1, 12);
    const ready = SseEvent('ticket.updated', {'status': 'ready', 'orderId': 5});

    test('the same alert for the same order rings once', () {
      final gate = AlertGate();
      expect(gate.shouldPlay(AlertKind.ready, ready, t0), isTrue);
      expect(gate.shouldPlay(AlertKind.ready, ready, t0.add(const Duration(seconds: 2))), isFalse);
      expect(gate.shouldPlay(AlertKind.ready, ready, t0.add(const Duration(seconds: 6))), isTrue); // window elapsed
    });

    test('two sounds are never closer than the minimum gap', () {
      final gate = AlertGate();
      expect(gate.shouldPlay(AlertKind.ready, ready, t0), isTrue);
      const other = SseEvent('ticket.updated', {'status': 'ready', 'orderId': 6});
      expect(gate.shouldPlay(AlertKind.ready, other, t0.add(const Duration(milliseconds: 300))), isFalse);
      expect(gate.shouldPlay(AlertKind.ready, other, t0.add(const Duration(milliseconds: 900))), isTrue);
    });

    test('a burst of replayed updates rings once', () {
      final gate = AlertGate();
      var rang = 0;
      for (var i = 1; i <= 6; i++) {
        final e = SseEvent('ticket.updated', {'status': 'ready', 'orderId': i}, replayed: true);
        if (gate.shouldPlay(AlertKind.ready, e, t0.add(Duration(seconds: i)))) rang++;
      }
      expect(rang, 1);
    });

    test('a live alert is not blocked by an earlier replay', () {
      final gate = AlertGate();
      const replayed = SseEvent('ticket.updated', {'status': 'ready', 'orderId': 1}, replayed: true);
      expect(gate.shouldPlay(AlertKind.ready, replayed, t0), isTrue);
      const live = SseEvent('ticket.updated', {'status': 'ready', 'orderId': 2});
      expect(gate.shouldPlay(AlertKind.ready, live, t0.add(const Duration(seconds: 2))), isTrue);
    });
  });
}
