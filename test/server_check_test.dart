import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/net/server_check.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);
  final Map<String, (int, Object?)> routes;
  final calls = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    calls.add(o);
    final (status, body) = routes[o.uri.path] ?? (404, {'message': 'not found'});
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Adapter a) => Dio()..httpClientAdapter = a;

void main() {
  const ok = (200, {'status': 'ok'});
  const licenseOk = (200, {'active': true, 'expired': false});

  test('ping + licence OK: the connection test passes and sends no Authorization header', () async {
    final a = _Adapter({'/api/ping': ok, '/api/license/status': licenseOk});
    await verifyServer('http://srv', dio: _dio(a));
    expect(a.calls.map((r) => r.uri.path), ['/api/ping', '/api/license/status']);
    expect(a.calls.every((r) => !r.headers.containsKey('Authorization')), isTrue);
  });

  test('a server that pings but fails the licence check is reported at setup time', () async {
    final a = _Adapter({'/api/ping': ok, '/api/license/status': (502, {})});
    await expectLater(
      verifyServer('http://srv', dio: _dio(a)),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 502)),
    );
  });

  test('403 on the licence route is accepted (the guard shows its own licence screen)', () async {
    final a = _Adapter({'/api/ping': ok, '/api/license/status': (403, {})});
    await verifyServer('http://srv', dio: _dio(a));
  });

  test('an invalid ping answer is refused', () async {
    final a = _Adapter({'/api/ping': (200, {'status': 'ko'})});
    await expectLater(verifyServer('http://srv', dio: _dio(a)), throwsA(isA<FormatException>()));
  });

  test('serverIdentity ignores the scheme but not host or port', () {
    expect(serverIdentity('https://192.168.3.20:8443'), serverIdentity('192.168.3.20:8443'));
    expect(serverIdentity('192.168.3.20:8443'), isNot(serverIdentity('192.168.3.21:8443')));
    expect(serverIdentity('192.168.3.20:8443'), isNot(serverIdentity('192.168.3.20:8090')));
  });
}
