import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/format.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/core/theme/app_theme.dart';
import 'package:monokek_flutter/features/pos/cart_store.dart';
import 'package:monokek_flutter/features/pos/order_page.dart';
import 'package:monokek_flutter/features/pos/stock_guard.dart';
import 'package:monokek_flutter/models/catalog.dart';
import 'package:monokek_flutter/models/ordering.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final (int, Object?) Function(RequestOptions) handler;
  final requests = <RequestOptions>[];

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

Map<String, dynamic> _order({int id = 5, List<Map<String, dynamic>> rounds = const []}) => {
      'id': id,
      'uuid': 'u-$id',
      'reference': 'ORD-$id',
      'type': 'dinein',
      'status': 'pending',
      'amounts': {'subtotal': 2500, 'tax': 0, 'discount': 0, 'total': 2500, 'formattedTotal': '2 500 FCFA', 'couponCode': null},
      'table': {'id': 4, 'name': 'T4', 'status': 'occupied'},
      'rounds': rounds,
      'time': '12:00',
      'date': '10/10/2026',
    };

Map<String, dynamic> _round1() => {
      'id': 70,
      'roundNumber': 1,
      'status': 'sent',
      'sentAt': '2026-10-10T12:00:00Z',
      'totalRound': 2500,
      'items': [
        {
          'id': 900,
          'qty': 1,
          'price': 2500,
          'total': 2500,
          'status': 'pending',
          'product': {'id': 10, 'name': 'Burger'},
          'variant': null,
          'modifiers': [],
          'formattedTotal': '2 500 FCFA',
        }
      ],
    };

