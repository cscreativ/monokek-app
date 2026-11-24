import 'package:dio/dio.dart';

import '../api/api_client.dart';

/// Connection test of the setup screen: the same two calls the app makes at start-up, with the app's
/// own timeouts and no Bearer token. `/api/ping` proves the server answers; `/api/license/status` is
/// what [LicenseGuard] calls first, so a server that pings but fails there is reported at setup time
/// instead of leaving the terminal stuck on a guard screen afterwards.
///
/// A 403 on the licence route is accepted: the server is reachable and the guard shows its own
/// "licence" screen. Any other failure throws (a [DioException] for network, certificate and HTTP errors).
Future<void> verifyServer(String base, {Dio? dio}) async {
  final client = dio ?? Dio(defaultClientOptions());
  final pong = await client.get('$base/api/ping');
  final data = pong.data;
  if (data is! Map || data['status'] != 'ok') throw const FormatException('Réponse invalide du serveur');
  await client.get('$base/api/license/status', options: Options(validateStatus: (s) => s == 200 || s == 403));
}

/// Host + port of a server address, ignoring the scheme: switching http↔https on the same machine
/// is not a different server (the session stays valid), another host or port is.
String serverIdentity(String? stored) {
  final uri = Uri.tryParse(resolveBaseUrl(stored));
  if (uri == null) return '';
  return '${uri.host}:${uri.hasPort ? uri.port : ''}';
}
