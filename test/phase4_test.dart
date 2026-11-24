import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/api/envelope.dart';
import 'package:monokek_flutter/core/router/app_router.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/core/theme/app_theme.dart';
import 'package:monokek_flutter/features/cashier/manager_pin_dialog.dart';
import 'package:monokek_flutter/features/cashier/payment_dialog.dart';
import 'package:monokek_flutter/features/cashier/sales_page.dart';
import 'package:monokek_flutter/models/cashier.dart';
import 'package:monokek_flutter/models/ordering.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final (int, Object?) Function(RequestOptions) handler;
  final requests = <RequestOptions>[];

  Iterable<RequestOptions> where(String method, String path) => requests.where((r) => r.method == method && r.path == path);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = handler(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _order({double total = 5000, double discount = 0, String? coupon, String status = 'completed'}) => {
      'id': 7,
      'uuid': 'uuid-7',
      'reference': 'ORD-7',
      'type': 'dinein',
      'status': status,
      'amounts': {'subtotal': 5000, 'tax': 0, 'discount': discount, 'total': total, 'formattedTotal': '${total.toStringAsFixed(0)} FCFA', 'couponCode': coupon},
      'table': {'id': 4, 'name': 'T4', 'status': 'billing'},
      'waiter': {'id': 3, 'name': 'Awa'},
      'rounds': [
        {
          'id': 70,
          'roundNumber': 1,
          'status': 'sent',
          'sentAt': '2026-10-10T12:00:00Z',
          'totalRound': 5000,
          'items': [
            {
              'id': 900,
              'qty': 2,
              'price': 2500,
              'total': 5000,
              'status': 'pending',
              'product': {'id': 10, 'name': 'Burger'},
              'variant': null,
              'modifiers': [],
              'formattedTotal': '5 000 FCFA',
            }
          ],
        }
      ],
      'note': null,
      'time': '12:00',
      'date': '10/10/2026',
    };

String? r(String loc, {String? role}) => computeRedirect(location: loc, hasBackend: true, authenticated: true, role: role);

Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 250));
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('router', () {
    test('cashier reaches the whole cashier tree', () {
      for (final p in ['/pos/sales', '/pos/sales/order', '/pos/sales/tables', '/pos/sales/tables/order', '/pos/sales/comptoir', '/pos/sales/history']) {
        expect(r(p, role: 'cashier'), isNull, reason: p);
      }
    });
    test('waiter is kept out of the cashier tree, kitchen out of /pos', () {
      expect(r('/pos/sales/order', role: 'waiter'), '/pos/tables');
      expect(r('/pos/sales/tables/order', role: 'waiter'), '/pos/tables');
      expect(r('/pos/sales/history', role: 'kitchen'), '/kitchen');
    });
  });

  test('cash models parse the Spring payloads', () {
    final status = CashStatus.fromJson({
      'isOpen': true,
      'session': {'id': 1, 'registerId': 2, 'registerName': 'Caisse 1', 'openingAmount': 10000, 'openedAt': '2026-10-10T08:00:00Z'},
    });
    expect(status.isOpen, isTrue);
    expect(status.session!.registerName, 'Caisse 1');

    final report = CloseReport.fromJson({
      'message': 'ok',
      'report': {
        'openedAt': '2026-10-10T08:00:00Z',
        'closedAt': '2026-10-10T20:00:00Z',
        'openingAmount': 10000,
        'totalPayments': 50000,
        'expectedTotal': 60000,
        'actualTotal': 59000,
        'difference': -1000,
        'note': 'billet abîmé',
        'paymentsDetail': [
          {'method': 'Espèces', 'total': 30000},
          {'method': 'MoMo', 'total': 20000}
        ],
      },
    });
    expect(report.difference, -1000);
    expect(report.payments.map((p) => p.method), ['Espèces', 'MoMo']);
  });

  group('manager PIN dialog', () {
    Future<void> open(WidgetTester t, Future<void> Function(String, String) onConfirm, void Function(bool) done) async {
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => done(await showManagerPinDialog(ctx, title: 'ANNULER', subtitle: 'ORD-7', confirmLabel: 'Confirmer', reasonHint: 'motif', onConfirm: onConfirm)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await settle(t);
    }

    testWidgets('needs a reason AND a 4-digit PIN, then sends both', (t) async {
      String? reason, pin;
      bool? result;
      await open(t, (rs, p) async {
        reason = rs;
        pin = p;
      }, (v) => result = v);

      FilledButton button() => t.widget<FilledButton>(find.byType(FilledButton));
      expect(button().onPressed, isNull);

      await t.enterText(find.byType(TextField).first, 'erreur de saisie');
      await t.pump();
      expect(button().onPressed, isNull); // PIN still missing

      await t.enterText(find.byType(TextField).last, '12');
      await t.pump();
      expect(button().onPressed, isNull); // too short

      await t.enterText(find.byType(TextField).last, '1234');
      await t.pump();
      expect(button().onPressed, isNotNull);

      await t.tap(find.byType(FilledButton));
      await settle(t);
      expect((reason, pin), ('erreur de saisie', '1234'));
      expect(result, isTrue);
    });

    testWidgets('a rejected PIN keeps the dialog open', (t) async {
      bool? result;
      await open(t, (_, _) async => throw ApiError('Code PIN manager invalide'), (v) => result = v);
      await t.enterText(find.byType(TextField).first, 'motif');
      await t.enterText(find.byType(TextField).last, '0000');
      await t.pump();
      await t.tap(find.byType(FilledButton));
      await settle(t);
      expect(result, isNull); // still open, nothing resolved
      expect(find.text('Code PIN manager invalide'), findsOneWidget);
    });
  });

  group('payment dialog', () {
    late _Adapter adapter;

    Future<void> pump(WidgetTester t, {bool roomEnabled = false, Order? order, bool Function()? couponWorks}) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final storage = (await t.runAsync(AppStorage.create))!;

      adapter = _Adapter((o) {
        switch ('${o.method} ${o.path}') {
          case 'GET /api/admin/settings':
            return (200, {'room_charge_enabled': roomEnabled});
          case 'GET /api/pos/rooms/204':
            return (200, {'status': 'success', 'data': {'bookingId': 55, 'guestName': 'Mme Dupont'}});
          case 'POST /api/pos/orders/uuid-7/coupon':
            return (200, _order(total: 4000, discount: 1000, coupon: 'PROMO10'));
          case 'DELETE /api/pos/orders/uuid-7/coupon':
            return (200, _order());
          case 'POST /api/pos/orders/uuid-7/finalize':
            return (200, {'status': 'success', 'message': 'Paiement enregistré', 'data': null});
        }
        return (404, {'message': 'unexpected ${o.method} ${o.path}'});
      });

      await t.pumpWidget(ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
          sseEventsProvider.overrideWith((ref) => const Stream<SseEvent>.empty()),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: Center(child: SingleChildScrollView(child: PaymentView(order: order ?? Order.fromJson(_order()))))),
        ),
      ));
      await settle(t);
    }

    FilledButton validate(WidgetTester t) => t.widget<FilledButton>(find.ancestor(of: find.text('VALIDER'), matching: find.byType(FilledButton)));

    testWidgets('cash: amount prefilled with the total, numpad edits it, finalize payload', (t) async {
      await pump(t);
      expect(validate(t).onPressed, isNotNull); // received == total

      // 5000 -> back x2 -> "50" -> insufficient
      await t.tap(find.byIcon(Icons.backspace_outlined).evaluate().isNotEmpty ? find.byIcon(Icons.backspace_outlined) : find.byType(OutlinedButton).at(11));
      await t.pump();
      await t.tap(find.byType(OutlinedButton).at(11));
      await t.pump();
      expect(validate(t).onPressed, isNull);

      // type 00 -> "5000" again
      await t.tap(find.widgetWithText(OutlinedButton, '00'));
      await t.pump();
      expect(validate(t).onPressed, isNotNull);

      await t.tap(find.text('VALIDER'));
      await settle(t);
      final body = adapter.where('POST', '/api/pos/orders/uuid-7/finalize').single.data as Map;
      expect(body['paymentMethod'], 'cash');
      expect(body['amountReceived'], 5000);
      expect(body.containsKey('roomNumber'), isFalse);
    });

    testWidgets('room charge is hidden unless the hotel integration is enabled', (t) async {
      await pump(t, roomEnabled: false);
      expect(find.text('CHAMBRE'), findsNothing);
    });

    testWidgets('room charge: guest must be verified before billing; a number edit invalidates it', (t) async {
      await pump(t, roomEnabled: true);
      await t.tap(find.text('CHAMBRE'));
      await t.pump();
      expect(validate(t).onPressed, isNull); // no verified guest yet

      await t.enterText(find.byType(TextField).first, '204');
      await t.pump();
      await t.tap(find.text('VÉRIFIER'));
      await settle(t);
      expect(find.text('Mme Dupont'), findsOneWidget);
      expect(validate(t).onPressed, isNotNull);

      // Editing the number drops the confirmation (never bill a name checked for ANOTHER room).
      await t.enterText(find.byType(TextField).first, '2041');
      await t.pump();
      expect(find.text('Mme Dupont'), findsNothing);
      expect(validate(t).onPressed, isNull);

      await t.enterText(find.byType(TextField).first, '204');
      await t.pump();
      await t.tap(find.text('VÉRIFIER'));
      await settle(t);
      await t.tap(find.text('VALIDER'));
      await settle(t);
      final body = adapter.where('POST', '/api/pos/orders/uuid-7/finalize').single.data as Map;
      expect(body['paymentMethod'], 'room_charge');
      expect(body['roomNumber'], '204');
    });

    testWidgets('coupon lowers the total, refills the amount and can be removed', (t) async {
      await pump(t);
      await t.enterText(find.byType(TextField).last, 'promo10');
      await t.pump();
      await t.tap(find.text('APPLIQUER'));
      await settle(t);

      final sent = adapter.where('POST', '/api/pos/orders/uuid-7/coupon').single.data as Map;
      expect(sent['code'], 'PROMO10'); // upper-cased like the Tauri modal
      expect(find.text('PROMO10 appliqué'), findsOneWidget);
      expect(find.textContaining('4 000').evaluate().isNotEmpty || find.textContaining('4 000').evaluate().isNotEmpty, isTrue);

      await t.tap(find.text('RETIRER'));
      await settle(t);
      expect(find.text('PROMO10 appliqué'), findsNothing);
    });
  });

  group('sales page', () {
    testWidgets('no open session → opening gate; opening posts the assigned register', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({'register-id': 3, 'register-name': 'Caisse 1'});
      final storage = (await t.runAsync(AppStorage.create))!;

      var open = false;
      final adapter = _Adapter((o) {
        switch ('${o.method} ${o.path}') {
          case 'GET /api/cash/status':
            return (200, open
                ? {'isOpen': true, 'session': {'id': 1, 'registerId': 3, 'registerName': 'Caisse 1', 'openingAmount': 5000, 'openedAt': '2026-10-10T08:00:00Z'}}
                : {'isOpen': false, 'session': null});
          case 'POST /api/cash/open':
            open = true;
            return (200, {'id': 1, 'registerId': 3, 'registerName': 'Caisse 1', 'openingAmount': 5000, 'openedAt': '2026-10-10T08:00:00Z'});
          case 'GET /api/pos/orders/history':
            return (200, {'status': 'success', 'data': [_order()]});
        }
        return (404, {'message': 'unexpected ${o.method} ${o.path}'});
      });

      await t.pumpWidget(ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
          sseEventsProvider.overrideWith((ref) => const Stream<SseEvent>.empty()),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: SalesPage())),
      ));
      await settle(t);

      expect(find.text('OUVERTURE DE CAISSE'), findsOneWidget);
      await t.enterText(find.byType(TextField), '5000');
      await t.tap(find.text("CONFIRMER L'OUVERTURE"));
      await settle(t);
      await settle(t);

      final body = adapter.where('POST', '/api/cash/open').single.data as Map;
      expect(body['registerId'], 3);
      expect(body['openingAmount'], 5000);

      // Gate gone: the shift list shows the order with its payable status and totals.
      expect(find.text('OUVERTURE DE CAISSE'), findsNothing);
      expect(find.text('ORD-7'), findsOneWidget);
      expect(find.text('CLÔTURER SHIFT'), findsOneWidget);

      await t.tap(find.text('ORD-7'));
      await settle(t);
      expect(find.textContaining('ENCAISSER'), findsOneWidget); // completed → payable
      expect(find.text('ANNULER TICKET'), findsOneWidget);
    });
  });
}
