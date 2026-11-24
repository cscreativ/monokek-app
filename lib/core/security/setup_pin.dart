import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../storage/app_storage.dart';

/// SHA-256 of the PIN — port of mono-kep-tauri/src/lib/setupPin.ts. A 4-digit space is trivially
/// brute-forceable with disk access: this deters casual tampering with the server address, it is not a vault.
String hashSetupPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

bool hasSetupPin(AppStorage s) => s.setupPinHash != null;

bool verifySetupPin(AppStorage s, String candidate) {
  final stored = s.setupPinHash;
  return stored != null && hashSetupPin(candidate) == stored;
}

Future<void> saveSetupPin(AppStorage s, String pin) => s.setSetupPinHash(hashSetupPin(pin));
