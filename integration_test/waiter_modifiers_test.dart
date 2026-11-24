// Vrai parcours waiter sur la vraie app (fenetre Linux) contre un vrai backend:
//   flutter test integration_test/waiter_modifiers_test.dart -d linux \
//     --dart-define=POS_CLIENT_SECRET=... [--dart-define=LIVE_API=127.0.0.1:8090] [--dart-define=TEST_PRODUCT=ZZ TEST]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:monokek_flutter/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

const _api = String.fromEnvironment('LIVE_API', defaultValue: '127.0.0.1:8090');
const _product = String.fromEnvironment('TEST_PRODUCT', defaultValue: 'ZZ TEST');

Finder exact(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase() == s.toLowerCase());

Finder txt(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase().contains(s.toLowerCase()));

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 20}) async {
  for (var i = 0; i < seconds * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('introuvable apres ${seconds}s: $f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('waiter: table -> plat -> popup options -> panier', (t) async {
    SharedPreferences.setMockInitialValues({'backend-ip': _api});
    await app.main();
    await t.pump(const Duration(seconds: 2));

    // login (ou session deja ouverte d'un run precedent)
    await waitFor(t, find.byWidgetPredicate((w) => w is Text && (w.data == 'SE CONNECTER' || (w.data ?? '').contains('PERS.') || (w.data ?? '') == 'QUITTER')), seconds: 30);
    if (find.text('SE CONNECTER').evaluate().isNotEmpty) {
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'waiter@resto.com');
      await t.enterText(fields.at(1), 'password');
      await t.tap(find.text('SE CONNECTER'));
    } else {
      debugPrint('SESSION: deja connecte');
    }
    await waitFor(t, txt('SESSION'), seconds: 30);

    // premiere table
    await waitFor(t, find.textContaining('PERS.'));
    await t.tap(find.textContaining('PERS.').first);
    await waitFor(t, exact(_product), seconds: 30);
    debugPrint('MENU: plat "$_product" affiche');

    // actualisation du menu: le plat doit rester/reapparaitre
    await t.tap(find.byIcon(LucideIcons.refreshCw));
    await t.pump(const Duration(milliseconds: 300));
    await waitFor(t, exact(_product), seconds: 20);
    debugPrint('REFRESH: menu recharge, plat toujours affiche');

    // clic -> popup
    await t.tap(exact(_product).first);
    await waitFor(t, txt('OPTIONS'));
    debugPrint('POPUP: ouvert');

    // choix: 1er bouton Ajouter (supplement) + premier radio accompagnement si present
    final confirm = find.widgetWithText(FilledButton, 'CONFIRMER LA SÉLECTION');
    final add = find.widgetWithText(OutlinedButton, 'Ajouter');
    if (add.evaluate().isNotEmpty) {
      await t.tap(add.first);
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(t.widget<FilledButton>(confirm).onPressed, isNotNull, reason: 'confirmer doit etre actif');
    await t.tap(confirm);
    await t.pump(const Duration(seconds: 1));
    expect(txt('OPTIONS'), findsNothing);
    expect(find.textContaining('+ '), findsWidgets, reason: 'une option doit apparaitre dans le panier');
    debugPrint('PANIER: ${find.textContaining('/ unité').evaluate().map((e) => (e.widget as Text).data).toList()}');
  });
}
