import 'dart:async';

/// Runs [action] at most once per [interval], however often [trigger] is called.
///
/// The first call runs at once (a ticket that just became "ready" must show immediately); calls arriving during the window collapse into ONE more
/// run when it ends, so the screen always ends up with the latest state. Why it exists: every order or ticket event reaches every terminal of the
/// branch, and each screen used to refetch its whole list on EACH of them — about six refetches per order per terminal. With two dozen terminals that
/// storm slowed the server ten-fold and delayed the very notifications that started it.
class Coalescer {
  Coalescer(this.action, {this.interval = const Duration(seconds: 2)});

  final void Function() action;
  final Duration interval;

  Timer? _window;
  bool _pending = false;
  bool _disposed = false;

  void trigger() {
    if (_disposed) return;
    if (_window == null) {
      _run();
    } else {
      _pending = true;
    }
  }

  void _run() {
    _pending = false;
    _window = Timer(interval, _windowEnded);
    action();
  }

  void _windowEnded() {
    _window = null;
    if (_pending && !_disposed) _run();
  }

  void dispose() {
    _disposed = true;
    _window?.cancel();
    _window = null;
  }
}
