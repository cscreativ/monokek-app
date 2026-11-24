import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/printing/usb_print_worker.dart';
import 'package:monokek_flutter/core/printing/usb_printer.dart';
import 'package:monokek_flutter/core/printing/usb_printer_settings.dart';
import 'package:monokek_flutter/data/printing_api.dart';

class FakeApi implements PrintJobApi {
  final calls = <String>[];
  final pendingJobs = <PrintJob>[];
  final tickets = <int, Uint8List>{};

  /// Ids another terminal already holds (claim answers 409 → null).
  final lost = <int>{};
  int markSuccessFailures = 0;
  bool failEscpos = false;

  @override
  Future<List<PrintJob>> pending(int branchId) async => pendingJobs;

  @override
  Future<PrintJob?> claim(int jobId) async {
    calls.add('claim $jobId');
    if (lost.contains(jobId)) return null;
    return PrintJob(id: jobId, printerId: 4, jobType: 'receipt');
  }

  @override
  Future<Uint8List> escpos(int jobId) async {
    calls.add('escpos $jobId');
    if (failEscpos) throw Exception('serveur indisponible');
    return tickets[jobId] ?? Uint8List.fromList([jobId]);
  }

  @override
  Future<void> markSuccess(int jobId) async {
    calls.add('success $jobId');
    if (markSuccessFailures > 0) {
      markSuccessFailures--;
      throw Exception('réseau coupé');
    }
  }

  @override
  Future<void> markFailed(int jobId) async => calls.add('failed $jobId');
}

class FakeTransport implements UsbPrinterTransport {
  final written = <List<int>>[];
  bool permission = true;
  bool failWrite = false;
  Duration writeDelay = Duration.zero;
  int concurrent = 0;
  int maxConcurrent = 0;

  @override
  bool get isSupported => true;

  @override
  Future<List<UsbPrinterDevice>> listDevices() async => const [];

  @override
  Future<bool> requestPermission(UsbPrinterDevice device) async => permission;

  @override
  Future<void> write(UsbPrinterDevice device, Uint8List bytes) async {
    concurrent++;
    maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
    await Future<void>.delayed(writeDelay);
    concurrent--;
    if (failWrite) throw const UsbPrinterException('imprimante débranchée');
    written.add(bytes);
  }
}

void main() {
  const device = UsbPrinterDevice(vendorId: 1, productId: 2, name: 'Xprinter');
  late FakeApi api;
  late FakeTransport transport;
  late List<PrintOutcome> outcomes;
  UsbPrinterBinding? binding;

  UsbPrintWorker worker() => UsbPrintWorker(
        api: api,
        transport: transport,
        binding: () => binding,
        onOutcome: outcomes.add,
        ackRetryDelay: Duration.zero,
      );
  PrintJob job(int id, {int printerId = 4}) => PrintJob(id: id, printerId: printerId, jobType: 'receipt');

  setUp(() {
    api = FakeApi();
    transport = FakeTransport();
    outcomes = [];
    binding = const UsbPrinterBinding(device: device, printerIds: {4});
  });

  test('claims, fetches the ticket, writes it to the printer and acknowledges, in that order', () async {
    api.tickets[7] = Uint8List.fromList([0x1B, 0x40, 0x41]);

    await worker().submit(job(7));

    expect(api.calls, ['claim 7', 'escpos 7', 'success 7']);
    expect(transport.written, [
      [0x1B, 0x40, 0x41]
    ]);
    expect(outcomes.single.ok, isTrue);
  });

  test('a job of a printer this terminal does not stand for is left alone (no claim at all)', () async {
    await worker().submit(job(8, printerId: 99));

    expect(api.calls, isEmpty);
    expect(transport.written, isEmpty);
  });

  test('nothing happens while no USB printer is configured on this terminal', () async {
    binding = null;

    await worker().submit(job(9));

    expect(api.calls, isEmpty);
  });

  test('when another terminal holds the job it is skipped, and can be picked up if the server redelivers it', () async {
    final w = worker();
    api.lost.add(10);
    await w.submit(job(10));
    expect(transport.written, isEmpty);

    api.lost.clear(); // the other terminal failed; the server republishes
    await w.submit(job(10));
    expect(transport.written, hasLength(1));
  });

  test('the same job delivered twice (push + catch-up) is printed once', () async {
    final w = worker();

    await Future.wait([w.submit(job(11)), w.submit(job(11))]);
    await w.submit(job(11));

    expect(transport.written, hasLength(1));
    expect(api.calls.where((c) => c == 'claim 11'), hasLength(1));
  });

  test('jobs are written one at a time, in arrival order', () async {
    transport.writeDelay = const Duration(milliseconds: 20);
    final w = worker();

    await Future.wait([w.submit(job(1)), w.submit(job(2)), w.submit(job(3))]);

    expect(transport.maxConcurrent, 1);
    expect(transport.written.map((b) => b.first), [1, 2, 3]);
  });

  test('a write failure reports the job as failed to the server and allows a later retry', () async {
    final w = worker();
    transport.failWrite = true;
    await w.submit(job(12));

    expect(api.calls, contains('failed 12'));
    expect(outcomes.single.ok, isFalse);
    expect(outcomes.single.error, contains('débranchée'));

    transport.failWrite = false; // plugged back in; the server's retry scheduler redelivers
    await w.submit(job(12));
    expect(transport.written, hasLength(1));
    expect(outcomes.last.ok, isTrue);
  });

  test('a refused USB permission fails the job without writing anything', () async {
    transport.permission = false;

    await worker().submit(job(13));

    expect(transport.written, isEmpty);
    expect(api.calls, contains('failed 13'));
    expect(outcomes.single.error, contains('Accès USB refusé'));
  });

  test('a server error while fetching the ticket fails the job instead of crashing the worker', () async {
    api.failEscpos = true;

    await worker().submit(job(14));

    expect(api.calls, ['claim 14', 'escpos 14', 'failed 14']);
    expect(transport.written, isEmpty);
  });

  test('if only the acknowledgement fails after printing, it is retried and the ticket is never printed twice', () async {
    final w = worker();
    api.markSuccessFailures = 3; // every retry of this attempt fails

    await w.submit(job(15));
    expect(transport.written, hasLength(1));
    expect(api.calls, isNot(contains('failed 15')));

    await w.submit(job(15)); // redelivered by the server: must not print again
    expect(transport.written, hasLength(1));

    api.calls.clear();
    api.markSuccessFailures = 0;
    await w.catchUp(3); // network is back: the pending acknowledgement goes through
    expect(api.calls, contains('success 15'));
  });

  test('catch-up prints the jobs queued while the terminal was offline, skipping other printers', () async {
    api.pendingJobs.addAll([job(20), job(21, printerId: 99), job(22)]);

    await worker().catchUp(3);

    expect(transport.written.map((b) => b.first), [20, 22]);
  });

  test('an unsupported platform never touches the server', () async {
    final w = UsbPrintWorker(api: api, transport: const UnsupportedUsbTransport(), binding: () => binding);

    await w.submit(job(30));
    await w.catchUp(3);

    expect(api.calls, isEmpty);
  });
}
