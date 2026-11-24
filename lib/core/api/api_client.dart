import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../config.dart';
import '../storage/app_storage.dart';

/// Routes that must never carry the stored Bearer token. The resource-server filter validates any
/// Bearer it sees, even on a permitAll route, and answers 401 when it is expired: a terminal that
/// already had a session would then fail the licence check / ping / login on a perfectly reachable server.
const publicApiPaths = {'/api/ping', '/api/login', '/api/license/status'};

/// Same rule as withScheme() in mono-kep-tauri/src/lib/axios.ts: an explicit http(s) URL is kept;
/// without a scheme, the Caddy HTTPS ports (443, 8443) mean `https://`, anything else (8090, the
/// local HTTP port) means `http://`. Plain http only works in debug builds on Android (see the
/// release network security config).
String resolveBaseUrl(String? stored) {
  if (stored == null || stored.trim().isEmpty) return AppConfig.defaultApiUrl;
  final clean = stored.trim().replaceAll(RegExp(r'/+$'), '');
  if (RegExp(r'^https?://').hasMatch(clean)) return clean;
  final port = RegExp(r':(\d+)$').firstMatch(clean)?.group(1);
  return '${port == '443' || port == '8443' ? 'https' : 'http'}://$clean';
}

/// Media (product images, logo) are stored with an ABSOLUTE url baked in at upload time, e.g.
/// `http://127.0.0.1:9000/...` or the LAN address the PC had that day — unreachable from a phone as
/// soon as it points at loopback or at an address the server no longer has. Such urls are re-pointed
/// at the server this terminal is configured for (same host, the url's own port, e.g. MinIO's 9000).
/// Public hostnames (CDN, domain) are left untouched.
String resolveMediaUrl(String url, String? backendStored) {
  final media = Uri.tryParse(url);
  final backend = Uri.tryParse(resolveBaseUrl(backendStored));
  if (media == null || backend == null || media.host.isEmpty || backend.host.isEmpty) return url;
  if (media.host == backend.host) return url;

  final h = media.host;
  final local = h == 'localhost' ||
      h.startsWith('127.') ||
      h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h);
  return local ? media.replace(host: backend.host).toString() : url;
}

/// Timeouts and headers of the app's HTTP client. The setup screen's connection test uses the SAME
/// options, so "Terminal connecté" really means "the app will reach the server the way it will use it".
BaseOptions defaultClientOptions() => BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest'},
      contentType: 'application/json',
    );