const _product = Product(id: 10, name: 'Burger', price: 2500, categoryName: 'Plats', type: 'consumable', stockCount: 0, modifiers: []);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('cart store', () {
    late ProviderContainer c;
    late AppStorage storage;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await AppStorage.create();
      c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
    });
    tearDown(() => c.dispose());

    test('identical product + modifiers merge, different modifiers do not', () {
      final cart = c.read(cartProvider.notifier);
      cart.initForTable(4);
      const m = CartModifier(id: 1, name: 'Bacon', price: 500, quantity: 1);
      cart.addItem(product: _product);
      cart.addItem(product: _product);
      cart.addItem(product: _product, modifiers: [m]);
      final s = c.read(cartProvider);
      expect(s.items.length, 2);
      expect(s.items.first.qty, 2);
    });

    test('modifier extras are counted once in the line total', () {
      final cart = c.read(cartProvider.notifier);
      cart.initForTable(4);
      cart.addItem(product: _product, modifiers: [const CartModifier(id: 1, name: 'Bacon', price: 500, quantity: 2)]);
      cart.updateQty(c.read(cartProvider).items.single.id, 3);
      // (2500 + 2*500) * 3
      expect(c.read(cartProvider).total, 10500);
    });

    test('switching table resets, same table keeps the round being composed', () {
      final cart = c.read(cartProvider.notifier);
      cart.initForTable(4);
      cart.addItem(product: _product);
      cart.initForTable(4);
      expect(c.read(cartProvider).items.length, 1);
      cart.initForTable(5);
      expect(c.read(cartProvider).items, isEmpty);
    });

    test('clearItems keeps orderId; resetAfterPayment only for the exact order', () {
      final cart = c.read(cartProvider.notifier);
      cart.initForTable(4);
      cart.syncOrderId(9);
      cart.addItem(product: _product);
      cart.clearItems();
      expect(c.read(cartProvider).orderId, 9);
      cart.resetAfterPayment(123);
      expect(c.read(cartProvider).orderId, 9);
      cart.resetAfterPayment(9);
      expect(c.read(cartProvider).orderId, isNull);
    });

    test('is persisted and restored', () async {
      c.read(cartProvider.notifier)
        ..initForTable(4)
        ..addItem(product: _product);
      final restored = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
      addTearDown(restored.dispose);
      expect(restored.read(cartProvider).items.single.name, 'Burger');
    });
  });

  group('stock guard', () {
    final order = Order.fromJson(_order(rounds: [_round1()]));
    final cart = CartState(items: [CartItem(id: '10-', productId: 10, name: 'Burger', price: 2500, qty: 1, modifiers: const [])]);

    test('counts the unsent cart AND already-sent rounds', () {
      expect(qtyCommitted(10, cart, order), 2);
    });
    test('blocks a storable product at its stock limit', () {
      expect(wouldExceedStock(allowOversell: false, cart: cart, order: order, productId: 10, productType: 'storable', stockCount: 2), isTrue);
      expect(wouldExceedStock(allowOversell: false, cart: cart, order: order, productId: 10, productType: 'storable', stockCount: 3), isFalse);
    });
    test('never blocks consumables or when oversell is allowed', () {
      expect(wouldExceedStock(allowOversell: false, cart: cart, order: order, productId: 10, productType: 'consumable', stockCount: 0), isFalse);
      expect(wouldExceedStock(allowOversell: true, cart: cart, order: order, productId: 10, productType: 'storable', stockCount: 0), isFalse);
    });
  });

  test('formatCurrency uses FCFA with no decimals', () {
    expect(formatCurrency(12500).replaceAll(RegExp(r'\s'), ' '), '12 500 FCFA');
  });

  group('order page', () {
    Future<_Adapter> pump(WidgetTester tester, {required (int, Object?) Function(RequestOptions, _Adapter) onSend, Map<String, Object> prefs = const {}}) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(prefs);
      // Real async (platform channels) must run outside the fake-async test zone.
      final storage = (await tester.runAsync(AppStorage.create))!;
      late _Adapter adapter;
      adapter = _Adapter((o) {
        switch ('${o.method} ${o.path}') {
          case 'GET /api/pos/floors':
            return (200, [
              {
                'id': 1,
                'name': 'Salle',
                'tables': [
                  {'id': 4, 'name': 'T4', 'status': 'free', 'seats': 4, 'virtual': false}
                ]
              }
            ]);
          case 'GET /api/pos/products':
            return (200, [
              {'id': 10, 'name': 'Burger', 'price': 2500, 'categoryName': 'Plats', 'type': 'consumable', 'stockCount': 0, 'modifiers': []}
            ]);
          case 'GET /api/admin/settings':
            return (403, {'message': 'forbidden'});
          case 'GET /api/pos/tables/4/active-order':
            return (200, {'status': 'success', 'message': null, 'data': null, 'errors': null});
          case 'POST /api/pos/orders/send-round':
            return onSend(o, adapter);
        }
        return (404, {'message': 'unexpected ${o.method} ${o.path}'});
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
          sseEventsProvider.overrideWith((ref) => const Stream<SseEvent>.empty()),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const OrderPage(tableId: 4)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      return adapter;
    }

    testWidgets('add a product then launch the round', (tester) async {
      final adapter = await pump(tester, onSend: (_, _) => (200, {'order': _order(rounds: [_round1()]), 'skippedKitchenItems': []}));

      expect(find.text('T4'), findsWidgets); // table name resolved from the floor plan
      expect(find.text('EN ATTENTE DE COMMANDE'), findsOneWidget);

      await tester.tap(find.text('BURGER'));
      await tester.pump();
      expect(find.text('NOUVEAU ROUND'), findsOneWidget);
      expect(find.text('LANCER LE ROUND 1'), findsOneWidget);

      await tester.tap(find.text('LANCER LE ROUND 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final send = adapter.requests.singleWhere((r) => r.path == '/api/pos/orders/send-round');
      final body = send.data as Map<String, dynamic>;
      expect(body['tableId'], 4);
      expect(body.containsKey('orderId'), isFalse);
      expect((body['items'] as List).single, {'productId': 10, 'qty': 1, 'modifiers': []});

      expect(find.text('NOUVEAU ROUND'), findsNothing); // cart emptied
      expect(find.textContaining('ROUND 1 · ENVOYÉ'), findsOneWidget); // server round shown
      expect(find.text('LANCER LE ROUND 2'), findsOneWidget);
    });

    testWidgets('a stale (already paid) orderId is dropped and the round is retried once without it', (tester) async {
      final stale = jsonEncode({
        'tableId': 4,
        'orderId': 99,
        'items': [
          {'id': '10-', 'productId': 10, 'name': 'Burger', 'price': 2500, 'qty': 1, 'modifiers': []}
        ],
      });
      var attempts = 0;
      final adapter = await pump(
        tester,
        prefs: {'mono-kek-cart-storage': stale},
        onSend: (_, _) {
          attempts++;
          return attempts == 1
              ? (409, {'status': 'error', 'message': 'Cette commande est déjà payée.'})
              : (200, {'order': _order(rounds: [_round1()]), 'skippedKitchenItems': []});
        },
      );

      await tester.tap(find.text('LANCER LE ROUND 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final sends = adapter.requests.where((r) => r.path == '/api/pos/orders/send-round').toList();
      expect(sends.length, 2);
      expect((sends[0].data as Map).containsKey('orderId'), isTrue);
      expect((sends[0].data as Map)['orderId'], 99);
      expect((sends[1].data as Map).containsKey('orderId'), isFalse);
      expect(find.textContaining('ROUND 1 · ENVOYÉ'), findsOneWidget);
    });

    testWidgets('a non-stale 409 is NOT retried (would open a duplicate order)', (tester) async {
      final adapter = await pump(
        tester,
        prefs: {
          'mono-kek-cart-storage': jsonEncode({
            'tableId': 4,
            'orderId': 99,
            'items': [
              {'id': '10-', 'productId': 10, 'name': 'Burger', 'price': 2500, 'qty': 1, 'modifiers': []}
            ],
          })
        },
        onSend: (_, _) => (409, {'status': 'error', 'message': "Cette commande n'appartient pas à la table indiquée."}),
      );

      await tester.tap(find.text('LANCER LE ROUND 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(adapter.requests.where((r) => r.path == '/api/pos/orders/send-round').length, 1);
      expect(find.text('NOUVEAU ROUND'), findsOneWidget); // selection kept
    });
  });
}
