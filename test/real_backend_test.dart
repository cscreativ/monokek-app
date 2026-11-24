import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/format.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';
import 'package:monokek_flutter/data/staffing_api.dart';
import 'package:monokek_flutter/features/auth/auth_controller.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';
import 'package:monokek_flutter/models/app_user.dart';
import 'package:monokek_flutter/models/cashier.dart';
import 'package:monokek_flutter/models/catalog.dart';
import 'package:monokek_flutter/models/floorplan.dart';
import 'package:monokek_flutter/models/kitchen.dart';
import 'package:monokek_flutter/models/ordering.dart';

/// Payloads captured from the REAL monokek stack (docker, http://localhost:8090, 2026-10-10):
/// guards the app's models against the actual wire formats, not just the Tauri types.
dynamic fx(String name) => jsonDecode(File('test/fixtures/real/$name').readAsStringSync());

void main() {
  test('login + /api/me → AppUser (what AuthController.login assembles)', () {
    final login = fx('login.json')['data'] as Map<String, dynamic>;
    final me = fx('me.json') as Map<String, dynamic>;
    final summary = login['user'] as Map<String, dynamic>;
    final user = AppUser(
      id: (summary['id'] as num).toInt(),
      uuid: me['uuid'] as String,
      name: summary['name'] as String,
      role: summary['role'] as String,
      permissions: (me['permissions'] as List).cast<String>(),
      branchId: (me['branchId'] as num?)?.toInt(),
    );
    expect((user.role, user.branchId, user.name), ('cashier', 1, 'Cashier User'));
    expect(login['expiresInSeconds'], 1800);
    // the persisted session round-trips
    final state = AuthState(user: user, token: 't', refreshToken: 'r', expiresAt: DateTime(2026));
    expect(AuthState.fromJson(state.toJson()).user!.branchId, 1);
  });

  test('licence', () {
    final l = LicenseStatus.fromJson(fx('license.json') as Map<String, dynamic>);
    expect((l.active, l.expired, l.daysLeft), (true, false, 364));
  });

  test('floors: a take-away floor holding only the virtual table, plus real dining floors', () {
    final floors = (fx('floors.json') as List).map((e) => Floor.fromJson(e as Map<String, dynamic>)).toList();
    expect(floors.length, 2);
    expect(floors.first.tables.single.virtual, isTrue);
    expect(floors.first.tables.single.status, 'free');
    expect(floors.last.tables.every((t) => !t.virtual), isTrue);
    expect(floors.last.tables.map((t) => t.name), ['T-01', 'T05']);
  });

  test('products: a "supplement" group flagged optional but minSelect 1 still needs a selection', () {
    final products = (fx('products.json') as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    final p = products.firstWhere((p) => p.id == 107);
    final supplements = p.modifiers.firstWhere((g) => g.name == 'Supplements');
    expect(supplements.required, isFalse);
    expect(supplements.minSelect, 1);
    expect(supplements.effectiveMin, 1); // the dialog must block confirm, like the server does
    expect(supplements.ruleLabel, 'Au moins 1');
    final accom = p.modifiers.firstWhere((g) => g.name == 'Accom');
    expect(accom.effectiveMin, 0);
    expect(accom.ruleLabel, 'Optionnel · max 1');
    expect(products.firstWhere((p) => p.id == 17).type, 'storable');
  });

  test('send-round result', () {
    final body = fx('send_round.json') as Map<String, dynamic>;
    final order = Order.fromJson(body['order'] as Map<String, dynamic>);
    expect(order.reference, startsWith('CMD-'));
    expect(order.total, 8200);
    expect(order.tableName, 'Emporter — Douala');
    expect(order.waiterName, 'Waiter User');
    final round = order.rounds.single;
    expect(round.editable, isTrue); // status "sent"
    expect(round.sentAt, isNotNull, reason: 'server sends "yyyy-MM-dd HH:mm:ss" with a space');
    expect(round.items.single.modifiers.single.name, 'pommes Frites');
    expect(round.items.single.productId, 107);
    expect(body['skippedKitchenItems'], isEmpty);
  });

  test('kitchen tickets + stations', () {
    final t = (fx('kitchen_tickets.json') as List).map((e) => KitchenTicket.fromJson(e as Map<String, dynamic>)).single;
    expect((t.status, t.roundNumber, t.createdAt), (TicketStatus.pending, 1, '13:04'));
    expect(t.items.single.modifiers.single.name, 'pommes Frites');
    final stations = (fx('stations.json') as List).map((e) => KitchenStation.fromJson(e as Map<String, dynamic>)).toList();
    expect(stations.where((s) => s.type == 'BAR').single.name, 'Bar');
  });

  test('cash status / summary / registers; payment keys are mapped to labels', () {
    final status = CashStatus.fromJson(fx('cash_status.json') as Map<String, dynamic>);
    expect(status.isOpen, isTrue);
    expect(status.session!.registerName, 'Caisse principale');
    expect(status.session!.openedAt, isNotNull, reason: 'openedAt has no timezone suffix');

    final summary = CashSummary.fromJson(fx('cash_summary.json') as Map<String, dynamic>);
    expect(summary.payments.first.method, 'cash'); // raw key from the server…
    expect(paymentMethodLabel(summary.payments.first.method), 'Espèces'); // …shown as a label
    expect(paymentMethodLabel('room_charge'), 'Chambre');

    final reg = CashRegister.fromJson((fx('registers.json') as List).single as Map<String, dynamic>);
    expect((reg.isOpen, reg.openedByUserName), (true, 'Cashier User'));
  });

  test('shift history is enveloped and parses', () {
    final data = (fx('history.json') as Map<String, dynamic>)['data'] as List;
    final orders = data.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
    expect(orders, isNotEmpty);
    expect(orders.first.status, anyOf('paid', 'completed', 'pending'));
  });

  test('SSE: real stream framing (":connected" comment, "event:" without a space)', () {
    final parser = SseParser();
    final events = <SseEvent>[];
    for (final line in const LineSplitter().convert(File('test/fixtures/real/sse_stream.txt').readAsStringSync())) {
      final e = parser.addLine(line);
      if (e != null) events.add(e);
    }
    expect(events.map((e) => e.name), ['order.created', 'ticket.created']);
    expect(events[0].map['reference'], 'CMD-7F8096B5');
    expect(events[1].map['stationId'], 2);
    expect(events[1].map['tableName'], 'Emporter — Douala');
  });

  test('clock entry tolerates the optional fields', () {
    final e = TimeClockEntry.fromJson({'id': 1, 'userId': 4, 'userName': null, 'branchId': 1, 'clockInAt': '2026-10-10T08:15:00', 'clockOutAt': null});
    expect(e.userName, isNull);
    expect(e.clockInAt, isNotNull);
  });
}
