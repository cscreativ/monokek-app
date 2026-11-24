import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/security/setup_pin.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';
import 'package:monokek_flutter/core/theme/app_theme.dart';
import 'package:monokek_flutter/features/kitchen/kitchen_tickets_page.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';
import 'package:monokek_flutter/models/kitchen.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final (int, Object) Function(RequestOptions) handler;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    final (status, body) = handler(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('SseParser', () {
    test('parses named JSON events across lines', () {
      final p = SseParser();
      expect(p.addLine(': keep-alive'), isNull);
      expect(p.addLine('event: ticket.created'), isNull);
      expect(p.addLine('data: {"stationId":3,"tableName":"T4"}'), isNull);
      final e = p.addLine('');
      expect(e!.name, 'ticket.created');
      expect(e.map['stationId'], 3);
      expect(e.map['tableName'], 'T4');
    });

    test('joins multi-line data and defaults the name to "message"', () {
      final p = SseParser();
      p.addLine('data: hello');
      p.addLine('data: world');
      final e = p.addLine('')!;
      expect(e.name, 'message');
      expect(e.data, 'hello\nworld');
    });

    test('blank line with nothing buffered emits nothing', () {
      expect(SseParser().addLine(''), isNull);
    });
  });

  test('setup PIN hash is SHA-256 hex of the PIN', () {
    expect(hashSetupPin('1234'), '03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4');
  });

  test('LicenseStatus maps the snake_case payload', () {
    final s = LicenseStatus.fromJson({'active': true, 'expired': false, 'license_key': 'K', 'expiry_date': '2027-01-01', 'days_left': 80});
    expect(s.active, isTrue);
    expect(s.daysLeft, 80);
    expect(s.expiryDate, '2027-01-01');
  });

  test('KitchenTicket parses the Spring payload', () {
    final t = KitchenTicket.fromJson({
      'id': 7,
      'reference': 'ORD-1',
      'table': 'Table 2',
      'status': 'preparing',
      'createdAt': '12:30',
      'roundNumber': 2,
      'items': [
        {
          'id': 1,
          'name': 'Burger',
          'qty': 2,
          'modifiers': [
            {'name': 'Bacon', 'quantity': 1}
          ]
        }
      ],
    });
    expect(t.status, TicketStatus.preparing);
    expect(t.items.single.modifiers.single.name, 'Bacon');
    expect(t.copyWith(status: TicketStatus.ready).status, TicketStatus.ready);
  });

  testWidgets('kitchen board: start then finish a ticket', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = _FakeAdapter((o) {
      if (o.method == 'GET' && o.path == '/api/kitchen/tickets') {
        return (
          200,
          [
            {
              'id': 11,
              'reference': 'ORD-9',
              'table': 'Table 5',
              'status': 'pending',
              'createdAt': '19:05',
              'roundNumber': 1,
              'items': [
                {'id': 1, 'name': 'Pizza', 'qty': 2, 'modifiers': []}
              ],
            }
          ]
        );
      }
      return (200, {'ok': true});
    });
    final dio = Dio()..httpClientAdapter = adapter;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(dio),
        // keep the SSE stream out of the test
        sseEventsProvider.overrideWith((ref) => const Stream<SseEvent>.empty()),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const KitchenTicketsPage(stationId: 1)),
    ));
    // The header's live-dot Pulse animates forever, so pumpAndSettle would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('TABLE 5'), findsNothing); // table name is rendered as-is
    expect(find.text('Table 5'), findsOneWidget);
    expect(find.text('PIZZA'), findsOneWidget);
    expect(find.text('COMMENCER'), findsOneWidget);

    await tester.tap(find.text('COMMENCER'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(adapter.calls, contains('PATCH /api/kitchen/tickets/11/status'));
    expect(find.text('TERMINER'), findsOneWidget);

    await tester.tap(find.text('TERMINER'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Table 5'), findsNothing); // ready tickets leave the board
    expect(find.text('TOUT EST PRÊT !'), findsOneWidget);
  });
}
