import 'dart:convert';

import '../storage/app_storage.dart';
import 'usb_printer.dart';

/// This terminal's local USB printer and WHICH server printers it stands for. A job is only ever printed here
/// when its printer id is in [printerIds] — otherwise a cashier tablet would also print the kitchen's tickets
/// just because it won the claim race.
class UsbPrinterBinding {
  const UsbPrinterBinding({required this.device, required this.printerIds, this.paperWidth = 58});

  final UsbPrinterDevice device;
  final Set<int> printerIds;
  final int paperWidth;

  Map<String, dynamic> toJson() => {'device': device.toJson(), 'printerIds': printerIds.toList(), 'paperWidth': paperWidth};

  factory UsbPrinterBinding.fromJson(Map<String, dynamic> j) => UsbPrinterBinding(
        device: UsbPrinterDevice.fromJson(j['device'] as Map<String, dynamic>),
        printerIds: (j['printerIds'] as List).map((e) => (e as num).toInt()).toSet(),
        paperWidth: (j['paperWidth'] as num?)?.toInt() ?? 58,
      );
}

class UsbPrinterSettings {
  UsbPrinterSettings(this._storage);
  final AppStorage _storage;

  static const _key = 'usb-printer';

  UsbPrinterBinding? get binding {
    final raw = _storage.getString(_key);
    if (raw == null) return null;
    try {
      return UsbPrinterBinding.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // unreadable → behave as "not configured"
    }
  }

  Future<void> save(UsbPrinterBinding binding) => _storage.setString(_key, jsonEncode(binding.toJson()));

  Future<void> clear() => _storage.remove(_key);
}
