// Ecran des suppléments/accompagnements (popup d'options) sur la vraie app contre un vrai backend, en LECTURE
// SEULE: aucun round n'est envoye, aucune commande creee, rien n'est modifie cote serveur.
//   flutter test integration_test/supplements_live_test.dart -d linux \
//     --dart-define=LIVE_API=https://192.168.3.20:8443 --dart-define=TRUST_CA_FP=AA:BB:... \
//     --dart-define=WAITER_EMAIL=... --dart-define=WAITER_PASSWORD=... [--dart-define=TEST_PRODUCT=nom]
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/format.dart';
import 'package:monokek_flutter/core/net/trusted_ca.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/main.dart' as app;
import 'package:monokek_flutter/models/catalog.dart';

const _api = String.fromEnvironment('LIVE_API', defaultValue: 'http://127.0.0.1:8090');
const _caFingerprint = String.fromEnvironment('TRUST_CA_FP');
const _email = String.fromEnvironment('WAITER_EMAIL', defaultValue: 'waiter@resto.com');
const _password = String.fromEnvironment('WAITER_PASSWORD', defaultValue: 'password');
const _wanted = String.fromEnvironment('TEST_PRODUCT');

Finder exact(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase() == s.toLowerCase());
Finder txt(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase().contains(s.toLowerCase()));

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 25}) async {
  for (var i = 0; i < seconds * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('introuvable apres ${seconds}s: $f');
}

/// Read-only: the waiter's menu exactly as the app receives it.
Future<List<Product>> fetchMenu(String base) async {
  final dio = Dio(defaultClientOptions());
  final login = await dio.post('$base/api/login', data: {'email': _email, 'password': _password, 'deviceName': 'Flutter POS Terminal'});
  final token = (login.data['data'] as Map)['token'] as String;
  final res = await dio.get('$base/api/pos/products', options: Options(headers: {'Authorization': 'Bearer $token'}));
  return (res.data as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ecran supplements: popup, regles, selection, panier', (t) async {
    final base = resolveBaseUrl(_api);
    final storage = (await t.runAsync(AppStorage.create))!;
    addTearDown(() async {
      for (final k in ['trusted-ca', 'backend-ip', 'mono-kek-cart-storage']) {
        await storage.remove(k);
      }
      await storage.clearSession();
      TrustedCa.install(null);
    });

    late List<Product> menu;
    await t.runAsync(() async {
      HttpOverrides.global = TrustingHttpOverrides();
      if (base.startsWith('https://')) {
        final pem = await TrustedCa.download(base);
        expect(TrustedCa.fingerprint(pem), _caFingerprint.toUpperCase(), reason: 'empreinte de la CA differente: refus');
        await storage.setTrustedCa(pem);
        TrustedCa.install(pem);
      }
      await storage.setBackendIp(_api);
      await storage.clearSession();
      await storage.remove('mono-kek-cart-storage');
      menu = await fetchMenu(base);
    });

    final withOptions = menu.where((p) => p.modifiers.isNotEmpty).toList();
    debugPrint('MENU: ${menu.length} plats, ${withOptions.length} avec options');
    for (final p in menu) {
      debugPrint('  ${p.modifiers.isEmpty ? '  ' : '+ '}${p.name}'
          '${p.modifiers.isEmpty ? '' : '  ->  ${p.modifiers.map((m) => '${m.name} [${m.type}, ${m.ruleLabel}, ${m.items.length} choix]').join(' | ')}'}');
    }
    if (withOptions.isEmpty) {
      debugPrint('CONCLUSION: aucun plat de ce serveur n a de groupe d options lie -> le popup ne peut pas s ouvrir');
      return;
    }
    // Prefer the product with the most rules to exercise (required groups first).
    withOptions.sort((a, b) => b.modifiers.where((m) => m.effectiveMin > 0).length.compareTo(a.modifiers.where((m) => m.effectiveMin > 0).length));
    final product = _wanted.isEmpty ? withOptions.first : withOptions.firstWhere((p) => p.name.toLowerCase() == _wanted.toLowerCase());
    debugPrint('PLAT TESTE: ${product.name}');

    await app.main();
    await t.pump(const Duration(seconds: 2));
    await waitFor(t, find.text('SE CONNECTER'));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), _email);
    await t.enterText(fields.at(1), _password);
    await t.tap(find.text('SE CONNECTER'));
    await waitFor(t, txt('SESSION'), seconds: 40);

    await waitFor(t, find.textContaining('PERS.'));
    await t.tap(find.textContaining('PERS.').first);
    await waitFor(t, exact(product.name), seconds: 40);
    debugPrint('MENU UI: plat affiche');

    await t.tap(exact(product.name).first);
    await waitFor(t, txt('OPTIONS'));
    debugPrint('POPUP: ouvert');
    for (final g in product.modifiers) {
      expect(txt(g.name), findsWidgets, reason: 'groupe ${g.name} absent du popup');
      expect(txt(g.ruleLabel), findsWidgets, reason: 'regle "${g.ruleLabel}" absente pour ${g.name}');
      for (final i in g.items) {
        expect(exact(i.name), findsWidgets, reason: 'choix ${i.name} absent');
      }
    }
    debugPrint('POPUP: groupes, regles et choix affiches');

    final confirm = find.widgetWithText(FilledButton, 'CONFIRMER LA SÉLECTION');
    final needs = product.modifiers.any((m) => m.effectiveMin > 0);
    if (needs) {
      expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'confirmer doit etre desactive tant qu un groupe obligatoire est vide');
      debugPrint('REGLE: confirmer desactive tant que les groupes obligatoires sont vides');
    }

    // Satisfy each group's minimum with its first choices.
    var extra = 0.0;
    final chosen = <String>[];
    for (final g in product.modifiers.where((m) => m.effectiveMin > 0)) {
      final single = g.maxSelect == 1;
      for (var n = 0; n < g.effectiveMin; n++) {
        final item = g.items[single ? 0 : n % g.items.length];
        if (single) {
          await t.tap(exact(item.name).first);
        } else {
          final row = find.ancestor(of: exact(item.name), matching: find.byType(InkWell)).first;
          final add = find.descendant(of: row, matching: find.widgetWithText(OutlinedButton, 'Ajouter'));
          if (add.evaluate().isNotEmpty) {
            await t.tap(add.first);
          } else {
            await t.tap(find.descendant(of: row, matching: find.byIcon(Icons.add)).first); // + button once selected
          }
        }
        await t.pump(const Duration(milliseconds: 250));
        extra += item.price;
        chosen.add(item.name);
      }
    }
    debugPrint('SELECTION: ${chosen.isEmpty ? '(aucune, groupes facultatifs)' : chosen.join(', ')}');
    expect(t.widget<FilledButton>(confirm).onPressed, isNotNull, reason: 'confirmer doit etre actif apres la selection');

    await t.tap(confirm);
    await t.pump(const Duration(seconds: 1));
    expect(txt('OPTIONS'), findsNothing, reason: 'le popup doit se fermer');
    for (final n in chosen.toSet()) {
      expect(txt('+ $n'), findsWidgets, reason: 'option $n absente du panier');
    }
    final expected = formatCurrency(product.price + extra);
    debugPrint('PANIER: attendu $expected / unité, affiche ${find.textContaining('/ unité').evaluate().map((e) => (e.widget as Text).data).toList()}');
    expect(txt('$expected / unité'), findsWidgets, reason: 'prix unitaire (plat + options) incorrect');
    debugPrint('RESULTAT: OK (aucun round envoye)');
  });
}
