import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/printing_api.dart';
import '../../features/auth/auth_controller.dart';
import '../api/api_client.dart';
import '../branch.dart';
import '../sse/notifications_service.dart';
import '../storage/app_storage.dart';
import 'usb_print_worker.dart';
import 'usb_printer.dart';
import 'usb_printer_settings.dart';

final printingApiProvider = Provider<PrintingApi>((ref) => PrintingApi(ref.watch(apiClientProvider)));

final usbTransportProvider = Provider<UsbPrinterTransport>((ref) => defaultUsbTransport());

final usbPrinterSettingsProvider = Provider<UsbPrinterSettings>((ref) => UsbPrinterSettings(ref.watch(storageProvider)));

/// This terminal's USB printer binding, reactive: the header status and the worker both follow changes made
/// on the settings screen without a restart. Persisted through [UsbPrinterSettings].
class UsbBinding extends Notifier<UsbPrinterBinding?> {
  @override
  UsbPrinterBinding? build() => ref.watch(usbPrinterSettingsProvider).binding;

  Future<void> save(UsbPrinterBinding binding) async {
    await ref.read(usbPrinterSettingsProvider).save(binding);
    state = binding;
  }

  Future<void> clear() async {
    await ref.read(usbPrinterSettingsProvider).clear();
    state = null;
  }
}

final usbBindingProvider = NotifierProvider<UsbBinding, UsbPrinterBinding?>(UsbBinding.new);

/// Last print result of this terminal (null until something printed or failed) — for the status indicator.
class LastPrintOutcome extends Notifier<PrintOutcome?> {
  @override
  PrintOutcome? build() => null;

  void set(PrintOutcome outcome) => state = outcome;
}

final lastPrintOutcomeProvider = NotifierProvider<LastPrintOutcome, PrintOutcome?>(LastPrintOutcome.new);

/// Keeps the USB print worker alive for the whole signed-in session: it receives `print-job-queued` pushes and
/// catches up on the queue every time the SSE stream (re)connects. Idle when no USB printer is configured here.
final usbPrintWorkerProvider = Provider<UsbPrintWorker>((ref) {
  final worker = UsbPrintWorker(
    api: ref.watch(printingApiProvider),
    transport: ref.watch(usbTransportProvider),
    binding: () => ref.read(usbBindingProvider),
    onOutcome: (o) => Future.microtask(() => ref.read(lastPrintOutcomeProvider.notifier).set(o)),
  );

  final notifications = ref.watch(notificationsProvider);
  final pushes = notifications.events.where((e) => e.name == 'print-job-queued').listen((e) {
    try {
      worker.submit(PrintJob.fromJson(e.map));
    } catch (_) {
      // malformed push: the catch-up fetch will still find the job
    }
  });
  final connection = notifications.connection.listen((up) async {
    if (!up) return;
    final branchId = await resolveBranchId(ref.read(apiClientProvider), ref.read(authProvider).user);
    if (branchId != null) await worker.catchUp(branchId);
  });
  ref.onDispose(() {
    pushes.cancel();
    connection.cancel();
  });
  return worker;
});
