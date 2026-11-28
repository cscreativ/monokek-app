import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/api/api_client.dart';
import 'core/net/trusted_ca.dart';
import 'core/printing/print_providers.dart';
import 'core/router/app_router.dart';
import 'core/sse/notifications_service.dart';
import 'core/roles.dart';
import 'core/storage/app_storage.dart';
import 'features/auth/auth_controller.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final storage = await AppStorage.create();
  TrustedCa.install(storage.trustedCa);
  HttpOverrides.global = TrustingHttpOverrides();
  runApp(ProviderScope(
    overrides: [storageProvider.overrideWithValue(storage)],
    child: const MonoKekApp(),
  ));
}

class MonoKekApp extends ConsumerStatefulWidget {
  const MonoKekApp({super.key});

  @override
  ConsumerState<MonoKekApp> createState() => _MonoKekAppState();
}

class _MonoKekAppState extends ConsumerState<MonoKekApp> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Proactive refresh: every minute, and on resume (wake-up), renew the access token before it expires.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _keepFresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepFresh());
  }

  void _keepFresh({Duration margin = const Duration(minutes: 5)}) =>
      ref.read(tokenRefresherProvider).refreshIfNeeded(margin: margin);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On wake-up the network is usually back but timers were frozen: renew generously (the token must
    // still be valid for the next 20 min) instead of waiting for the next 401 while the connection may be flaky.
    if (state == AppLifecycleState.resumed) _keepFresh(margin: const Duration(minutes: 20));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationsProvider); // keeps the single SSE connection alive for the whole session
    // Kitchen displays stay lit: a sleeping tablet drops Wi-Fi/SSE and ends up with a dead session.
    ref.listen(authProvider.select((a) => a.isAuthenticated && a.user?.role == Roles.kitchen), (_, keepAwake) {
      (keepAwake ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {});
    });
    ref.watch(usbPrintWorkerProvider); // prints this terminal's USB jobs (idle unless a USB printer is configured)
    return MaterialApp.router(
      title: 'MonoKek',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
