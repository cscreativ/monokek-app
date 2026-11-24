import 'dart:io';

import 'package:flutter/services.dart';

import 'linux_usb_transport.dart';
import 'windows_usb_transport.dart';

/// A USB device as the OS reports it. [key] (`vendorId:productId`) is what the terminal stores to find
/// "its" printer again after a restart or a re-plug; [isPrinter] = it exposes a USB printer-class interface.
class UsbPrinterDevice {
  const UsbPrinterDevice({required this.vendorId, required this.productId, required this.name, this.isPrinter = true});

  final int vendorId;
  final int productId;
  final String name;
  final bool isPrinter;

  String get key => '$vendorId:$productId';

  Map<String, dynamic> toJson() => {'vendorId': vendorId, 'productId': productId, 'name': name, 'isPrinter': isPrinter};

  factory UsbPrinterDevice.fromJson(Map<dynamic, dynamic> j) => UsbPrinterDevice(
        vendorId: (j['vendorId'] as num).toInt(),
        productId: (j['productId'] as num).toInt(),
        name: (j['name'] as String?) ?? 'USB ${j['vendorId']}:${j['productId']}',
        isPrinter: j['isPrinter'] as bool? ?? true,
      );
}

class UsbPrinterException implements Exception {
  const UsbPrinterException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Writes raw ESC/POS bytes to a USB printer. One implementation per platform; the rest of the app only
/// sees this interface, so the print worker is testable with a fake.
abstract class UsbPrinterTransport {
  /// False on platforms without an implementation yet (the print worker then stays idle).
  bool get isSupported;

  Future<List<UsbPrinterDevice>> listDevices();

  /// Asks the user for access to [device] if needed (Android shows a system dialog). True = granted.
  Future<bool> requestPermission(UsbPrinterDevice device);

  /// Sends [bytes] to the printer and returns once the OS accepted all of them. Throws [UsbPrinterException].
  Future<void> write(UsbPrinterDevice device, Uint8List bytes);
}

class UnsupportedUsbTransport implements UsbPrinterTransport {
  const UnsupportedUsbTransport();

  @override
  bool get isSupported => false;

  @override
  Future<List<UsbPrinterDevice>> listDevices() async => const [];

  @override
  Future<bool> requestPermission(UsbPrinterDevice device) async => false;

  @override
  Future<void> write(UsbPrinterDevice device, Uint8List bytes) =>
      throw const UsbPrinterException("L'impression USB n'est pas disponible sur cette plateforme");
}

/// Android: UsbManager through a small platform channel (see UsbPrinterPlugin.kt).
class AndroidUsbTransport implements UsbPrinterTransport {
  AndroidUsbTransport([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('com.monokek.pos/usb_printer');
  final MethodChannel _channel;

  @override
  bool get isSupported => true;

  @override
  Future<List<UsbPrinterDevice>> listDevices() async {
    final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>('list') ?? const [];
    return list.map(UsbPrinterDevice.fromJson).toList();
  }

  @override
  Future<bool> requestPermission(UsbPrinterDevice d) async =>
      await _channel.invokeMethod<bool>('requestPermission', {'vendorId': d.vendorId, 'productId': d.productId}) ?? false;

  @override
  Future<void> write(UsbPrinterDevice d, Uint8List bytes) async {
    try {
      await _channel.invokeMethod<void>('write', {'vendorId': d.vendorId, 'productId': d.productId, 'data': bytes});
    } on PlatformException catch (e) {
      throw UsbPrinterException(e.message ?? e.code);
    }
  }
}

UsbPrinterTransport defaultUsbTransport() {
  if (Platform.isAndroid) return AndroidUsbTransport();
  if (Platform.isWindows) return const WindowsUsbTransport();
  if (Platform.isLinux) return const LinuxUsbTransport();
  return const UnsupportedUsbTransport();
}
