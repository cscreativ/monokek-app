import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The server's HTTPS certificate is signed by Caddy's own internal CA (`tls internal`), which no
/// phone or PC knows. Dart's HttpClient ignores certificates the user installs in Android's settings
/// (it only reads the system store), so the app carries the CA itself: it downloads it once from
/// `<server>/ca.crt` during setup, the user confirms its fingerprint, and from then on every
/// dart:io connection (Dio, Image.network, SSE) also trusts it — see [TrustingHttpOverrides].
///
/// Only this CA is added: system roots stay trusted, and no certificate error is ever ignored.
class TrustedCa {
  TrustedCa._();

  static String? _pem;
  static SecurityContext? _context;

  static String? get pem => _pem;

  /// Call at startup (stored value) and after the user accepts a new CA. null = system roots only.
  static void install(String? pem) {
    _pem = (pem == null || pem.trim().isEmpty) ? null : pem;
    _context = null;
  }

  static SecurityContext? get context {
    final pem = _pem;
    if (pem == null) return null;
    return _context ??= (SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(utf8.encode(pem)));
  }

  /// SHA-256 of the DER certificate, formatted `AB:CD:…` — what the user compares/confirms.
  static String fingerprint(String pem) {
    final der = base64.decode(
      pem
          .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
          .replaceAll(RegExp(r'\s'), ''),
    );
    return sha256
        .convert(der)
        .bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  /// Downloads the root certificate from the server. Certificate checks are skipped for THIS request
  /// only (the CA is public — it is exactly the thing we cannot verify yet); the result is not trusted
  /// until the user confirms its fingerprint, and it must parse as a certificate.
  static Future<String> download(String baseUrl) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/ca.crt'));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw const HttpException('ca.crt indisponible');
      }
      return _validated(
        await utf8.decodeStream(res).timeout(const Duration(seconds: 10)),
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _validated(String body) {
    final pem = body.trim();
    if (!pem.startsWith('-----BEGIN CERTIFICATE-----') || pem.length > 8192) {
      throw const FormatException('Certificat invalide');
    }
    fingerprint(pem); // throws if the base64 body is not valid
    return pem;
  }
}

/// Makes every `HttpClient()` created by dart:io (hence Dio's default adapter) trust [TrustedCa].
class TrustingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? TrustedCa.context);
}
