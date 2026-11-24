import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/envelope.dart';
import '../models/catalog.dart';
import '../models/floorplan.dart';
import '../models/ordering.dart';

/// Waiter/cashier-facing endpoints (ports of lib/api/{floorplan,catalog,ordering,identity}.ts).
class PosApi {
  PosApi(this._dio);
  final Dio _dio;

  List<T> _list<T>(Response<dynamic> r, T Function(Map<String, dynamic>) f) =>
      (r.data as List).map((e) => f(e as Map<String, dynamic>)).toList();

  Future<List<Floor>> listFloors() async => _list(await _dio.get('/api/pos/floors'), Floor.fromJson);

  Future<List<Product>> listProducts() async => _list(await _dio.get('/api/pos/products'), Product.fromJson);

  /// Setting "Vente en stock insuffisant". Admin-only endpoint: any failure means "not allowed".
  Future<bool> allowOversell() async {
    try {
      final r = await _dio.get('/api/admin/settings');
      return (r.data as Map)['allow_oversell'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Enveloped; `data` is null when the table has no open order.
  Future<Order?> getActiveOrder(int tableId) async {
    final r = await _dio.get('/api/pos/tables/$tableId/active-order');
    final data = unwrap<Object?>(r);
    return data is Map<String, dynamic> && data['id'] != null ? Order.fromJson(data) : null;
  }

  Future<SendRoundResult> sendRound({
    required int tableId,
    int? orderId,
    required List<Map<String, dynamic>> items,
    String note = '',
    String? clientRequestId,
  }) async {
    final r = await _dio.post('/api/pos/orders/send-round', data: {
      'tableId': tableId,
      'orderId': ?orderId,
      'items': items,
      'note': note,
      // Same value on every retry of the same send: the server answers with the first result instead of
      // raising a second round (and a second kitchen ticket) when a response was lost.
      'clientRequestId': ?clientRequestId,
    });
    final body = r.data as Map<String, dynamic>;
    final skipped = ((body['skippedKitchenItems'] as List?) ?? const []).map((e) => (e as Map)['productName'] as String? ?? '').where((n) => n.isNotEmpty).toList();
    return SendRoundResult(Order.fromJson(body['order'] as Map<String, dynamic>), skipped);
  }

  Future<Order> updateRoundItemQty(int roundId, int itemId, int qty) async {
    final r = await _dio.patch('/api/pos/rounds/$roundId/items/$itemId', data: {'qty': qty});
    return Order.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> transferTable(int fromTableId, int toTableId) async {
    await _dio.post('/api/pos/tables/transfer', data: {'fromTableId': fromTableId, 'toTableId': toTableId});
  }

  Future<List<Order>> waiterOrders({String? date, String? status}) async {
    final r = await _dio.get('/api/pos/waiter/orders', queryParameters: {
      'date': ?date,
      'status': ?status,
    });
    return _list(r, Order.fromJson);
  }

  Future<void> markAsServed(int orderId) async {
    await _dio.post('/api/pos/orders/$orderId/serve');
  }

  // --- Cashier: order history, payment, coupon, cancel/void ---

  /// Shift view: every order of the current session (enveloped list).
  Future<List<Order>> historyPos() async {
    final r = await _dio.get('/api/pos/orders/history');
    return (unwrap<List<dynamic>>(r)).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Order history with filters (bare Spring page).
  Future<List<Order>> listOrders({String? search, String? date, String? status}) async {
    final r = await _dio.get('/api/pos/orders', queryParameters: {'search': ?search, 'date': ?date, 'status': ?status});
    return unwrapRawPage(r).map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Returns the server's confirmation message.
  ///
  /// Either one [method] + [amountReceived] (whole total on a single method), or a split settlement in
  /// [payments] — `amount` is the share of the bill the method settles, `amountReceived` what was handed
  /// over (only cash may exceed its share; the change comes back on it).
  Future<String?> finalizePayment(
    String uuid, {
    String? method,
    double? amountReceived,
    String? roomNumber,
    List<({String method, double amount, double amountReceived})>? payments,
  }) async {
    final r = await _dio.post('/api/pos/orders/$uuid/finalize', data: {
      'paymentMethod': ?method,
      'amountReceived': ?amountReceived,
      'roomNumber': ?roomNumber,
      if (payments != null)
        'payments': [
          for (final p in payments) {'method': p.method, 'amount': p.amount, 'amountReceived': p.amountReceived},
        ],
    });
    unwrap<Object?>(r);
    return (r.data as Map)['message'] as String?;
  }

  Future<Order> applyCoupon(String uuid, String code) async {
    final r = await _dio.post('/api/pos/orders/$uuid/coupon', data: {'code': code});
    return Order.fromJson(r.data as Map<String, dynamic>);
  }

  Future<Order> removeCoupon(String uuid) async {
    final r = await _dio.delete('/api/pos/orders/$uuid/coupon');
    return Order.fromJson(r.data as Map<String, dynamic>);
  }

  /// Pre-payment lookup so the till can confirm the guest's name before billing a room.
  Future<({int bookingId, String guestName})> checkRoom(String roomNumber) async {
    final r = await _dio.get('/api/pos/rooms/${Uri.encodeComponent(roomNumber)}');
    final d = unwrap<Map<String, dynamic>>(r);
    return (bookingId: (d['bookingId'] as num).toInt(), guestName: d['guestName'] as String? ?? '');
  }

  /// "Chambre" payment is only offered when the hotel integration is enabled (global setting).
  Future<bool> roomChargeEnabled() async {
    try {
      final r = await _dio.get('/api/admin/settings');
      return (r.data as Map)['room_charge_enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Voids an unpaid order — always needs a manager PIN, verified server-side.
  Future<void> cancelOrder(String uuid, String reason, String managerPin) async {
    final r = await _dio.post('/api/pos/orders/$uuid/cancel', data: {'reason': reason, 'managerPin': managerPin});
    unwrap<Object?>(r);
  }

  /// Removes one round from a still-open order (same manager-PIN override, round granularity).
  Future<Order> voidRound(int roundId, String reason, String managerPin) async {
    final r = await _dio.post('/api/pos/rounds/$roundId/void', data: {'reason': reason, 'managerPin': managerPin});
    return Order.fromJson(r.data as Map<String, dynamic>);
  }

  Future<void> reprint(int orderId) async {
    await _dio.post('/api/sales/$orderId/reprint');
  }

  Future<void> updatePin(String pin) async {
    await _dio.post('/api/auth/update-pin', data: {'pin': pin});
  }

  Future<void> updatePassword(String oldPassword, String newPassword) async {
    await _dio.post('/api/auth/update-password', data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
      'newPasswordConfirmation': newPassword,
    });
  }
}

final posApiProvider = Provider<PosApi>((ref) => PosApi(ref.watch(apiClientProvider)));
