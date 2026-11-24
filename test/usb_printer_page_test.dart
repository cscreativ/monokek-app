import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/printing/print_providers.dart';
import 'package:monokek_flutter/core/printing/usb_print_worker.dart';
import 'package:monokek_flutter/core/printing/usb_printer.dart';
import 'package:monokek_flutter/core/printing/usb_printer_settings.dart';
import 'package:monokek_flutter/core/router/app_router.dart';
import 'package:monokek_flutter/core/security/setup_pin.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/core/theme/app_theme.dart';
import 'package:monokek_flutter/data/printing_api.dart';
import 'package:monokek_flutter/features/auth/auth_controller.dart';
import 'package:monokek_flutter/features/printing/usb_printer_page.dart';
import 'package:monokek_flutter/models/app_user.dart';
import 'package:monokek_flutter/shared/widgets/printer_status.dart';
import 'package:monokek_flutter/shared/widgets/setup_pin_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.printers);
  final List<Map<String, dynamic>> printers;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.path == '/api/print-queue/printers' ? printers : <String, dynamic>{};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuth extends AuthController {
  @override
  AuthState build() => const AuthState(user: AppUser(id: 3, uuid: 'u', name: 'Awa', role: 'cashier', branchId: 1), token: 't');
}

class _FakeTransport implements UsbPrinterTransport {
  _FakeTransport({this.supported = true, this.devices = const []});
  final bool supported;
  List<UsbPrinterDevice> devices;
  final written = <Uint8List>[];

  @override
  bool get isSupported => supported;
  @override
  Future<List<UsbPrinterDevice>> listDevices() async => devices;
  @override
  Future<bool> requestPermission(UsbPrinterDevice device) async => true;
  @override
  Future<void> write(UsbPrinterDevice device, Uint8List bytes) async => written.add(bytes);
}

class _IdleApi implements PrintJobApi {
  @override
  Future<List<PrintJob>> pending(int branchId) async => const [];
  @override
  Future<PrintJob?> claim(int jobId) async => null;
  @override
  Future<Uint8List> escpos(int jobId) async => Uint8List(0);
  @override
  Future<void> markSuccess(int jobId) async {}
  @override
  Future<void> markFailed(int jobId) async {}
}

const _xprinter = UsbPrinterDevice(vendorId: 1155, productId: 22339, name: 'Xprinter XP-80');
const _caisse = {'id': 4, 'name': 'Caisse', 'location': 'receipt', 'paperWidth': 80, 'charPerLine': 48, 'useBeep': true};

Future<(AppStorage, _FakeTransport)> _pump(
  WidgetTester t,
  Widget child, {
  _FakeTransport? transport,
  List<Map<String, dynamic>> printers = const [_caisse],
  Map<String, Object> prefs = const {},
  Size size = const Size(800, 1200),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final storage = (await t.runAsync(AppStorage.create))!;
  final tr = transport ?? _FakeTransport(devices: const [_xprinter]);
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => child)]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(Dio()..httpClientAdapter = _Adapter(printers)),
      authProvider.overrideWith(_FakeAuth.new),
      usbTransportProvider.overrideWithValue(tr),
      usbPrintWorkerProvider.overrideWithValue(UsbPrintWorker(api: _IdleApi(), transport: tr, binding: () => null)),
    ],
    child: MaterialApp.router(theme: buildTheme(Brightness.light), routerConfig: router),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  return (storage, tr);
}

