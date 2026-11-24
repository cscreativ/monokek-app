import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'usb_printer.dart';

/// A USB printer-class interface found under /sys/bus/usb/devices, with what libusb needs to write to it.
class LinuxUsbPrinter {
  const LinuxUsbPrinter({
    required this.vendorId,
    required this.productId,
    required this.name,
    required this.busNumber,
    required this.deviceNumber,
    required this.interfaceNumber,
    required this.endpointAddress,
  });

  final int vendorId;
  final int productId;
  final String name;
  final int busNumber;
  final int deviceNumber;
  final int interfaceNumber;

  /// Bulk OUT endpoint address (e.g. 0x01).
  final int endpointAddress;

  /// The device node libusb opens — shown in permission errors.
  String get node => '/dev/bus/usb/${busNumber.toString().padLeft(3, '0')}/${deviceNumber.toString().padLeft(3, '0')}';
}

/// Finds the USB printers (interface class 7 with a bulk OUT endpoint) by reading sysfs — plain files, no
/// native code, no permission needed. [root] is injectable so tests can point it at a fake tree.
List<LinuxUsbPrinter> scanSysfsPrinters([String root = '/sys/bus/usb/devices']) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];

  String? read(Directory d, String file) {
    try {
      return File('${d.path}/$file').readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  int? hex(String? s) => s == null ? null : int.tryParse(s, radix: 16);

  final found = <LinuxUsbPrinter>[];
  final entries = dir.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final device in entries) {
    final name = device.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name.contains(':')) continue; // interfaces are handled below, from their device
    final vid = hex(read(device, 'idVendor'));
    final pid = hex(read(device, 'idProduct'));
    if (vid == null || pid == null) continue;

    for (final intf in entries.where((e) => e.path.startsWith('${device.path}:'))) {
      if (hex(read(intf, 'bInterfaceClass')) != 7) continue;
      final number = hex(read(intf, 'bInterfaceNumber'));
      if (number == null) continue;
      final out = intf.listSync().whereType<Directory>().where((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('ep_')).where(
            (ep) => read(ep, 'direction') == 'out' && read(ep, 'type')?.toLowerCase() == 'bulk',
          );
      final address = out.isEmpty ? null : hex(read(out.first, 'bEndpointAddress'));
      if (address == null) continue;

      found.add(LinuxUsbPrinter(
        vendorId: vid,
        productId: pid,
        name: read(device, 'product') ?? 'USB ${vid.toRadixString(16)}:${pid.toRadixString(16)}',
        busNumber: int.tryParse(read(device, 'busnum') ?? '') ?? 0,
        deviceNumber: int.tryParse(read(device, 'devnum') ?? '') ?? 0,
        interfaceNumber: number,
        endpointAddress: address,
      ));
      break; // one printer interface per device is enough
    }
  }
  return found;
}

/// Linux: printers found through sysfs, written to through libusb (`libusb-1.0.so.0`), claiming the printer
/// interface and sending raw ESC/POS on its bulk OUT endpoint — the same path as the Android plugin. Needs
/// read/write access to the device node: see linux/udev/99-monokek-usb-printer.rules.
class LinuxUsbTransport implements UsbPrinterTransport {
  const LinuxUsbTransport({this.sysfsRoot = '/sys/bus/usb/devices'});
  final String sysfsRoot;

  @override
  bool get isSupported => true;

  LinuxUsbPrinter? _find(UsbPrinterDevice d) =>
      scanSysfsPrinters(sysfsRoot).where((p) => p.vendorId == d.vendorId && p.productId == d.productId).firstOrNull;

  @override
  Future<List<UsbPrinterDevice>> listDevices() async =>
      scanSysfsPrinters(sysfsRoot).map((p) => UsbPrinterDevice(vendorId: p.vendorId, productId: p.productId, name: p.name)).toList();

  /// No consent dialog on Linux: "permission" is simply being allowed to open the device node.
  @override
  Future<bool> requestPermission(UsbPrinterDevice device) async {
    final printer = _find(device);
    if (printer == null) return false;
    return await Isolate.run(() => _canOpen(printer.vendorId, printer.productId));
  }

  @override
  Future<void> write(UsbPrinterDevice device, Uint8List bytes) async {
    final printer = _find(device);
    if (printer == null) throw const UsbPrinterException('Imprimante USB introuvable (débranchée ?)');
    final error = await Isolate.run(() => _writeBlocking(printer, bytes));
    if (error != null) throw UsbPrinterException(error);
  }
}

// --- libusb ----------------------------------------------------------------------------------------------

