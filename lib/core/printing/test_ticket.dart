import 'dart:convert';
import 'dart:typed_data';

/// A small ESC/POS test ticket generated locally (no server involved), to check the whole USB path of THIS
/// terminal: cable, permission, printer, paper, cutter. Plain ASCII only — no code page assumption.
Uint8List buildTestTicket({required String deviceName, required int paperWidth, DateTime? now}) {
  final cols = paperWidth == 80 ? 48 : 32;
  final time = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)}';

  final out = BytesBuilder();
  void raw(List<int> bytes) => out.add(bytes);
  void line(String text) {
    out.add(ascii.encode(_asciiOnly(text)));
    out.addByte(0x0A);
  }

  raw([0x1B, 0x40]); // ESC @  initialize
  raw([0x1B, 0x61, 0x01]); // ESC a 1  center
  raw([0x1B, 0x45, 0x01, 0x1D, 0x21, 0x11]); // bold + double size
  line('MONOKEK');
  raw([0x1D, 0x21, 0x00, 0x1B, 0x45, 0x00]); // normal size, bold off
  line('TEST IMPRIMANTE USB');
  line('-' * cols);
  line(deviceName);
  line('Papier ${paperWidth == 80 ? 80 : 58} mm');
  line(stamp);
  line('-' * cols);
  line('Si vous lisez ce ticket,');
  line("l'impression USB fonctionne.");
  raw([0x1B, 0x64, 0x04]); // ESC d 4  feed 4 lines
  raw([0x1D, 0x56, 0x42, 0x00]); // GS V 66 0  feed to cutter + partial cut
  return out.toBytes();
}

/// Replaces anything outside printable ASCII (accents included) so the printer never prints garbage.
String _asciiOnly(String s) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
  const to = 'aaaaaceeeeiiiinooooouuuuyyAAAAACEEEEIIIINOOOOOUUUUY';
  final b = StringBuffer();
  for (final c in s.runes) {
    final ch = String.fromCharCode(c);
    final i = from.indexOf(ch);
    if (i >= 0) {
      b.write(to[i]);
    } else if (c >= 0x20 && c < 0x7F) {
      b.write(ch);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}
