// Runs the app's REAL data layer (ApiClient interceptors, AuthController, PosApi, CashierApi)
// against a live monokek stack. Skipped unless LIVE_API is provided:
//   flutter test test/live_backend_test.dart \
//     --dart-define=LIVE_API=localhost:8090 --dart-define=POS_CLIENT_SECRET=...
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/data/cashier_api.dart';
import 'package:monokek_flutter/data/pos_api.dart';
import 'package:monokek_flutter/data/staffing_api.dart';
import 'package:monokek_flutter/features/auth/auth_controller.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _api = String.fromEnvironment('LIVE_API');

void main() {
  final skip = _api.isEmpty ? 'set --dart-define=LIVE_API=host:port to run' : null;

  late ProviderContainer c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'backend-ip': _api});
    final storage = await AppStorage.create();
    c = ProviderContainer(overrides: [storageProvider.overrideWithValue(storage)]);
  });
  tearDown(() => c.dispose());

  test('licence endpoint is public and parses', skip: skip, () async {
    final res = await c.read(apiClientProvider).get('/api/license/status');
    final l = LicenseStatus.fromJson(res.data as Map<String, dynamic>);
    expect(l.active, isTrue);
  });

  test('login → /api/me → authenticated state with role + branch', skip: skip, () async {
    final user = await c.read(authProvider.notifier).login('waiter@resto.com', 'password');
    expect(user.role, 'waiter');
    expect(user.branchId, 1);
    final s = c.read(authProvider);
    expect(s.isAuthenticated, isTrue);
    expect(s.refreshToken, isNotNull);

    final floors = await c.read(posApiProvider).listFloors();
    expect(floors, isNotEmpty);
    final products = await c.read(posApiProvider).listProducts();
    expect(products.length, greaterThan(10));
    expect(await c.read(posApiProvider).getActiveOrder(1), isNull);
    // a waiter cannot read admin settings → treated as "oversell not allowed"
    expect(await c.read(posApiProvider).allowOversell(), isFalse);
  });

  test('wrong password surfaces a 401 without logging out anything', skip: skip, () async {
    expect(() => c.read(authProvider.notifier).login('waiter@resto.com', 'nope'), throwsA(anything));
    expect(c.read(authProvider).isAuthenticated, isFalse);
  });

  test('expired access token is refreshed through /oauth2/token and the request is replayed', skip: skip, () async {
    await c.read(authProvider.notifier).login('cashier@resto.com', 'password');
    final before = c.read(authProvider);
    // Corrupt the access token but keep the real refresh token.
    await c.read(authProvider.notifier).setTokens('not-a-valid-jwt', before.refreshToken, 1800);

    final status = await c.read(cashierApiProvider).status(); // 401 → refresh → retry
    expect(status.isOpen, isA<bool>());

    final after = c.read(authProvider);
    expect(after.token, isNot('not-a-valid-jwt'));
    expect(after.isAuthenticated, isTrue);
  });

  test('concurrent 401s share ONE refresh (the server does not reuse refresh tokens)', skip: skip, () async {
    await c.read(authProvider.notifier).login('cashier@resto.com', 'password');
    await c.read(authProvider.notifier).setTokens('garbage', c.read(authProvider).refreshToken, 1800);
    final api = c.read(cashierApiProvider);
    final results = await Future.wait([api.status(), api.listRegisters(), api.status()]);
    expect(results.length, 3);
    expect(c.read(authProvider).isAuthenticated, isTrue);
  });

  test('cashier: registers, summary; kitchen: stations/tickets; staffing lookups', skip: skip, () async {
    await c.read(authProvider.notifier).login('cashier@resto.com', 'password');
    final regs = await c.read(cashierApiProvider).listRegisters();
    expect(regs.first.branchId, 1);
    final bar = await c.read(cashierApiProvider).barStation();
    expect(bar?.type, 'BAR');
    expect(await c.read(posApiProvider).historyPos(), isA<List>());
    expect(await c.read(posApiProvider).listOrders(), isA<List>());
    expect(await c.read(posApiProvider).roomChargeEnabled(), isTrue);
    expect(await c.read(staffingApiProvider).currentlyPresent(1), isA<List>());
  });

  test('logout clears the persisted session', skip: skip, () async {
    await c.read(authProvider.notifier).login('kitchen@resto.com', 'password');
    expect(c.read(storageProvider).session, isNotNull);
    await c.read(authProvider.notifier).logout();
    expect(c.read(authProvider).isAuthenticated, isFalse);
    expect(c.read(storageProvider).session, isNull);
  });
}