final _libusb = DynamicLibrary.open('libusb-1.0.so.0');

final _init = _libusb.lookupFunction<Int32 Function(Pointer<Pointer<Void>>), int Function(Pointer<Pointer<Void>>)>('libusb_init');
final _exit = _libusb.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('libusb_exit');
final _openVidPid = _libusb.lookupFunction<Pointer<Void> Function(Pointer<Void>, Uint16, Uint16), Pointer<Void> Function(Pointer<Void>, int, int)>('libusb_open_device_with_vid_pid');
final _close = _libusb.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('libusb_close');
final _kernelDriverActive = _libusb.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('libusb_kernel_driver_active');
final _detachKernelDriver = _libusb.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('libusb_detach_kernel_driver');
final _attachKernelDriver = _libusb.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('libusb_attach_kernel_driver');
final _claimInterface = _libusb.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('libusb_claim_interface');
final _releaseInterface = _libusb.lookupFunction<Int32 Function(Pointer<Void>, Int32), int Function(Pointer<Void>, int)>('libusb_release_interface');
final _bulkTransfer = _libusb.lookupFunction<Int32 Function(Pointer<Void>, Uint8, Pointer<Uint8>, Int32, Pointer<Int32>, Uint32), int Function(Pointer<Void>, int, Pointer<Uint8>, int, Pointer<Int32>, int)>('libusb_bulk_transfer');
final _strerror = _libusb.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('libusb_strerror');

const _chunk = 16 * 1024;
const _timeoutMs = 5000;
const _errorAccess = -3;
const _errorBusy = -6;

String _describe(int code) => '${_strerror(code).toDartString()} ($code)';

/// Runs in a worker isolate: runs [body] with an open handle on the printer, or returns why it could not.
String? _withHandle(int vendorId, int productId, String? Function(Pointer<Void> handle) body, {LinuxUsbPrinter? printer}) {
  final ctxOut = calloc<Pointer<Void>>();
  try {
    final init = _init(ctxOut);
    if (init != 0) return "libusb indisponible : ${_describe(init)}";
    final ctx = ctxOut.value;
    try {
      final handle = _openVidPid(ctx, vendorId, productId);
      if (handle == nullptr) {
        final node = printer?.node ?? '/dev/bus/usb';
        return "Impossible d'ouvrir l'imprimante USB ($node) : droits insuffisants ou appareil absent. "
            'Installez la règle udev linux/udev/99-monokek-usb-printer.rules puis rebranchez l\'imprimante.';
      }
      try {
        return body(handle);
      } finally {
        _close(handle);
      }
    } finally {
      _exit(ctx);
    }
  } finally {
    calloc.free(ctxOut);
  }
}

bool _canOpen(int vendorId, int productId) => _withHandle(vendorId, productId, (_) => null) == null;

String? _writeBlocking(LinuxUsbPrinter printer, Uint8List data) {
  return _withHandle(printer.vendorId, printer.productId, printer: printer, (handle) {
    // A kernel driver (usblp) may own the interface: take it over for the print, give it back afterwards.
    var detached = false;
    if (_kernelDriverActive(handle, printer.interfaceNumber) == 1) {
      final r = _detachKernelDriver(handle, printer.interfaceNumber);
      if (r != 0) return "Impossible de libérer l'imprimante du pilote système : ${_describe(r)}";
      detached = true;
    }
    try {
      final claim = _claimInterface(handle, printer.interfaceNumber);
      if (claim == _errorBusy) return "L'imprimante est utilisée par un autre programme (CUPS ?) : ${_describe(claim)}";
      if (claim == _errorAccess) return "Accès refusé à l'imprimante : ${_describe(claim)}";
      if (claim != 0) return "Impossible de réserver l'imprimante : ${_describe(claim)}";

      final buffer = calloc<Uint8>(_chunk);
      final sent = calloc<Int32>();
      try {
        var offset = 0;
        while (offset < data.length) {
          final n = math.min(_chunk, data.length - offset);
          buffer.asTypedList(n).setAll(0, Uint8List.sublistView(data, offset, offset + n));
          final r = _bulkTransfer(handle, printer.endpointAddress, buffer, n, sent, _timeoutMs);
          if (r != 0) return "L'imprimante ne répond pas (écrit $offset/${data.length} octets) : ${_describe(r)}";
          offset += sent.value;
        }
        return null;
      } finally {
        calloc.free(buffer);
        calloc.free(sent);
        _releaseInterface(handle, printer.interfaceNumber);
      }
    } finally {
      if (detached) _attachKernelDriver(handle, printer.interfaceNumber);
    }
  });
}
