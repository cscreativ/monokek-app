import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/printing/test_ticket.dart';

void main() {
  test('test ticket starts with ESC @, ends with a cut, and is plain ASCII', () {
    final bytes = buildTestTicket(deviceName: 'Xprinter XP-80É', paperWidth: 80, now: DateTime(2026, 11, 2, 9, 5));

    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    final text = ascii.decode(bytes.where((b) => b >= 0x20 && b < 0x7F || b == 0x0A).toList(), allowInvalid: true);
    expect(text, contains('TEST IMPRIMANTE USB'));
    expect(text, contains('Xprinter XP-80E')); // accent transliterated, never a raw non-ASCII byte
    expect(text, contains('02/11/2026 09:05'));
  });

  test('the separator follows the paper width (32 columns for 58 mm, 48 for 80 mm)', () {
    int longestDashRun(Uint8List b) => RegExp(r'-+').allMatches(latin1.decode(b)).map((m) => m.group(0)!.length).reduce((a, c) => a > c ? a : c);

    expect(longestDashRun(buildTestTicket(deviceName: 'X', paperWidth: 58)), 32);
    expect(longestDashRun(buildTestTicket(deviceName: 'X', paperWidth: 80)), 48);
  });
}
