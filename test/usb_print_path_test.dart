import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/printing/usb_print_path.dart';

void main() {
  test('the vendor and product ids are read from a real usbprint device path, whatever the case', () {
    const path = r'\\?\usb#vid_0483&pid_5743#5&2a5b3c7&0&2#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}';

    final ids = parseUsbPrintPath(path)!;
    expect(ids.vendorId, 0x0483);
    expect(ids.productId, 0x5743);

    final upper = parseUsbPrintPath(path.toUpperCase())!;
    expect(upper.vendorId, 0x0483);
    expect(upper.productId, 0x5743);
  });

  test('a path without usb ids is ignored instead of crashing the listing', () {
    expect(parseUsbPrintPath(r'\\?\root#printqueue#0000#{28d78fad-5a12-11d1-ae5b-0000f803a8c2}'), isNull);
    expect(parseUsbPrintPath(''), isNull);
  });

  test('the USBPRINT interface GUID is encoded the way a Windows GUID struct lays out in memory', () {
    expect(usbPrintInterfaceGuid, hasLength(16));
    // {28d78fad-5a12-11d1-ae5b-0000f803a8c2}: first three fields little-endian, last eight bytes in order.
    expect(usbPrintInterfaceGuid.sublist(0, 4), [0xAD, 0x8F, 0xD7, 0x28]);
    expect(usbPrintInterfaceGuid.sublist(4, 6), [0x12, 0x5A]);
    expect(usbPrintInterfaceGuid.sublist(6, 8), [0xD1, 0x11]);
    expect(usbPrintInterfaceGuid.sublist(8), [0xAE, 0x5B, 0x00, 0x00, 0xF8, 0x03, 0xA8, 0xC2]);
  });

  test('SetupAPI struct sizes follow the pointer size (the classic 32/64-bit trap)', () {
    expect(setupStructSize(8), 32);
    expect(setupStructSize(4), 28);
    expect(deviceInterfaceDetailCbSize(8), 8); // not sizeof(): documented quirk
    expect(deviceInterfaceDetailCbSize(4), 6);
  });
}
