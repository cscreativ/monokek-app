import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/api/envelope.dart';
import 'package:monokek_flutter/core/roles.dart';
import 'package:monokek_flutter/core/router/app_router.dart';

String? r(String loc, {bool backend = true, bool auth = true, String? role}) =>
    computeRedirect(location: loc, hasBackend: backend, authenticated: auth, role: role);

void main() {
  test('roleHomeRoute mirrors the Tauri mapping', () {
    expect(roleHomeRoute('kitchen'), '/kitchen');
    expect(roleHomeRoute('cashier'), '/pos/sales');
    expect(roleHomeRoute('waiter'), '/pos/tables');
    expect(roleHomeRoute('admin'), '/unsupported');
  });

  group('router redirect', () {
    test('no backend → setup', () => expect(r('/login', backend: false, auth: false), '/setup'));
    test('unauthenticated → login', () => expect(r('/pos/tables', auth: false), '/login'));
    test('login screen allowed when unauthenticated', () => expect(r('/login', auth: false), isNull));
    test('authenticated at / → role home', () => expect(r('/', role: 'cashier'), '/pos/sales'));
    test('kitchen cannot enter /pos', () => expect(r('/pos/tables', role: 'kitchen'), '/kitchen'));
    test('waiter cannot enter cash screens', () => expect(r('/pos/sales', role: 'waiter'), '/pos/tables'));
    test('cashier can enter /pos/tables', () => expect(r('/pos/tables', role: 'cashier'), isNull));
  });

  group('base url', () {
    test('adds https scheme', () => expect(resolveBaseUrl('192.168.1.10:8443'), 'https://192.168.1.10:8443'));
    test('keeps an explicit http', () => expect(resolveBaseUrl('http://192.168.1.10:8080/'), 'http://192.168.1.10:8080'));
    test('keeps https', () => expect(resolveBaseUrl('https://pos.example.com/'), 'https://pos.example.com'));
  });

  group('envelope', () {
    Response<dynamic> res(Object data) => Response(requestOptions: RequestOptions(), data: data);
    test('unwraps data', () => expect(unwrap<Map<String, dynamic>>(res({'status': 'success', 'data': {'a': 1}})), {'a': 1}));
    test('throws on error status', () {
      expect(() => unwrap<dynamic>(res({'status': 'error', 'message': 'boom'})), throwsA(isA<ApiError>()));
    });
    test('bare dto passes through', () => expect(unwrap<List<dynamic>>(res([1, 2])), [1, 2]));
  });
}
