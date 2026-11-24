import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../models/cashier.dart';
import '../models/kitchen.dart';

/// Cash register / session / bar-counter endpoints (ports of lib/api/cashier.ts + kitchenStation.ts).
/// All of these answer with bare DTOs (no `{status,data}` envelope).
class CashierApi {
  CashierApi(this._dio);
  final Dio _dio;

  Future<List<CashRegister>> listRegisters() async {
    final r = await _dio.get('/api/cash/registers');
    return (r.data as List).map((e) => CashRegister.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<CashStatus> status() async {
    final r = await _dio.get('/api/cash/status');
    return CashStatus.fromJson(r.data as Map<String, dynamic>);
  }

  Future<CashSession> open(int registerId, double openingAmount) async {
    final r = await _dio.post('/api/cash/open', data: {'registerId': registerId, 'openingAmount': openingAmount});
    return CashSession.fromJson(r.data as Map<String, dynamic>);
  }

  Future<CashSummary> currentSummary() async {
    final r = await _dio.get('/api/cash/current-summary');
    return CashSummary.fromJson(r.data as Map<String, dynamic>);
  }

  Future<CloseReport> close(double closingAmount, String? note) async {
    final r = await _dio.post('/api/cash/close', data: {'closingAmount': closingAmount, 'note': note});
    return CloseReport.fromJson(r.data as Map<String, dynamic>);
  }

  // --- Bar counter ("Comptoir") ---

  /// Resolves the branch's BAR station instead of a hard-coded id.
  Future<KitchenStation?> barStation() async {
    final r = await _dio.get('/api/kitchen/stations');
    final list = (r.data as List).map((e) => KitchenStation.fromJson(e as Map<String, dynamic>));
    return list.where((s) => s.type == 'BAR').firstOrNull;
  }

  Future<List<KitchenTicket>> stationTickets(int stationId) async {
    final r = await _dio.get('/api/kitchen/tickets', queryParameters: {'stationId': stationId});
    return (r.data as List).map((e) => KitchenTicket.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Counter tickets skip the kitchen flow, hence the `tickets-direct` endpoint.
  Future<void> setDirectTicketStatus(int ticketId, String status) async {
    await _dio.patch('/api/kitchen/tickets-direct/$ticketId/status', data: {'status': status});
  }
}

final cashierApiProvider = Provider<CashierApi>((ref) => CashierApi(ref.watch(apiClientProvider)));
