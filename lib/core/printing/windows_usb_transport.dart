import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'usb_print_path.dart';
import 'usb_printer.dart';

/// Windows: direct USB access to printer-class devices through the stock `usbprint` driver's device interface
/// (SetupAPI to find them, CreateFile + WriteFile to print). No spooler, no driver swap. Devices are addressed
/// by vendorId/productId read from the device path; two identical printers on one PC are not told apart.
class WindowsUsbTransport implements UsbPrinterTransport {
  const WindowsUsbTransport();

  @override
  bool get isSupported => true;

  @override
  Future<List<UsbPrinterDevice>> listDevices() async {
    final devices = <UsbPrinterDevice>[];
    for (final f in _enumerate()) {
      final ids = parseUsbPrintPath(f.path);
      if (ids == null) continue;
      devices.add(UsbPrinterDevice(vendorId: ids.vendorId, productId: ids.productId, name: f.name));
    }
    return devices;
  }

  /// Windows has no per-device USB consent dialog: the printer is either openable or not.
  @override
  Future<bool> requestPermission(UsbPrinterDevice device) async => true;

  @override
  Future<void> write(UsbPrinterDevice device, Uint8List bytes) async {
    // Resolved at each write: the path changes when the printer is re-plugged.
    final path = _enumerate().where((f) {
      final ids = parseUsbPrintPath(f.path);
      return ids != null && ids.vendorId == device.vendorId && ids.productId == device.productId;
    }).map((f) => f.path).firstOrNull;
    if (path == null) throw const UsbPrinterException('Imprimante USB introuvable (débranchée ?)');

    // Off the UI isolate: WriteFile blocks while a busy printer drains its buffer.
    final error = await Isolate.run(() => _writeBlocking(path, bytes));
    if (error != null) throw UsbPrinterException(error);
  }
}

// --- Win32 -----------------------------------------------------------------------------------------------

final _setupapi = DynamicLibrary.open('setupapi.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _getClassDevs = _setupapi.lookupFunction<IntPtr Function(Pointer<Uint8>, Pointer<Utf16>, IntPtr, Uint32), int Function(Pointer<Uint8>, Pointer<Utf16>, int, int)>('SetupDiGetClassDevsW');
final _enumInterfaces = _setupapi.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Pointer<Uint8>, Uint32, Pointer<Uint8>), int Function(int, Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint8>)>('SetupDiEnumDeviceInterfaces');
final _getInterfaceDetail = _setupapi.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint8>), int Function(int, Pointer<Uint8>, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint8>)>('SetupDiGetDeviceInterfaceDetailW');
final _getRegistryProperty = _setupapi.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint8>, Uint32, Pointer<Uint32>), int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint8>, int, Pointer<Uint32>)>('SetupDiGetDeviceRegistryPropertyW');
final _destroyDeviceInfoList = _setupapi.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetupDiDestroyDeviceInfoList');

final _createFile = _kernel32.lookupFunction<IntPtr Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>, Uint32, Uint32, IntPtr), int Function(Pointer<Utf16>, int, int, Pointer<Uint8>, int, int, int)>('CreateFileW');
final _writeFile = _kernel32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint8>), int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint8>)>('WriteFile');
final _closeHandle = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _getLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

const _digcfPresent = 0x2;
const _digcfDeviceInterface = 0x10;
const _spdrpDeviceDesc = 0x0;
const _spdrpFriendlyName = 0xC;
const _genericWrite = 0x40000000;
const _fileShareReadWrite = 0x3;
const _openExisting = 3;
const _fileAttributeNormal = 0x80;
const _invalidHandle = -1;
const _writeChunk = 32 * 1024;

class _Found {
  const _Found(this.path, this.name);
  final String path;
  final String name;
}

/// Every USB printer-class interface currently present, with its device path and a human name.
List<_Found> _enumerate() {
  final pointerSize = sizeOf<IntPtr>();
  final guid = calloc<Uint8>(16)..asTypedList(16).setAll(0, usbPrintInterfaceGuid);
  final devInfo = _getClassDevs(guid, nullptr, 0, _digcfPresent | _digcfDeviceInterface);
  if (devInfo == _invalidHandle) {
    calloc.free(guid);
    return const [];
  }

  final structSize = setupStructSize(pointerSize);
  final iface = calloc<Uint8>(structSize);
  final devData = calloc<Uint8>(structSize);
  final required = calloc<Uint32>();
  final found = <_Found>[];
  try {
    for (var i = 0;; i++) {
      iface.cast<Uint32>().value = structSize; // cbSize must be set before every call
      if (_enumInterfaces(devInfo, nullptr, guid, i, iface) == 0) break; // ERROR_NO_MORE_ITEMS

      _getInterfaceDetail(devInfo, iface, nullptr, 0, required, nullptr); // size query: fails on purpose
      final size = required.value;
      if (size < 8) continue;
      final detail = calloc<Uint8>(size);
      try {
        detail.cast<Uint32>().value = deviceInterfaceDetailCbSize(pointerSize);
        devData.cast<Uint32>().value = structSize;
        if (_getInterfaceDetail(devInfo, iface, detail, size, nullptr, devData) == 0) continue;
        final path = Pointer<Utf16>.fromAddress(detail.address + 4).toDartString(); // DevicePath follows the DWORD cbSize
        found.add(_Found(path, _deviceName(devInfo, devData)));
      } finally {
        calloc.free(detail);
      }
    }
  } finally {
    calloc.free(iface);
    calloc.free(devData);
    calloc.free(required);
    calloc.free(guid);
    _destroyDeviceInfoList(devInfo);
  }
  return found;
}

String _deviceName(int devInfo, Pointer<Uint8> devData) {
  final buffer = calloc<Uint8>(512);
  final required = calloc<Uint32>();
  try {
    for (final property in const [_spdrpFriendlyName, _spdrpDeviceDesc]) {
      if (_getRegistryProperty(devInfo, devData, property, nullptr, buffer, 512, required) != 0) {
        final name = buffer.cast<Utf16>().toDartString();
        if (name.isNotEmpty) return name;
      }
    }
  } finally {
    calloc.free(buffer);
    calloc.free(required);
  }
  return 'Imprimante USB';
}

/// Runs in a worker isolate. Returns an error message, or null when every byte was accepted by the printer.
String? _writeBlocking(String path, Uint8List data) {
  final pathPtr = path.toNativeUtf16();
  try {
    final handle = _createFile(pathPtr, _genericWrite, _fileShareReadWrite, nullptr, _openExisting, _fileAttributeNormal, 0);
    if (handle == _invalidHandle) {
      return "Impossible d'ouvrir l'imprimante USB (code ${_getLastError()}) — est-elle utilisée par un autre programme ?";
    }
    final buffer = calloc<Uint8>(_writeChunk);
    final written = calloc<Uint32>();
    try {
      var offset = 0;
      while (offset < data.length) {
        final n = math.min(_writeChunk, data.length - offset);
        buffer.asTypedList(n).setAll(0, Uint8List.sublistView(data, offset, offset + n));
        if (_writeFile(handle, buffer, n, written, nullptr) == 0 || written.value == 0) {
          return "L'imprimante ne répond pas (écrit $offset/${data.length} octets, code ${_getLastError()})";
        }
        offset += written.value;
      }
      return null;
    } finally {
      calloc.free(buffer);
      calloc.free(written);
      _closeHandle(handle);
    }
  } finally {
    calloc.free(pathPtr);
  }
}
