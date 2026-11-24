import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

DioException _timeout() => DioException(requestOptions: RequestOptions(path: '/api/license/status'), type: DioExceptionType.connectionTimeout);

void main() {
  late AppStorage storage;
  var calls = 0;

  Future<void> mount(WidgetTester t, Future<LicenseStatus> Function(int call) answer, {bool rebuildEverySecond = false}) async {
    SharedPreferences.setMockInitialValues({'backend-ip': '192.168.3.20:8443'});
    storage = (await t.runAsync(AppStorage.create))!;
    calls = 0;
    final tick = ValueNotifier<int>(0);
    await t.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        licenseProvider.overrideWith((ref) => answer(++calls)),
      ],
      child: MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tick,
          // A NEW LicenseGuard each tick forces build() to run again, like any rebuild would.
          builder: (_, n, _) => LicenseGuard(key: const ValueKey('g'), child: Text('APP OK $n')),
        ),
      ),
    ));
    if (rebuildEverySecond) {
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(seconds: 1));
        tick.value++;
      }
    }
  }

  const ok = LicenseStatus(active: true, expired: false);

  testWidgets('the retry fires after 8 s even if the screen rebuilds every second', (t) async {
    await mount(t, (call) async => call == 1 ? throw _timeout() : ok, rebuildEverySecond: true);
    expect(calls, greaterThanOrEqualTo(2), reason: 'a rebuild must not push the retry back');
    expect(find.textContaining('APP OK'), findsOneWidget);
  });

  testWidgets('a slow server is not restarted before it can answer', (t) async {
    // The first request answers after 12 s (> the 8 s retry delay) with an error.
    await mount(t, (call) async {
      await Future<void>.delayed(const Duration(seconds: 12));
      if (call == 1) throw _timeout();
      return ok;
    });
    await t.pump(const Duration(seconds: 11));
    expect(calls, 1, reason: 'no retry while the request is still in flight');
    await t.pump(const Duration(seconds: 2)); // t=13: first answered (error) -> retry armed
    expect(find.textContaining('INJOIGNABLE'), findsOneWidget);
    await t.pump(const Duration(seconds: 8)); // retry fires
    expect(calls, 2);
    await t.pump(const Duration(seconds: 13)); // second request answers OK
    expect(find.textContaining('APP OK'), findsOneWidget);
  });
}
