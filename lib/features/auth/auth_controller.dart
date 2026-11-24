import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/envelope.dart';
import '../../core/storage/app_storage.dart';
import '../../models/app_user.dart';

class AuthState {
  const AuthState({this.user, this.token, this.refreshToken, this.expiresAt});

  final AppUser? user;
  final String? token;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get isAuthenticated => token != null && user != null;

  factory AuthState.fromJson(Map<String, dynamic> j) => AuthState(
        user: j['user'] == null ? null : AppUser.fromJson(j['user'] as Map<String, dynamic>),
        token: j['token'] as String?,
        refreshToken: j['refreshToken'] as String?,
        expiresAt: j['expiresAt'] == null ? null : DateTime.tryParse(j['expiresAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'user': user?.toJson(),
        'token': token,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt?.toIso8601String(),
      };
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final saved = ref.read(storageProvider).session;
    return saved == null ? const AuthState() : AuthState.fromJson(saved);
  }

  /// POST /api/login then GET /api/me for roles/permissions — same two-step flow as use-auth.ts.
  /// Throws; the caller shows [errorMessage].
  Future<AppUser> login(String email, String password) async {
    final dio = ref.read(apiClientProvider);
    final res = await dio.post('/api/login', data: {
      'email': email,
      'password': password,
      'deviceName': 'Flutter POS Terminal',
    });
    final data = unwrap<Map<String, dynamic>>(res);
    final token = data['token'] as String;
    final summary = data['user'] as Map<String, dynamic>;

    // Pass the token explicitly: state isn't written yet, so the interceptor has nothing to attach.
    final me = await dio.get('/api/me', options: Options(headers: {'Authorization': 'Bearer $token'}));
    final staff = me.data as Map<String, dynamic>;

    final user = AppUser(
      id: (summary['id'] as num).toInt(),
      uuid: staff['uuid'] as String? ?? '',
      name: summary['name'] as String? ?? '',
      role: summary['role'] as String? ?? 'waiter',
      permissions: (staff['permissions'] as List?)?.cast<String>() ?? const [],
      branchId: (staff['branchId'] as num?)?.toInt(),
    );
    await _persist(AuthState(
      user: user,
      token: token,
      refreshToken: data['refreshToken'] as String?,
      expiresAt: DateTime.now().add(Duration(seconds: (data['expiresInSeconds'] as num?)?.toInt() ?? 1800)),
    ));
    return user;
  }

  /// Swaps in a fresh token pair after a silent refresh; leaves the user untouched.
  Future<void> setTokens(String token, String? refreshToken, int expiresInSeconds) => _persist(AuthState(
        user: state.user,
        token: token,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: expiresInSeconds)),
      ));

  /// [remote] = also tell the server; skipped when the session is already dead.
  Future<void> logout({bool remote = true}) async {
    if (remote && state.token != null) {
      try {
        await ref.read(apiClientProvider).post('/api/logout');
      } catch (_) {}
    }
    await ref.read(storageProvider).clearSession();
    state = const AuthState();
  }

  Future<void> _persist(AuthState next) async {
    await ref.read(storageProvider).saveSession(next.toJson());
    state = next;
  }
}
