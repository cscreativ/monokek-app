import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/router/app_router.dart';
import 'package:monokek_flutter/core/sse/notifications_service.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/core/theme/app_theme.dart';
import 'package:monokek_flutter/features/auth/auth_controller.dart';
import 'package:monokek_flutter/features/auth/login_page.dart';
import 'package:monokek_flutter/features/cashier/payment_dialog.dart';
import 'package:monokek_flutter/features/cashier/sales_page.dart';
import 'package:monokek_flutter/features/pos/order_page.dart';
import 'package:monokek_flutter/models/ordering.dart';
import 'package:monokek_flutter/features/clock/clock_page.dart';
import 'package:monokek_flutter/features/kitchen/kitchen_dashboard_page.dart';
import 'package:monokek_flutter/features/waiter/tables_page.dart';
import 'package:monokek_flutter/features/waiter/waiter_shell.dart';
import 'package:monokek_flutter/models/app_user.dart';
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
    return ResponseBody.fromString(body is String ? body : jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [body is String ? 'text/event-stream' : 'application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthController {
  _FakeAuth(this.role);
  final String role;
  @override
  AuthState build() => AuthState(
        user: AppUser(id: 3, uuid: 'u', name: 'Awa Diop', role: role, branchId: 1),
        token: 't',
      );
}

Map<String, dynamic> _order() => {
      'id': 7,
      'uuid': 'uuid-7',
      'reference': 'ORD-7',
      'type': 'dinein',
      'status': 'completed',
      'amounts': {'subtotal': 5000, 'tax': 0, 'discount': 0, 'total': 5000, 'formattedTotal': '5 000 FCFA', 'couponCode': null},
      'table': {'id': 4, 'name': 'T4', 'status': 'billing'},
      'waiter': {'id': 3, 'name': 'Awa'},
      'rounds': [],
      'time': '12:00',
      'date': '10/10/2026',
    };

final _floors = [
  {
    'id': 1,
    'name': 'Salle principale',
    'tables': [
      for (var i = 1; i <= 6; i++) {'id': i, 'name': 'Table $i', 'status': i == 2 ? 'occupied' : (i == 3 ? 'billing' : 'free'), 'seats': 4, 'virtual': false}
    ],
  },
  {'id': 2, 'name': 'Terrasse', 'tables': []},
];

(int, Object?) _api(RequestOptions o) {
  switch ('${o.method} ${o.path}') {
    case 'GET /api/pos/floors':
      return (200, _floors);
    case 'GET /api/cash/status':
      return (200, {'isOpen': true, 'session': {'id': 1, 'registerId': 3, 'registerName': 'Caisse 1', 'openingAmount': 5000, 'openedAt': '2026-10-10T08:00:00Z'}});
    case 'GET /api/pos/orders/history':
      return (200, {'status': 'success', 'data': [_order()]});
    case 'GET /api/pos/products':
      return (200, [
        for (var i = 1; i <= 8; i++)
          {'id': i, 'name': 'Produit numéro $i très long', 'price': 2500 * i, 'categoryName': i.isEven ? 'Plats' : 'Boissons', 'type': 'consumable', 'stockCount': 0, 'modifiers': []}
      ]);
    case 'GET /api/pos/tables/4/active-order':
      return (200, {'status': 'success', 'data': _order()});
    case 'GET /api/admin/settings':
      return (200, {'room_charge_enabled': true});
    case 'GET /api/kitchen/stations':
      return (200, [
        {'id': 1, 'branchId': 1, 'name': 'Grill principal', 'type': 'GRILL', 'pendingTicketsCount': 3},
        {'id': 2, 'branchId': 1, 'name': 'Bar & boissons', 'type': 'BAR', 'pendingTicketsCount': 0},
      ]);
  }
  return (404, {'message': 'unexpected ${o.method} ${o.path}'});
}

Future<ProviderScope> _scope(WidgetTester t, Widget child, {String role = 'waiter', _Adapter? adapter, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = (await t.runAsync(AppStorage.create))!;
  final a = adapter ?? _Adapter(_api);
  return ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = a),
      authProvider.overrideWith(() => _FakeAuth(role)),
      sseEventsProvider.overrideWith((ref) => const Stream<SseEvent>.empty()),
      sseConnectedProvider.overrideWith((ref) => Stream.value(true)),
    ],
    child: MaterialApp(theme: buildTheme(Brightness.light), home: child),
  );
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('resolveMediaUrl', () {
    const server = '192.168.1.139:8090';
    test('loopback / localhost / stale private IPs are re-pointed at the configured server', () {
      expect(resolveMediaUrl('http://127.0.0.1:9000/monokek/products/a.png', server), 'http://192.168.1.139:9000/monokek/products/a.png');
      expect(resolveMediaUrl('http://localhost:9000/m/a.png', server), 'http://192.168.1.139:9000/m/a.png');
      expect(resolveMediaUrl('http://192.168.1.111:9000/m/a.png', server), 'http://192.168.1.139:9000/m/a.png');
      expect(resolveMediaUrl('http://10.0.0.5:9000/m/a.png', server), 'http://192.168.1.139:9000/m/a.png');
      expect(resolveMediaUrl('http://172.20.1.2:9000/m/a.png', server), 'http://192.168.1.139:9000/m/a.png');
    });
    test('already-correct and public urls are untouched', () {
      expect(resolveMediaUrl('http://192.168.1.139:9000/m/a.png', server), 'http://192.168.1.139:9000/m/a.png');
      expect(resolveMediaUrl('https://cdn.example.com/m/a.png', server), 'https://cdn.example.com/m/a.png');
      expect(resolveMediaUrl('http://172.32.0.1:9000/m/a.png', server), 'http://172.32.0.1:9000/m/a.png'); // outside 172.16/12
    });
    test('query strings (presigned urls) and ports survive', () {
      expect(resolveMediaUrl('http://127.0.0.1:9000/b/k.png?X-Amz-Signature=abc&e=1', server), 'http://192.168.1.139:9000/b/k.png?X-Amz-Signature=abc&e=1');
    });
  });

  group('router', () {
    String? r(String loc, String role) => computeRedirect(location: loc, hasBackend: true, authenticated: true, role: role);
    test('the clock kiosk is open to every supported role', () {
      for (final role in ['kitchen', 'waiter', 'cashier']) {
        expect(r('/pos/clock', role), isNull, reason: role);
      }
    });
  });

  group('SSE connection', () {
    test('reports connected while streaming, parses events, then disconnects on stream end', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await AppStorage.create();
      final adapter = _Adapter((o) {
        if (o.path == '/api/sse/ticket') return (200, {'ticket': 'abc'});
        if (o.path == '/api/sse/stream') return (200, 'event: order.created\ndata: {"orderId":9}\n\n');
        return (404, {});
      });
      final c = ProviderContainer(overrides: [
        storageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = adapter),
        authProvider.overrideWith(() => _FakeAuth('waiter')),
      ]);
      addTearDown(c.dispose);

      final service = c.read(notificationsProvider);
      final states = <bool>[];
      service.connection.listen(states.add);
      final event = await service.events.first.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(event.name, 'order.created');
      expect(event.map['orderId'], 9);
      expect(adapter.where('POST', '/api/sse/ticket').first.queryParameters['branchId'], 1);
      expect(adapter.where('GET', '/api/sse/stream').first.queryParameters['ticket'], 'abc');
      expect(states, [true, false]); // open, then closed when the server ended the stream
    });
  });

  group('clock kiosk', () {
    testWidgets('unknown colleague → clock-in; already present → clock-out', (t) async {
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      var present = <Map<String, Object?>>[];
      final adapter = _Adapter((o) {
        switch ('${o.method} ${o.path}') {
          case 'GET /api/staffing/clock/current':
            return (200, present);
          case 'POST /api/auth/lookup-pin':
            final pin = (o.data as Map)['pin'];
            return pin == '1234' ? (200, {'status': 'success', 'data': {'id': 42, 'name': 'Moussa', 'role': 'waiter'}}) : (401, {'message': 'Code PIN invalide'});
          case 'POST /api/staffing/clock/clock-in':
            present = [
              {'id': 1, 'userId': 42, 'userName': 'Moussa', 'branchId': 1, 'clockInAt': '2026-10-10T08:15:00Z'}
            ];
            return (200, {});
          case 'POST /api/staffing/clock/clock-out':
            present = [];
            return (200, {});
        }
        return (404, {'message': 'unexpected ${o.method} ${o.path}'});
      });

      await t.pumpWidget(await _scope(t, const ClockPage(), adapter: adapter));
      await _settle(t);
      expect(find.text("Aucun employé n'est actuellement pointé"), findsOneWidget);
      expect(adapter.where('GET', '/api/staffing/clock/current').first.queryParameters['branchId'], 1);

      Future<void> type(String pin) async {
        for (final d in pin.split('')) {
          await t.tap(find.widgetWithText(OutlinedButton, d));
          await t.pump();
        }
        await _settle(t);
      }

      await type('1234');
      final inBody = adapter.where('POST', '/api/staffing/clock/clock-in').single.data as Map;
      expect(inBody, {'userId': 42, 'branchId': 1, 'pin': '1234'}); // the server re-verifies the PIN
      expect(find.text('MOUSSA A POINTÉ SON ENTRÉE'), findsOneWidget);
      expect(find.text('1 EMPLOYÉ PRÉSENT'), findsOneWidget);

      await type('1234');
      expect(adapter.where('POST', '/api/staffing/clock/clock-out').single.data, {'userId': 42, 'pin': '1234'});
      expect(find.text('MOUSSA A POINTÉ SA SORTIE'), findsOneWidget);
      expect(find.text('0 EMPLOYÉ PRÉSENT'), findsOneWidget);
    });

    testWidgets('a wrong PIN shows the server message and resets the entry', (t) async {
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);

      final adapter = _Adapter((o) {
        if (o.path == '/api/staffing/clock/current') return (200, []);
        if (o.path == '/api/auth/lookup-pin') return (401, {'message': 'Code PIN invalide'});
        return (404, {});
      });
      await t.pumpWidget(await _scope(t, const ClockPage(), adapter: adapter));
      await _settle(t);

      for (final d in ['9', '9', '9', '9']) {
        await t.tap(find.widgetWithText(OutlinedButton, d));
        await t.pump();
      }
      await _settle(t);

      expect(find.text('Code PIN invalide'), findsOneWidget);
      expect(adapter.where('POST', '/api/staffing/clock/clock-in'), isEmpty);
      expect(find.text('•'), findsNothing); // the 4 dots were cleared
    });
  });

  // Overflow in a layout throws in tests, so pumping each screen at phone and tablet sizes is a layout check.
  group('responsive layouts (no overflow)', () {
    const phone = Size(360, 740);
    const tablet = Size(900, 1280);

    for (final size in [phone, tablet]) {
      final label = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('waiter shell + floor plan @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final router = GoRouter(initialLocation: '/pos/tables', routes: [
          ShellRoute(
            builder: (_, _, child) => WaiterShell(child: child),
            routes: [GoRoute(path: '/pos/tables', builder: (_, _) => const TablesPage())],
          ),
        ]);
        final scope = await _scope(t, const SizedBox());
        await t.pumpWidget(ProviderScope(
          overrides: scope.overrides,
          child: MaterialApp.router(theme: buildTheme(Brightness.light), routerConfig: router),
        ));
        await _settle(t);
        expect(find.text('Table 2'), findsOneWidget);
        expect(find.text('OCCUPÉE'), findsOneWidget);
        expect(find.text('ADDITION'), findsOneWidget);
      });

      testWidgets('cashier shell + shift screen @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final router = GoRouter(initialLocation: '/pos/sales/order', routes: [
          ShellRoute(
            builder: (_, _, child) => WaiterShell(tabs: cashierTabs, showLogout: true, registerName: 'Caisse 1', child: child),
            routes: [GoRoute(path: '/pos/sales/order', builder: (_, _) => const SalesPage())],
          ),
        ]);
        final scope = await _scope(t, const SizedBox(), role: 'cashier');
        await t.pumpWidget(ProviderScope(
          overrides: scope.overrides,
          child: MaterialApp.router(theme: buildTheme(Brightness.light), routerConfig: router),
        ));
        await _settle(t); // cash status first,
        await _settle(t); // then the shift's orders
        expect(find.text('ORD-7'), findsOneWidget);
        expect(find.textContaining('CLÔTURER'), findsOneWidget); // shortened on very narrow screens
      });

      testWidgets('kitchen dashboard @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(await _scope(t, const KitchenDashboardPage(), role: 'kitchen'));
        await _settle(t);
        expect(find.text('GRILL PRINCIPAL'), findsOneWidget);
        expect(find.text('3 EN ATTENTE'), findsOneWidget);
      });

      testWidgets('order page (+ cart sheet on phone) @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(await _scope(t, const OrderPage(tableId: 4)));
        await _settle(t);
        await _settle(t);
        expect(find.textContaining('PRODUIT NUMÉRO 1'), findsOneWidget);
        if (size.width < 1000) {
          await t.tap(find.byIcon(Icons.shopping_cart).evaluate().isNotEmpty ? find.byIcon(Icons.shopping_cart) : find.byType(InkWell).at(2));
          await _settle(t);
        }
      });

      testWidgets('payment dialog @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final order = Order.fromJson(_order());
        await t.pumpWidget(await _scope(
          t,
          Scaffold(body: Dialog(insetPadding: const EdgeInsets.all(8), child: PaymentView(order: order))),
        ));
        await _settle(t);
        expect(find.text('VALIDER'), findsOneWidget);
      });

      testWidgets('login @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(await _scope(t, const LoginPage()));
        await _settle(t);
        expect(find.text('SE CONNECTER'), findsOneWidget);
      });

      testWidgets('clock kiosk @ $label', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final adapter = _Adapter((o) => o.path == '/api/staffing/clock/current'
            ? (200, [
                for (var i = 0; i < 5; i++) {'id': i, 'userId': i, 'userName': 'Employé numéro $i avec un nom très long', 'branchId': 1, 'clockInAt': '2026-10-10T08:15:00Z'}
              ])
            : (404, {}));
        await t.pumpWidget(await _scope(t, const ClockPage(), adapter: adapter));
        await _settle(t);
        expect(find.text('5 EMPLOYÉS PRÉSENTS'), findsOneWidget);
      });
    }
  });
}
