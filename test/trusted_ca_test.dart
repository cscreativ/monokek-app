import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/net/trusted_ca.dart';

/// Live check against a Caddy `tls internal` server. Skipped unless
/// `--dart-define=LIVE_HTTPS=https://IP:8443` is provided.
const _base = String.fromEnvironment('LIVE_HTTPS');

void main() {
  final skip = _base.isEmpty ? 'set --dart-define=LIVE_HTTPS=https://host:8443 to run' : null;

  test('fingerprint is the SHA-256 of the DER certificate', () {
    const pem = '''-----BEGIN CERTIFICATE-----
AQID
-----END CERTIFICATE-----''';
    // SHA-256 of the 3 bytes 01 02 03
    expect(TrustedCa.fingerprint(pem), '03:90:58:C6:F2:C0:CB:49:2C:53:3B:0A:4D:14:EF:77:CC:0F:78:AB:CC:CE:D5:28:7D:84:A1:A2:01:1C:FB:81');
  });

  test('without the CA the server certificate is rejected, with it the request succeeds', skip: skip, () async {
    TrustedCa.install(null);
    HttpOverrides.global = TrustingHttpOverrides();
    await expectLater(Dio().get('$_base/api/ping'), throwsA(isA<DioException>()));

    final pem = await TrustedCa.download(_base);
    TrustedCa.install(pem);
    final res = await Dio().get('$_base/api/ping');
    expect((res.data as Map)['status'], 'ok');
  });
}
