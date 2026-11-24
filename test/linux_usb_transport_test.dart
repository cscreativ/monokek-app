import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/printing/linux_usb_transport.dart';
import 'package:monokek_flutter/core/printing/usb_printer.dart';

/// Builds a fake /sys/bus/usb/devices tree.
class FakeSysfs {
  FakeSysfs() : root = Directory.systemTemp.createTempSync('sysfs_test_');
  final Directory root;

  void file(String path, String content) {
    final f = File('${root.path}/$path')..createSync(recursive: true);
    f.writeAsStringSync('$content\n');
  }

  void device(String name, {required String vid, required String pid, String? product, String bus = '1', String dev = '2'}) {
    file('$name/idVendor', vid);
    file('$name/idProduct', pid);
    if (product != null) file('$name/product', product);
    file('$name/busnum', bus);
    file('$name/devnum', dev);
  }

  void iface(String name, {required String cls, String number = '00'}) {
    file('$name/bInterfaceClass', cls);
    file('$name/bInterfaceNumber', number);
  }

  void endpoint(String iface, String addr, {required String direction, String type = 'Bulk'}) {
    file('$iface/ep_$addr/bEndpointAddress', addr);
    file('$iface/ep_$addr/direction', direction);
    file('$iface/ep_$addr/type', type);
  }

  void dispose() => root.deleteSync(recursive: true);
}

void main() {
  late FakeSysfs sysfs;
  setUp(() => sysfs = FakeSysfs());
  tearDown(() => sysfs.dispose());

  test('finds an Xprinter: printer-class interface, its number and its bulk OUT endpoint', () {
    sysfs.device('1-1', vid: '0483', pid: '5743', product: 'USB Printer Port', bus: '1', dev: '19');
    sysfs.iface('1-1:1.0', cls: '07');
    sysfs.endpoint('1-1:1.0', '01', direction: 'out');
    sysfs.endpoint('1-1:1.0', '82', direction: 'in');

    final printers = scanSysfsPrinters(sysfs.root.path);

    expect(printers, hasLength(1));
    final p = printers.single;
    expect([p.vendorId, p.productId], [0x0483, 0x5743]);
    expect(p.name, 'USB Printer Port');
    expect(p.interfaceNumber, 0);
    expect(p.endpointAddress, 0x01); // the OUT one, not 0x82
    expect(p.node, '/dev/bus/usb/001/019');
  });

  test('keyboards, hubs and other non-printer devices are ignored', () {
    sysfs.device('1-3', vid: '2a7a', pid: '8a57', product: 'USB KB');
    sysfs.iface('1-3:1.0', cls: '03');
    sysfs.endpoint('1-3:1.0', '81', direction: 'in', type: 'Interrupt');
    sysfs.device('usb1', vid: '1d6b', pid: '0002');

    expect(scanSysfsPrinters(sysfs.root.path), isEmpty);
  });

  test('a printer interface without any bulk OUT endpoint cannot be written to, so it is not offered', () {
    sysfs.device('1-2', vid: '04b8', pid: '0202', product: 'Read-only thing');
    sysfs.iface('1-2:1.0', cls: '07');
    sysfs.endpoint('1-2:1.0', '82', direction: 'in');

    expect(scanSysfsPrinters(sysfs.root.path), isEmpty);
  });

  test('several printers are all listed, and a printer on a later interface of a composite device is found', () {
    sysfs.device('1-1', vid: '0483', pid: '5743', product: 'Caisse');
    sysfs.iface('1-1:1.0', cls: '07');
    sysfs.endpoint('1-1:1.0', '01', direction: 'out');
    sysfs.device('1-4', vid: '0416', pid: '5011', product: 'Cuisine');
    sysfs.iface('1-4:1.0', cls: '03');
    sysfs.iface('1-4:1.1', cls: '07', number: '01');
    sysfs.endpoint('1-4:1.1', '03', direction: 'out');

    final printers = scanSysfsPrinters(sysfs.root.path);

    expect(printers.map((p) => p.name), ['Caisse', 'Cuisine']);
    expect(printers.last.interfaceNumber, 1);
    expect(printers.last.endpointAddress, 0x03);
  });

  test('a missing product name falls back to the ids, and a missing sysfs tree gives an empty list', () {
    sysfs.device('1-1', vid: '0483', pid: '5743');
    sysfs.iface('1-1:1.0', cls: '07');
    sysfs.endpoint('1-1:1.0', '01', direction: 'out');

    expect(scanSysfsPrinters(sysfs.root.path).single.name, 'USB 483:5743');
    expect(scanSysfsPrinters('${sysfs.root.path}/nope'), isEmpty);
  });

  test('the transport lists devices as app-level UsbPrinterDevice, and reports a vanished printer clearly', () async {
    sysfs.device('1-1', vid: '0483', pid: '5743', product: 'USB Printer Port');
    sysfs.iface('1-1:1.0', cls: '07');
    sysfs.endpoint('1-1:1.0', '01', direction: 'out');
    final transport = LinuxUsbTransport(sysfsRoot: sysfs.root.path);

    final devices = await transport.listDevices();
    expect(devices.single.key, '1155:22339');

    const gone = UsbPrinterDevice(vendorId: 1, productId: 2, name: 'Débranchée');
    expect(await transport.requestPermission(gone), isFalse);
    expect(() => transport.write(gone, Uint8List(0)), throwsA(isA<UsbPrinterException>()));
  });

  test('on Linux the default transport is the libusb one', () {
    expect(defaultUsbTransport(), isA<LinuxUsbTransport>());
  }, skip: Platform.isLinux ? null : 'Linux only');
}
