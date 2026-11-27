import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local settings (backend IP, assigned register) and the persisted session.
/// Equivalent of the Tauri `.settings.json` store + the persisted Zustand auth store.
/// Loaded once before runApp so every getter is synchronous.
class AppStorage {
  AppStorage._(this._prefs, this._secure, this._session);

  static const _sessionKey = 'mono-kek-session';
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  Map<String, dynamic>? _session;

  static Future<AppStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage();
    String? raw;
    try {
      raw = await secure.read(key: _sessionKey);
    } catch (_) {
      raw = prefs.getString(_sessionKey); // keystore unavailable (e.g. Linux without libsecret)
    }
    Map<String, dynamic>? session;
    if (raw != null) {
      try {
        session = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    return AppStorage._(prefs, secure, session);
  }

  // --- Backend IP ("192.168.1.10:8080", or a full https URL) ---
  String? get backendIp => _prefs.getString('backend-ip');
  Future<void> setBackendIp(String value) => _prefs.setString('backend-ip', value);

  // --- Server CA (PEM) the user confirmed during setup — see core/net/trusted_ca.dart ---
  String? get trustedCa => _prefs.getString('trusted-ca');
  Future<void> setTrustedCa(String pem) => _prefs.setString('trusted-ca', pem);

  // --- Generic string slots (persisted cart, ...) ---
  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);

  // --- Admin PIN protecting the setup screen (SHA-256 hash, never the PIN itself) ---
  String? get setupPinHash => _prefs.getString('setup-pin-hash');
  Future<void> setSetupPinHash(String hash) => _prefs.setString('setup-pin-hash', hash);

  // --- Alert sounds on the waiter screens (per terminal) ---
  bool get alertSoundEnabled => _prefs.getBool('alert-sound-enabled') ?? true;
  double get alertSoundVolume => _prefs.getDouble('alert-sound-volume') ?? 1.0;
  Future<void> setAlertSound({required bool enabled, required double volume}) async {
    await _prefs.setBool('alert-sound-enabled', enabled);
    await _prefs.setDouble('alert-sound-volume', volume);
  }

  // --- Register assigned to this terminal ---
  int? get registerId => _prefs.getInt('register-id');
  String? get registerName => _prefs.getString('register-name');
  Future<void> setRegister(int id, String name) async {
    await _prefs.setInt('register-id', id);
    await _prefs.setString('register-name', name);
  }

  // --- Session ---
  Map<String, dynamic>? get session => _session;

  Future<void> saveSession(Map<String, dynamic> session) async {
    _session = session;
    final raw = jsonEncode(session);
    try {
      await _secure.write(key: _sessionKey, value: raw);
    } catch (_) {
      await _prefs.setString(_sessionKey, raw);
    }
  }

  Future<void> clearSession() async {
    _session = null;
    try {
      await _secure.delete(key: _sessionKey);
    } catch (_) {}
    await _prefs.remove(_sessionKey);
  }
}

/// Overridden in main() with the instance created before runApp.
final storageProvider = Provider<AppStorage>((ref) => throw UnimplementedError('storageProvider not overridden'));