/// Thrown when the server refuses the refresh_token grant for a reason that is NOT a dead session
/// (invalid_client = bad/missing POS_CLIENT_SECRET in this build): the user must not be logged out.
class RefreshConfigError implements Exception {
  RefreshConfigError(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _oauthError(DioException e) {
  final d = e.response?.data;
  return d is Map ? d['error'] as String? : null;
}

/// Single in-flight refresh_token exchange (the server rotates refresh tokens, so parallel refreshes
/// would invalidate each other). Used by the 401 interceptor and by the proactive [SessionKeeper].
class TokenRefresher {
  TokenRefresher(this._ref);
  final Ref _ref;
  Future<String>? _inFlight;

  Future<String> refresh() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<String> _run() async {
    if (AppConfig.posClientSecret.isEmpty) {
      debugPrint('[auth] POS_CLIENT_SECRET vide: build sans --dart-define, le refresh sera refuse (invalid_client).');
    }
    final current = _ref.read(authProvider).refreshToken;
    if (current == null) throw StateError('Aucun refresh token disponible.');
    final base = resolveBaseUrl(_ref.read(storageProvider).backendIp);
    DioException? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: 2 * attempt));
      try {
        // Bare client: no Bearer interceptor, no recursive refresh on 401.
        final res = await Dio(BaseOptions(
          baseUrl: base,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        )).post(
          '/oauth2/token',
          data: {'grant_type': 'refresh_token', 'refresh_token': current},
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {'Authorization': 'Basic ${_basic(AppConfig.posClientId, AppConfig.posClientSecret)}'},
          ),
        );
        final data = res.data as Map<String, dynamic>;
        final access = data['access_token'] as String;
        await _ref.read(authProvider.notifier).setTokens(
              access,
              data['refresh_token'] as String? ?? current,
              (data['expires_in'] as num?)?.toInt() ?? 1800,
            );
        return access;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        debugPrint('[auth] refresh echoue: status=$status error=${_oauthError(e)} type=${e.type}');
        if (status == null) {
          last = e; // network not back yet (wake-up, timeout): retry, never conclude the session is dead
          continue;
        }
        if (_oauthError(e) == 'invalid_client' || (status == 401 && _oauthError(e) == null)) {
          throw RefreshConfigError('Client OAuth refuse (invalid_client): verifier POS_CLIENT_SECRET du build.');
        }
        // Someone else rotated the pair while this exchange was in flight (another refresh path, a
        // re-login): the token we sent is stale but the session is alive. Use what is stored now.
        final stored = _ref.read(authProvider);
        if (_oauthError(e) == 'invalid_grant' && stored.refreshToken != null && stored.refreshToken != current && stored.token != null) {
          return stored.token!;
        }
        rethrow; // 400 invalid_grant => dead session, decided by the caller
      }
    }
    throw last!;
  }

  /// Refreshes if the access token expires within [margin]. Never logs out by itself.
  Future<void> refreshIfNeeded({Duration margin = const Duration(minutes: 5)}) async {
    final a = _ref.read(authProvider);
    if (a.refreshToken == null || a.expiresAt == null) return;
    if (a.expiresAt!.difference(DateTime.now()) > margin) return;
    try {
      await refresh();
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 && _oauthError(e) == 'invalid_grant') {
        await _ref.read(authProvider.notifier).logout(remote: false);
      }
    } catch (_) {/* transient or config error: the 401 path will retry / surface it */}
  }
}

final tokenRefresherProvider = Provider<TokenRefresher>(TokenRefresher.new);

/// Shared HTTP client: dynamic base URL, Bearer token, and refresh on 401 (see [TokenRefresher]).
final apiClientProvider = Provider<Dio>((ref) {
  final storage = ref.read(storageProvider);
  final dio = Dio(defaultClientOptions());

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      options.baseUrl = resolveBaseUrl(storage.backendIp);
      final token = ref.read(authProvider).token;
      // Never send a (possibly expired) Bearer to public routes (see [publicApiPaths]); for /api/login
      // this is what made re-login impossible after a long sleep.
      if (token != null && !publicApiPaths.contains(options.path) && !options.headers.containsKey('Authorization')) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      final req = error.requestOptions;
      // A public route has no session to refresh or drop: surface its own error untouched.
      if (publicApiPaths.contains(req.path)) return handler.next(error);
      final is401 = error.response?.statusCode == 401;
      // A 401 on an already-retried request (fresh token) is that endpoint's problem, not a dead
      // session: surface it, do NOT log the whole terminal out.
      if (!is401 || req.extra['retried'] == true) return handler.next(error);
      final auth = ref.read(authProvider);
      if (auth.refreshToken == null) {
        if (auth.token != null) await ref.read(authProvider.notifier).logout(remote: false);
        return handler.next(error);
      }
      req.extra['retried'] = true;

      // Another request may already have refreshed since this one left: reuse the newer token.
      final sent = (req.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
      String? token = auth.token != null && auth.token != sent ? auth.token : null;
      if (token == null) {
        try {
          token = await ref.read(tokenRefresherProvider).refresh();
        } on DioException catch (e) {
          // Only an explicit invalid_grant (expired / revoked / already rotated token) kills the session.
          if (e.response?.statusCode == 400 && _oauthError(e) == 'invalid_grant') {
            await ref.read(authProvider.notifier).logout(remote: false);
          }
          return handler.next(error);
        } catch (_) {
          // Config error (invalid_client), no refresh token... keep the session, surface the 401.
          return handler.next(error);
        }
      }
      try {
        req.headers['Authorization'] = 'Bearer $token';
        handler.resolve(await dio.fetch(req));
      } on DioException catch (e) {
        handler.next(e);
      }
    },
  ));

  return dio;
});

String _basic(String user, String pass) => base64Encode(utf8.encode('$user:$pass'));