void main() {
  testWidgets('lists the plugged devices and the branch printers; saving stores the binding', (t) async {
    final (storage, _) = await _pump(t, const UsbPrinterPage());

    expect(find.text('Xprinter XP-80'), findsOneWidget);
    expect(find.text('Caisse'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'ENREGISTRER')).onPressed, isNull); // nothing chosen yet

    await t.tap(find.text('Xprinter XP-80'));
    await t.tap(find.text('Caisse'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'ENREGISTRER'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    final binding = UsbPrinterSettings(storage).binding!;
    expect(binding.device.key, '1155:22339');
    expect(binding.printerIds, {4});
    expect(binding.paperWidth, 80); // taken from the server printer's paper width
  });

  testWidgets('the test button writes a real ESC/POS ticket to the selected printer', (t) async {
    final (_, transport) = await _pump(t, const UsbPrinterPage());

    await t.tap(find.text('Xprinter XP-80'));
    await t.pump();
    await t.tap(find.text("TESTER L'IMPRESSION"));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(transport.written, hasLength(1));
    expect(transport.written.single.sublist(0, 2), [0x1B, 0x40]);
    expect(find.textContaining('Ticket de test envoyé'), findsOneWidget);
  });

  testWidgets('an existing configuration is shown pre-selected and can be removed', (t) async {
    final prefs = <String, Object>{
      'usb-printer': jsonEncode(const UsbPrinterBinding(device: _xprinter, printerIds: {4}, paperWidth: 80).toJson()),
    };
    final (storage, _) = await _pump(t, const UsbPrinterPage(), prefs: prefs);

    expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
    await t.tap(find.text('SUPPRIMER LA CONFIGURATION'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await t.pumpAndSettle();

    expect(UsbPrinterSettings(storage).binding, isNull);
  });

  testWidgets('a branch with no USB printer declared on the server gets an explicit warning', (t) async {
    await _pump(t, const UsbPrinterPage(), printers: const []);

    expect(find.textContaining("Aucune imprimante USB active n'est déclarée"), findsOneWidget);
  });

  testWidgets('with nothing plugged in the page says how to plug the printer', (t) async {
    await _pump(t, const UsbPrinterPage(), transport: _FakeTransport());

    expect(find.textContaining('Aucun appareil USB détecté'), findsOneWidget);
  });

  testWidgets('on a platform without USB support the page explains it instead of offering a dead form', (t) async {
    await _pump(t, const UsbPrinterPage(), transport: _FakeTransport(supported: false));

    expect(find.textContaining("disponible sur Android"), findsOneWidget);
    expect(find.text('ENREGISTRER'), findsNothing);
  });

  testWidgets('no overflow on a small phone', (t) async {
    await _pump(t, const UsbPrinterPage(), size: const Size(360, 740));

    expect(t.takeException(), isNull);
  });

  testWidgets('the header pill is hidden until a printer is configured, then turns red after a failed print', (t) async {
    final prefs = <String, Object>{
      'usb-printer': jsonEncode(const UsbPrinterBinding(device: _xprinter, printerIds: {4}).toJson()),
    };
    await _pump(t, const Scaffold(body: Center(child: PrinterStatus())), prefs: prefs);

    expect(find.text('IMPRIMANTE'), findsOneWidget);

    final container = ProviderScope.containerOf(t.element(find.byType(PrinterStatus)));
    container.read(lastPrintOutcomeProvider.notifier).set(const PrintOutcome(jobId: 9, ok: false, error: 'imprimante débranchée'));
    await t.pump();

    expect(find.text('ERREUR'), findsOneWidget);
  });

  testWidgets('without a configured printer the header shows nothing', (t) async {
    await _pump(t, const Scaffold(body: Center(child: PrinterStatus())));

    expect(find.text('IMPRIMANTE'), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('the terminal PIN gate accepts the right PIN, rejects a wrong one, and is skipped when no PIN exists', (t) async {
    bool? result;
    late AppStorage storage;
    Future<void> open() async {
      await t.tap(find.text('open'));
      await t.pump();
    }

    final pumped = await _pump(
      t,
      Builder(builder: (context) => Scaffold(body: Center(child: TextButton(child: const Text('open'), onPressed: () async => result = await confirmSetupPin(context, storage))))),
    );
    storage = pumped.$1;

    await open(); // no PIN yet → straight through
    expect(result, isTrue);

    await t.runAsync(() => saveSetupPin(storage, '1234'));
    result = null;
    await open();
    for (final k in ['9', '9', '9', '9']) {
      await t.tap(find.text(k).last);
      await t.pump();
    }
    expect(result, isNull); // wrong PIN: dialog still open
    expect(find.text('Code PIN du poste'), findsOneWidget);

    for (final k in ['1', '2', '3', '4']) {
      await t.tap(find.text(k).last);
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(result, isTrue);
  });

  test('the printer settings route is open to every role, kitchen included', () {
    String? r(String role) => computeRedirect(location: '/printer/usb', hasBackend: true, authenticated: true, role: role);
    expect([r('kitchen'), r('cashier'), r('waiter')], everyElement(isNull));
  });
}
