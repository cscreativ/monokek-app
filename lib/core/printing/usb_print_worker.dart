import 'dart:async';

import '../../data/printing_api.dart';
import 'usb_printer.dart';
import 'usb_printer_settings.dart';

class PrintOutcome {
  const PrintOutcome({required this.jobId, required this.ok, this.error});
  final int jobId;
  final bool ok;
  final String? error;
}

/// Prints the USB jobs of this terminal's printer(s) — the Flutter counterpart of the Tauri UsbPrintQueueWorker.
///
/// For each job: reserve it on the server (`claim`: when several terminals receive the same push, exactly one
/// wins), fetch the ticket as ESC/POS bytes, write them to the USB printer, then acknowledge. Jobs are handled
/// one at a time, in arrival order, because one USB printer cannot take two tickets at once.
class UsbPrintWorker {
  UsbPrintWorker({
    required this.api,
    required this.transport,
    required this.binding,
    this.onOutcome,
    this.ackRetries = 3,
    this.ackRetryDelay = const Duration(seconds: 2),
  });

  final PrintJobApi api;
  final UsbPrinterTransport transport;

  /// Read at each job, so changing the setting needs no restart.
  final UsbPrinterBinding? Function() binding;
  final void Function(PrintOutcome outcome)? onOutcome;
  final int ackRetries;
  final Duration ackRetryDelay;

  Future<void> _tail = Future.value();

  /// Jobs in flight or already physically printed this session: never printed twice (the SSE push and the
  /// catch-up fetch can deliver the same still-unacknowledged job). Removed when a job fails or is lost to
  /// another terminal, so the server's later redelivery gets a fresh attempt.
  final _seen = <int>{};

  /// Printed, but the server could not be told (network down): re-acknowledged at the next catch-up
  /// instead of being printed again.
  final _unacked = <int>{};

  bool get _active => transport.isSupported && binding() != null;

  /// Queues [job]; completes once it has been handled (printed, skipped, or failed).
  Future<void> submit(PrintJob job) {
    if (!_active) return Future.value();
    return _tail = _tail.then((_) => _process(job));
  }

  /// Jobs queued while this terminal was offline. Called on every (re)connection of the SSE stream.
  Future<void> catchUp(int branchId) async {
    if (!_active) return;
    await _flushAcks();
    List<PrintJob> jobs;
    try {
      jobs = await api.pending(branchId);
    } catch (_) {
      return; // server unreachable: the next reconnection tries again
    }
    for (final job in jobs) {
      await submit(job);
    }
  }

  Future<void> _process(PrintJob job) async {
    final b = binding();
    if (b == null || !b.printerIds.contains(job.printerId)) return; // not this terminal's printer
    if (!_seen.add(job.id)) return;

    var claimed = false;
    var printed = false;
    try {
      if (await api.claim(job.id) == null) {
        _seen.remove(job.id); // another terminal holds it; if it fails there, the server redelivers
        return;
      }
      claimed = true;
      if (!await transport.requestPermission(b.device)) throw const UsbPrinterException('Accès USB refusé');
      final bytes = await api.escpos(job.id);
      await transport.write(b.device, bytes);
      printed = true;
      await _ack(job.id);
      onOutcome?.call(PrintOutcome(jobId: job.id, ok: true));
    } catch (e) {
      if (printed) {
        // The ticket is out; only the acknowledgement is missing. Never print it again.
        _unacked.add(job.id);
        onOutcome?.call(PrintOutcome(jobId: job.id, ok: true, error: 'Imprimé, confirmation serveur en attente'));
        return;
      }
      _seen.remove(job.id);
      if (claimed) {
        try {
          await api.markFailed(job.id);
        } catch (_) {
          // the claim lease expires on the server and the job is released by itself
        }
      }
      onOutcome?.call(PrintOutcome(jobId: job.id, ok: false, error: e.toString()));
    }
  }

  Future<void> _ack(int jobId) async {
    Object? last;
    for (var i = 0; i < ackRetries; i++) {
      try {
        await api.markSuccess(jobId);
        return;
      } catch (e) {
        last = e;
        if (i < ackRetries - 1) await Future<void>.delayed(ackRetryDelay);
      }
    }
    throw last!;
  }

  Future<void> _flushAcks() async {
    for (final id in _unacked.toList()) {
      try {
        await api.markSuccess(id);
        _unacked.remove(id);
      } catch (_) {}
    }
  }
}
