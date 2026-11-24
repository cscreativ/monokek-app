// Terminal deja servi: une session perimee est enregistree. Avant le correctif, l'intercepteur envoyait
// ce Bearer a /api/license/status (401) et la garde affichait "SERVEUR INJOIGNABLE" alors que le serveur
// repond. Lancer: flutter test integration_test/stale_session_test.dart -d linux --dart-define=POS_CLIENT_SECRET=...
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monokek_flutter/core/net/trusted_ca.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/main.dart' as app;
import 'package:monokek_flutter/models/app_user.dart';

const _api = String.fromEnvironment('LIVE_API', defaultValue: '127.0.0.1:8090');
// HTTPS (Caddy "tls internal"): empreinte SHA-256 de la CA racine, confirmee par l'utilisateur. La CA n'est
// installee que si l'empreinte telechargee est IDENTIQUE, comme l'ecran de configuration le demande.
const _caFingerprint = String.fromEnvironment('TRUST_CA_FP');

bool _shown(String s) => find
    .byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toUpperCase().contains(s))
    .evaluate()
    .isNotEmpty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('session perimee enregistree: jamais "injoignable", arrivee au login', (t) async {
    final storage = (await t.runAsync(AppStorage.create))!;
    addTearDown(() async {
      await storage.remove('trusted-ca');
      await storage.remove('backend-ip');
      await storage.clearSession();
      TrustedCa.install(null);
    });
    await t.runAsync(() async {
      if (_api.startsWith('https://')) {
        expect(_caFingerprint, isNotEmpty, reason: 'TRUST_CA_FP requis pour un serveur HTTPS');
        final pem = await TrustedCa.download(_api);
        expect(TrustedCa.fingerprint(pem), _caFingerprint.toUpperCase(), reason: 'empreinte de la CA differente: refus');
        await storage.setTrustedCa(pem);
      }
      await storage.setBackendIp(_api);
      await storage.saveSession({
        'user': const AppUser(id: 4, uuid: 'stale', name: 'Waiter', role: 'waiter', permissions: [], branchId: 1).toJson(),
        'token': 'eyJhbGciOiJSUzI1NiJ9.e30.perime',
        'refreshToken': 'refresh-perime',
        'expiresAt': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
      });
    });

    await app.main();
    var sawUnreachable = false;
    var atLogin = false;
    for (var i = 0; i < 100 && !atLogin; i++) {
      await t.pump(const Duration(milliseconds: 200));
      if (_shown('INJOIGNABLE') || _shown('RÉPONSE INATTENDUE') || _shown('CERTIFICAT NON RECONNU')) sawUnreachable = true;
      atLogin = _shown('SE CONNECTER');
    }
    debugPrint('RESULTAT: injoignable affiche=$sawUnreachable, arrive au login=$atLogin');
    expect(sawUnreachable, isFalse, reason: 'la garde ne doit pas afficher une erreur serveur a cause du token perime');
    expect(atLogin, isTrue, reason: 'la session perimee doit etre abandonnee et mener au login');
  });
}
