/// Windows exposes every USB printer-class device (what Xprinter & co are) through the stock `usbprint` driver
/// as a device interface of this class — no vendor driver, no Zadig: its path can be opened with CreateFile and
/// written to directly. Pure helpers here (no FFI) so they are unit-tested on any OS.
///
/// GUID_DEVINTERFACE_USBPRINT = {28d78fad-5a12-11d1-ae5b-0000f803a8c2}, as the 16 bytes of a Windows GUID
/// (Data1/Data2/Data3 little-endian, Data4 as is).
const usbPrintInterfaceGuid = <int>[
  0xAD, 0x8F, 0xD7, 0x28, // Data1 0x28d78fad
  0x12, 0x5A, // Data2 0x5a12
  0xD1, 0x11, // Data3 0x11d1
  0xAE, 0x5B, 0x00, 0x00, 0xF8, 0x03, 0xA8, 0xC2, // Data4
];

/// `\\?\usb#vid_0483&pid_5743#5&2a5b3c7&0&2#{28d78fad-…}` → (0x0483, 0x5743). Null when the path has no ids.
({int vendorId, int productId})? parseUsbPrintPath(String path) {
  final m = RegExp(r'vid_([0-9a-f]{4})&pid_([0-9a-f]{4})', caseSensitive: false).firstMatch(path);
  if (m == null) return null;
  return (vendorId: int.parse(m.group(1)!, radix: 16), productId: int.parse(m.group(2)!, radix: 16));
}

/// sizeof(SP_DEVICE_INTERFACE_DATA) == sizeof(SP_DEVINFO_DATA): DWORD + GUID + DWORD + ULONG_PTR,
/// the pointer being aligned (32 bytes on 64-bit Windows, 28 on 32-bit).
int setupStructSize(int pointerSize) => 24 + pointerSize;

/// cbSize of SP_DEVICE_INTERFACE_DETAIL_DATA_W: the documented quirk — 8 on 64-bit, 6 on 32-bit — not sizeof().
int deviceInterfaceDetailCbSize(int pointerSize) => pointerSize == 8 ? 8 : 6;
