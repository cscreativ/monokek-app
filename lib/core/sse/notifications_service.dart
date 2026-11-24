import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../api/api_client.dart';
import '../branch.dart';

class SseEvent {
  const SseEvent(this.name, this.data);
  final String name;
  final dynamic data;

  /// Payload as a map (all known events broadcast a JSON object); empty if absent/other shape.
  Map<String, dynamic> get map => data is Map<String, dynamic> ? data as Map<String, dynamic> : const {};
}

/// Incremental Server-Sent-Events line parser: feed it one line at a time, it returns an
/// event when the blank separator line arrives.
class SseParser {
  String _event = '';
  final List<String> _data = [];

  SseEvent? addLine(String line) {
    if (line.isEmpty) {
      if (_data.isEmpty && _event.isEmpty) return null;
      final raw = _data.join('\n');
      final name = _event.isEmpty ? 'message' : _event;
      _event = '';
      _data.clear();
      dynamic payload = raw;
      if (raw.isNotEmpty) {
        try {
          payload = jsonDecode(raw);
        } catch (_) {}
      } else {
        payload = null;
      }
      return SseEvent(name, payload);
    }
    if (line.startsWith(':')) return null; // comment / keep-alive
    final i = line.indexOf(':');
    final field = i < 0 ? line : line.substring(0, i);
    var value = i < 0 ? '' : line.substring(i + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      _event = value;
    } else if (field == 'data') {
      _data.add(value);
    }
    return null;
  }
}

/// Single SSE connection for the whole app (port of NotificationsProvider.tsx).
/// A ticket is single-use, so every reconnection requests a fresh one.
class NotificationsService {
  NotificationsService(this._ref);
  final Ref _ref;

  static const _noBranchRetry = Duration(seconds: 5);
  static const _reconnectDelay = Duration(seconds: 3);
  static const _maxReconnectDelay = Duration(seconds: 60);
  int _failures = 0;
  bool _forced = false;

  final _controller = StreamController<SseEvent>.broadcast();
  Stream<SseEvent> get events => _controller.stream;

  /// True while the event stream is open: the real "online" signal for the UI indicator.
  final _connection = StreamController<bool>.broadcast();
  bool _connected = false;
  bool get connected => _connected;
  Stream<bool> get connection => _connection.stream;

  void _setConnected(bool v) {
    if (_connected == v) return;
    _connected = v;
    if (!_connection.isClosed) _connection.add(v);
  }

  /// Last moment the stream was known to be alive (an event arrived, or the connection ended). Used after a
  /// reconnection to ask the server what happened during the gap.
  DateTime? _lastAlive;

  /// Margin for clock skew between this device and the server; replaying a few seconds twice is harmless
  /// because every consumer just refetches state.
  static const _catchUpMargin = Duration(seconds: 30);

  bool _running = false;
  Timer? _timer;
  CancelToken? _cancel;
  int _branchId = 0;

  void start() {
    if (_running) return;
    _running = true;
    _branchId = 0;
    _failures = 0;
    _connect();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _cancel?.cancel();
    _cancel = null;
    _branchId = 0;
    _setConnected(false);
  }

  /// Called when the app returns to the foreground. After device sleep the SSE socket is usually a
  /// dead TCP connection that never errors, so drop it and reconnect right away (fresh ticket, and a
  /// silent token refresh through the 401 interceptor if the access token expired meanwhile).
  void resync() {
    if (!_running) return;
    _failures = 0;
    _timer?.cancel();
    if (_connected && _cancel != null) {
      _forced = true;
      _cancel!.cancel();
    } else {
      _schedule(Duration.zero);
    }
  }

  void dispose() {
    stop();
    _controller.close();
    _connection.close();
  }

  void _schedule(Duration d) {
    if (!_running) return;
    _timer?.cancel();
    _timer = Timer(d, _connect);
  }

  Future<int?> _resolveBranch() async {
    if (_branchId != 0) return _branchId;
    final id = await resolveBranchId(_ref.read(apiClientProvider), _ref.read(authProvider).user);
    if (id != null) _branchId = id;
    return id;
  }

  /// Ticket answers (ready, preparing...) that arrived while this terminal was disconnected, re-emitted as the
  /// ordinary `ticket.updated` events so every existing screen and toast reacts to them as if they were live.
  /// The server only returns what this account would have received; a failure here is never fatal.
  Future<void> _catchUp(DateTime since) async {
    try {
      final res = await _ref.read(apiClientProvider).get('/api/kitchen/updates', queryParameters: {
        'since': since.subtract(_catchUpMargin).toUtc().toIso8601String(),
      });
      final list = res.data;
      if (list is! List) return;
      for (final item in list) {
        if (item is Map<String, dynamic> && !_controller.isClosed) _controller.add(SseEvent('ticket.updated', item));
      }
    } catch (_) {/* unscoped account, old server, offline again: the next reconnection or a manual refresh covers it */}
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final branchId = await _resolveBranch();
      if (branchId == null) return _schedule(_noBranchRetry);
      if (!_running) return;

      final dio = _ref.read(apiClientProvider);
      final t = await dio.post('/api/sse/ticket', queryParameters: {'branchId': branchId});
      final ticket = (t.data as Map)['ticket'] as String;
      if (!_running) return;

      final cancel = _cancel = CancelToken();
      final res = await dio.get<ResponseBody>(
        '/api/sse/stream',
        queryParameters: {'ticket': ticket},
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero,
          headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
        ),
      );
      final parser = SseParser();
      _setConnected(true);
      _failures = 0;
      final since = _lastAlive;
      if (since != null) unawaited(_catchUp(since));
      await for (final line in res.data!.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
        final event = parser.addLine(line);
        if (event != null) _lastAlive = DateTime.now();
        if (event != null && !_controller.isClosed) _controller.add(event);
      }
    } catch (_) {
      // fall through to reconnect
    }
    _setConnected(false);
    _lastAlive = DateTime.now();
    // Exponential backoff (3s → 60s): a server/session that stays unreachable must not be pinged every 3s.
    final delay = _forced ? Duration.zero : _reconnectDelay * (1 << (_failures < 5 ? _failures : 5));
    if (_forced) {
      _forced = false;
    } else {
      _failures++;
    }
    _schedule(delay > _maxReconnectDelay ? _maxReconnectDelay : delay);
  }
}

final notificationsProvider = Provider<NotificationsService>((ref) {
  final service = NotificationsService(ref);
  // Only connect while someone is logged in; logout (or a user switch) tears the stream down.
  ref.listen(authProvider, (prev, next) {
    if (next.isAuthenticated) {
      if (prev?.user?.id != next.user?.id) service.stop();
      service.start();
    } else {
      service.stop();
    }
  }, fireImmediately: true);
  final lifecycle = AppLifecycleListener(onResume: service.resync);
  ref.onDispose(() {
    lifecycle.dispose();
    service.dispose();
  });
  return service;
});

/// Subscribe with `ref.listen(sseEventsProvider, ...)` and filter on `event.name`.
final sseEventsProvider = StreamProvider<SseEvent>((ref) => ref.watch(notificationsProvider).events);

/// Live connection state for the header indicator.
final sseConnectedProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(notificationsProvider);
  yield service.connected;
  yield* service.connection;
});
