import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/net/trusted_ca.dart';
import 'core/printing/print_providers.dart';
import 'core/router/app_router.dart';
import 'core/sse/notifications_service.dart';
import 'core/storage/app_storage.dart';
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

  void _keepFresh() => ref.read(tokenRefresherProvider).refreshIfNeeded();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _keepFresh();
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
