import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A job of the server's print queue (PrintQueueDto, or the `print-job-queued` SSE payload which names the id `jobId`).
class PrintJob {
  const PrintJob({required this.id, required this.printerId, required this.jobType});

  final int id;
  final int printerId;
  final String jobType;

  factory PrintJob.fromJson(Map<String, dynamic> j) => PrintJob(
        id: ((j['id'] ?? j['jobId']) as num).toInt(),
        printerId: (j['printerId'] as num).toInt(),
        jobType: j['jobType'] as String? ?? '',
      );
}

/// An active USB printer of the branch, as the server knows it (UsbPrinterDto — no IP, no OS name).
class ServerUsbPrinter {
  const ServerUsbPrinter({required this.id, required this.name, required this.location, required this.paperWidth});

  final int id;
  final String name;
  final String location;
  final int paperWidth;

  factory ServerUsbPrinter.fromJson(Map<String, dynamic> j) => ServerUsbPrinter(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? 'Imprimante ${j['id']}',
        location: j['location'] as String? ?? 'receipt',
        paperWidth: (j['paperWidth'] as num?)?.toInt() ?? 58,
      );
}

/// What the USB print worker needs from the server; an interface so the worker is testable without HTTP.
abstract class PrintJobApi {
  Future<List<PrintJob>> pending(int branchId);

  /// Reserves the job for this terminal. Null = another terminal already has it (or it is finished): skip it.
  Future<PrintJob?> claim(int jobId);

  /// The ticket as raw ESC/POS bytes, rendered by the server.
  Future<Uint8List> escpos(int jobId);

  Future<void> markSuccess(int jobId);
  Future<void> markFailed(int jobId);
}

/// `/api/print-queue/*` (see PrintQueueController in monokek-spring).
class PrintingApi implements PrintJobApi {
  PrintingApi(this._dio);
  final Dio _dio;

  @override
  Future<List<PrintJob>> pending(int branchId) async {
    final r = await _dio.get('/api/print-queue/pending', queryParameters: {'branchId': branchId});
    return (r.data as List).map((e) => PrintJob.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// USB printers of the branch this terminal can be bound to.
  Future<List<ServerUsbPrinter>> usbPrinters(int branchId) async {
    final r = await _dio.get('/api/print-queue/printers', queryParameters: {'branchId': branchId});
    return (r.data as List).map((e) => ServerUsbPrinter.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<PrintJob?> claim(int jobId) async {
    try {
      final r = await _dio.post('/api/print-queue/$jobId/claim');
      return PrintJob.fromJson(r.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) return null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> escpos(int jobId) async {
    // Explicit Accept: the shared client sends `application/json` everywhere, which the server rejects for this binary endpoint.
    final r = await _dio.get<List<int>>(
      '/api/print-queue/$jobId/escpos',
      options: Options(responseType: ResponseType.bytes, headers: {'Accept': 'application/octet-stream'}),
    );
    return Uint8List.fromList(r.data!);
  }

  @override
  Future<void> markSuccess(int jobId) => _dio.post('/api/print-queue/$jobId/mark-success');

  @override
  Future<void> markFailed(int jobId) => _dio.post('/api/print-queue/$jobId/mark-failed');
}
