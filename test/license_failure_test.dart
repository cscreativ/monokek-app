import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';

DioException _dio(DioExceptionType type, {int? status, Object? error}) {
  final req = RequestOptions(path: '/api/license/status');
  return DioException(
    requestOptions: req,
    type: type,
    error: error,
    response: status == null ? null : Response(requestOptions: req, statusCode: status),
  );
}

void main() {
  test('HTTP error from a reachable server is not reported as a network outage', () {
    final f = classifyLicenseError(_dio(DioExceptionType.badResponse, status: 401));
    expect(f.kind, LicenseFailureKind.http);
    expect(f.status, 401);
    expect(classifyLicenseError(_dio(DioExceptionType.badResponse, status: 502)).kind, LicenseFailureKind.http);
  });

  test('timeouts and refused connections are network failures', () {
    expect(classifyLicenseError(_dio(DioExceptionType.connectionTimeout)).kind, LicenseFailureKind.network);
    expect(classifyLicenseError(_dio(DioExceptionType.connectionTimeout)).detail, 'Délai dépassé');
    expect(classifyLicenseError(_dio(DioExceptionType.connectionError)).kind, LicenseFailureKind.network);
  });

  test('untrusted certificate is its own failure', () {
    expect(classifyLicenseError(_dio(DioExceptionType.badCertificate)).kind, LicenseFailureKind.certificate);
    expect(
      classifyLicenseError(_dio(DioExceptionType.unknown, error: const HandshakeException('CERTIFICATE_VERIFY_FAILED'))).kind,
      LicenseFailureKind.certificate,
    );
  });

  test('public routes never carry the Bearer token', () {
    expect(publicApiPaths, containsAll(['/api/ping', '/api/login', '/api/license/status']));
    expect(publicApiPaths.contains('/api/pos/products'), isFalse);
  });
}
