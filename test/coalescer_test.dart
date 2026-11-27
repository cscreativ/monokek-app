import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/sse/coalescer.dart';

void main() {
  const window = Duration(milliseconds: 80);

  test('the first trigger runs at once', () {
    var runs = 0;
    final c = Coalescer(() => runs++, interval: window);
    c.trigger();
    expect(runs, 1);
    c.dispose();
  });

  test('a burst collapses into ONE more run when the window ends', () async {
    var runs = 0;
    final c = Coalescer(() => runs++, interval: window);
    for (var i = 0; i < 50; i++) {
      c.trigger();
    }
    expect(runs, 1, reason: 'only the leading run so far');
    await Future<void>.delayed(window * 2);
    expect(runs, 2, reason: '49 more events -> exactly one trailing refetch');
    await Future<void>.delayed(window * 2);
    expect(runs, 2, reason: 'nothing pending: no extra run');
    c.dispose();
  });

  test('never more than one run per window, however long the storm lasts', () async {
    var runs = 0;
    final c = Coalescer(() => runs++, interval: window);
    final started = DateTime.now();
    while (DateTime.now().difference(started) < window * 5) {
      c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await Future<void>.delayed(window * 2);
    // 5 windows of continuous events: about one run per window (+ the final trailing one), never one per event
    expect(runs, lessThanOrEqualTo(9));
    expect(runs, greaterThanOrEqualTo(4));
    c.dispose();
  });

  test('after a quiet window the next event runs at once again', () async {
    var runs = 0;
    final c = Coalescer(() => runs++, interval: window);
    c.trigger();
    await Future<void>.delayed(window * 2);
    c.trigger();
    expect(runs, 2);
    c.dispose();
  });

  test('a disposed coalescer never runs again', () async {
    var runs = 0;
    final c = Coalescer(() => runs++, interval: window);
    c.trigger();
    c.trigger();
    c.dispose();
    await Future<void>.delayed(window * 2);
    c.trigger();
    expect(runs, 1);
  });
}
