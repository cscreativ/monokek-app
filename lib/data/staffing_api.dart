import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/envelope.dart';

class ClockUser {
  const ClockUser({required this.id, required this.name});
  final int id;
  final String name;
}

class TimeClockEntry {
  const TimeClockEntry({required this.id, required this.userId, required this.userName, required this.clockInAt});
  final int id;
  final int userId;
  final String? userName;
  final DateTime? clockInAt;

  factory TimeClockEntry.fromJson(Map<String, dynamic> j) => TimeClockEntry(
        id: (j['id'] as num).toInt(),
        userId: (j['userId'] as num).toInt(),
        userName: j['userName'] as String?,
        clockInAt: j['clockInAt'] == null ? null : DateTime.tryParse(j['clockInAt'] as String)?.toLocal(),
      );
}

/// Self-service clock-in/out on a shared terminal (ports of lib/api/staffing.ts + identity.lookupPin).
class StaffingApi {
  StaffingApi(this._dio);
  final Dio _dio;

  /// Which colleague of [branchId] owns [pin] (PINs are unique per branch).
  Future<ClockUser> lookupPin(int branchId, String pin) async {
    final r = await _dio.post('/api/auth/lookup-pin', data: {'branchId': branchId, 'pin': pin});
    final d = unwrap<Map<String, dynamic>>(r);
    return ClockUser(id: (d['id'] as num).toInt(), name: d['name'] as String? ?? '');
  }

  Future<void> clockIn(int userId, int branchId, String pin) async {
    await _dio.post('/api/staffing/clock/clock-in', data: {'userId': userId, 'branchId': branchId, 'pin': pin});
  }

  Future<void> clockOut(int userId, String pin) async {
    await _dio.post('/api/staffing/clock/clock-out', data: {'userId': userId, 'pin': pin});
  }

  Future<List<TimeClockEntry>> currentlyPresent(int branchId) async {
    final r = await _dio.get('/api/staffing/clock/current', queryParameters: {'branchId': branchId});
    return (r.data as List).map((e) => TimeClockEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final staffingApiProvider = Provider<StaffingApi>((ref) => StaffingApi(ref.watch(apiClientProvider)));
