// Split payment ("paiement partage") against a live monokek stack, through the app's real data layer.
// Creates ONE order on a virtual table and pays it; leaves a cash session open if none was.
//   flutter test test/split_payment_live_test.dart --dart-define=LIVE_API=127.0.0.1:8090
// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/data/cashier_api.dart';
import 'package:monokek_flutter/data/pos_api.dart';
import 'package:monokek_flutter/features/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _api = String.fromEnvironment('LIVE_API');

void main() {
  final skip = _api.isEmpty ? 'set --dart-define=LIVE_API=host:port to run' : null;

  test('cash + momo on one bill: bad sums rejected, exact split accepted, double pay refused', skip: skip, () async {
    SharedPreferences.setMockInitialValues({'backend-ip': _api});
    final c = ProviderContainer(overrides: [storageProvider.overrideWithValue(await AppStorage.create())]);
    addTearDown(c.dispose);

    await c.read(authProvider.notifier).login('cashier@resto.com', 'password');
    final cashier = c.read(cashierApiProvider);
    final pos = c.read(posApiProvider);

    final status = await cashier.status();
    if (!status.isOpen) {
      final regs = await cashier.listRegisters();
      await cashier.open(regs.first.id, 0);
    }

    final floors = await pos.listFloors();
    final table = floors.expand((f) => f.tables).firstWhere((t) => t.virtual, orElse: () => floors.first.tables.first);
    final products = await pos.listProducts();
    final candidates = products.where((p) => p.type != 'storable' && p.price > 0).toList()
      ..sort((a, b) => a.modifiers.length.compareTo(b.modifiers.length));
    final product = candidates.first;
    // First item(s) of every group that demands a selection, like a waiter would tap them.
    final modifiers = [
      for (final g in product.modifiers.where((g) => g.effectiveMin > 0))
        for (final m in g.items.take(g.effectiveMin)) {'modifierItemId': m.id, 'quantity': 1},
    ];
    print('table=${table.name} product=${product.name} price=${product.price}');

    final sent = await pos.sendRound(
      tableId: table.id,
      items: [
        {'productId': product.id, 'qty': 3, 'modifiers': modifiers},
      ],
    ).catchError((Object e) {
      if (e is DioException) print('sendRound ${e.response?.statusCode}: ${e.response?.data}');
      throw e;
    });
    final order = sent.order;
    final total = order.total;
    print('order ${order.id} total=$total');
    expect(total, greaterThan(0));

    final cashShare = (total * 0.6).roundToDouble();
    final momoShare = total - cashShare;

    // 1) Parts that don't cover the total -> 400, order stays unpaid.
    await expectLater(
      pos.finalizePayment(order.uuid, payments: [
        (method: 'cash', amount: cashShare, amountReceived: cashShare),
        (method: 'momo', amount: momoShare - 1, amountReceived: momoShare - 1),
      ]),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 400)),
    );

    // 2) MoMo handing over more than its share -> 400.
    await expectLater(
      pos.finalizePayment(order.uuid, payments: [
        (method: 'cash', amount: cashShare, amountReceived: cashShare),
        (method: 'momo', amount: momoShare, amountReceived: momoShare + 500),
      ]),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 400)),
    );

    // 3) Exact split, cash handed over rounded up -> accepted.
    final message = await pos.finalizePayment(order.uuid, payments: [
      (method: 'cash', amount: cashShare, amountReceived: cashShare + 1000),
      (method: 'momo', amount: momoShare, amountReceived: momoShare),
    ]);
    print('finalize -> $message');

    // 4) Paying again -> 409.
    await expectLater(
      pos.finalizePayment(order.uuid, method: 'cash', amountReceived: total),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 409)),
    );

    final paid = (await pos.historyPos()).firstWhere((o) => o.id == order.id);
    print('status after payment: ${paid.status}');
    print('ORDER_ID=${order.id}');
  });
}
