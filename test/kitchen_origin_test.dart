import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';
import 'package:monokek_flutter/models/kitchen.dart';

void main() {
  test('central kitchen ticket carries its origin branch', () {
    final t = KitchenTicket.fromJson({
      'id': 1, 'reference': 'CMD-1', 'table': 'T1', 'status': 'pending', 'createdAt': '12:00', 'roundNumber': 1,
      'items': [], 'originBranchId': 20, 'originBranchName': 'Succursale Nord',
    });
    expect(t.originBranchId, 20);
    expect(t.originBranchName, 'Succursale Nord');
    expect(t.copyWith(status: TicketStatus.ready).originBranchName, 'Succursale Nord');
  });

  test('a local kitchen ticket (or an older server) has no origin name', () {
    final t = KitchenTicket.fromJson({'id': 2, 'status': 'pending', 'items': []});
    expect(t.originBranchName, isNull);
    expect(t.originBranchId, isNull);
  });

  test('a caught-up update reads exactly like a live ticket.updated event', () {
    // Shape returned by GET /api/kitchen/updates, re-emitted by NotificationsService._catchUp.
    const e = SseEvent('ticket.updated', {
      'ticketId': 1, 'orderId': 100, 'roundId': 200, 'stationId': 5, 'originBranchId': 20, 'status': 'ready', 'updatedAt': '2026-11-12T09:30:00',
    });
    expect(e.map['status'], 'ready');
    expect('${e.map['stationId']}', '5');
    expect(e.map['orderId'], 100);
  });
}
