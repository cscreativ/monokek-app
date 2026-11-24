import 'package:dio/dio.dart';

import '../models/app_user.dart';

/// Branch this terminal operates in (port of lib/branch.ts): the logged-in user's own branch is
/// authoritative; only an account with none (e.g. an unscoped admin) falls back to the branch of
/// the first register. Null when nothing answers yet.
Future<int?> resolveBranchId(Dio dio, AppUser? user) async {
  final own = user?.branchId;
  if (own != null) return own;
  try {
    final res = await dio.get('/api/cash/registers');
    final list = res.data as List;
    if (list.isNotEmpty) return (list.first['branchId'] as num).toInt();
  } catch (_) {}
  return null;
}
