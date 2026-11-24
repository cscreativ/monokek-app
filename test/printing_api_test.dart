import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/data/printing_api.dart';

/// Minimal scripted HTTP layer: answers by "METHOD path", records the requests.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.routes);
  final Map<String, ResponseBody Function(RequestOptions)> routes;
  final requests = <String>[];
  final headers = <String, Map<String, dynamic>>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final key = '${options.method} ${options.path}';
    requests.add(key + (options.queryParameters.isEmpty ? '' : ' ${options.queryParameters}'));
    headers[key] = Map.of(options.headers);
    final route = routes[key];
    if (route == null) return ResponseBody.fromString('not found', 404);
    return route(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: ['application/json']});

void main() {
  PrintingApi apiFor(ScriptedAdapter adapter) => PrintingApi(Dio()..httpClientAdapter = adapter);

  test('the SSE push (jobId) and the queue DTO (id) both parse into a PrintJob', () {
    final fromPush = PrintJob.fromJson({'jobId': 5, 'printerId': 4, 'jobType': 'receipt', 'content': '{}', 'priority': 1});
    final fromDto = PrintJob.fromJson({'id': 5, 'printerId': 4, 'jobType': 'receipt', 'status': 'pending'});

    expect([fromPush.id, fromPush.printerId, fromPush.jobType], [5, 4, 'receipt']);
    expect([fromDto.id, fromDto.printerId, fromDto.jobType], [5, 4, 'receipt']);
  });

  test('pending sends the branch and parses the queue', () async {
    final adapter = ScriptedAdapter({
      'GET /api/print-queue/pending': (_) => json([
            {'id': 1, 'printerId': 4, 'jobType': 'receipt'},
            {'id': 2, 'printerId': 5, 'jobType': 'kitchen'}
          ]),
    });

    final jobs = await apiFor(adapter).pending(3);

    expect(jobs.map((j) => j.id), [1, 2]);
    expect(adapter.requests.single, contains('branchId: 3'));
  });

  test('claim answers the job when won and null on 409 (another terminal has it)', () async {
    final adapter = ScriptedAdapter({
      'POST /api/print-queue/1/claim': (_) => json({'id': 1, 'printerId': 4, 'jobType': 'receipt'}),
      'POST /api/print-queue/2/claim': (_) => json({'status': 'error', 'message': 'déjà pris'}, 409),
    });
    final api = apiFor(adapter);

    expect((await api.claim(1))?.id, 1);
    expect(await api.claim(2), isNull);
  });

  test('claim still raises on real errors (server down, forbidden) so the worker reports them', () async {
    final adapter = ScriptedAdapter({'POST /api/print-queue/3/claim': (_) => json({'message': 'non'}, 403)});

    expect(() => apiFor(adapter).claim(3), throwsA(isA<DioException>()));
  });

  test('escpos returns the raw bytes untouched, including non-text ones', () async {
    final raw = Uint8List.fromList([0x1B, 0x40, 0x00, 0xFF, 0x1D, 0x56, 0x30]);
    final adapter = ScriptedAdapter({
      'GET /api/print-queue/9/escpos': (_) => ResponseBody.fromBytes(raw, 200, headers: {
            Headers.contentTypeHeader: ['application/octet-stream']
          }),
    });

    expect(await apiFor(adapter).escpos(9), raw);
  });

  test('escpos asks for octet-stream even though the shared client sends Accept: application/json everywhere', () async {
    final adapter = ScriptedAdapter({
      'GET /api/print-queue/9/escpos': (o) {
        // What the real server does: Spring rejects an Accept it cannot satisfy for this binary endpoint.
        final accept = o.headers['Accept'] as String;
        return accept.contains('octet-stream') ? ResponseBody.fromBytes([1, 2, 3], 200) : ResponseBody.fromString('not acceptable', 500);
      },
    });
    final dio = Dio(BaseOptions(headers: {'Accept': 'application/json'}))..httpClientAdapter = adapter; // same default as apiClientProvider

    expect(await PrintingApi(dio).escpos(9), [1, 2, 3]);
    expect(adapter.headers['GET /api/print-queue/9/escpos']!['Accept'], 'application/octet-stream');
  });

  test('usbPrinters parses the branch printers and tolerates missing optional fields', () async {
    final adapter = ScriptedAdapter({
      'GET /api/print-queue/printers': (_) => json([
            {'id': 4, 'name': 'Caisse', 'location': 'receipt', 'paperWidth': 80, 'charPerLine': 48, 'useBeep': true},
            {'id': 6},
          ]),
    });

    final printers = await apiFor(adapter).usbPrinters(3);

    expect(printers.first.paperWidth, 80);
    expect(printers.last.location, 'receipt');
    expect(printers.last.paperWidth, 58);
  });
}
