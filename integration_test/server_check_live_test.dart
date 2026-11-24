// Le test de connexion de l'ecran de configuration (verifyServer) contre un vrai serveur, avec les delais
// et en-tetes de l'app. flutter test integration_test/server_check_live_test.dart -d linux \
//   --dart-define=LIVE_API=https://192.168.3.20:8443 --dart-define=TRUST_CA_FP=AA:BB:...
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/net/server_check.dart';
import 'package:monokek_flutter/core/net/trusted_ca.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';

const _api = String.fromEnvironment('LIVE_API', defaultValue: 'http://127.0.0.1:8090');
const _caFingerprint = String.fromEnvironment('TRUST_CA_FP');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() => TrustedCa.install(null));

  testWidgets('verifyServer: serveur reel OK, adresse fausse -> cause precise', (t) async {
    await t.runAsync(() async {
      HttpOverrides.global = TrustingHttpOverrides();
      final base = resolveBaseUrl(_api);

      if (base.startsWith('https://')) {
        // Sans CA: le certificat doit etre refuse, et classe comme tel.
        TrustedCa.install(null);
        Object? untrusted;
        try {
          await verifyServer(base);
        } catch (e) {
          untrusted = e;
        }
        expect(untrusted, isNotNull);
        debugPrint('SANS CA: ${classifyLicenseError(untrusted!).kind.name} / ${classifyLicenseError(untrusted).detail}');
        expect(classifyLicenseError(untrusted).kind, LicenseFailureKind.certificate);

        final pem = await TrustedCa.download(base);
        expect(TrustedCa.fingerprint(pem), _caFingerprint.toUpperCase(), reason: 'empreinte differente: refus');
        TrustedCa.install(pem);
      }

      await verifyServer(base);
      debugPrint('SERVEUR REEL: verifyServer OK ($base)');

      // Port ferme: refus de connexion -> reseau.
      final host = Uri.parse(base).host;
      Object? refused;
      try {
        await verifyServer('http://$host:9', dio: Dio(defaultClientOptions()..connectTimeout = const Duration(seconds: 4)));
      } catch (e) {
        refused = e;
      }
      expect(refused, isNotNull);
      debugPrint('PORT FERME: ${classifyLicenseError(refused!).kind.name} / ${classifyLicenseError(refused).detail}');
      expect(classifyLicenseError(refused).kind, LicenseFailureKind.network);
    });
  });
}
