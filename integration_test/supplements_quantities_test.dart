// Suppléments payants sur la vraie app contre un vrai backend: choix, quantites (+/-), retrait, prix et
// contenu EXACT du panier (ce que le round enverrait). Ne cree aucune commande.
//   flutter test integration_test/supplements_quantities_test.dart -d linux [--dart-define=LIVE_API=...]
// Attend le plat "ZZ TEST": un groupe d'accompagnement (choix unique) et un groupe de suppléments payants
// obligatoire (au moins 1, sans maximum) avec au moins 2 choix.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:monokek_flutter/core/api/api_client.dart';
import 'package:monokek_flutter/core/format.dart';
import 'package:monokek_flutter/core/net/trusted_ca.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/features/pos/cart_store.dart';
import 'package:monokek_flutter/main.dart' as app;
import 'package:monokek_flutter/models/catalog.dart';

const _api = String.fromEnvironment('LIVE_API', defaultValue: 'http://127.0.0.1:8090');
const _email = String.fromEnvironment('WAITER_EMAIL', defaultValue: 'waiter@resto.com');
const _password = String.fromEnvironment('WAITER_PASSWORD', defaultValue: 'password');
const _productName = String.fromEnvironment('TEST_PRODUCT', defaultValue: 'ZZ TEST');

Finder exact(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase() == s.toLowerCase());
Finder txt(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase().contains(s.toLowerCase()));

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 25}) async {
  for (var i = 0; i < seconds * 5; i++) {
    await t.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('introuvable apres ${seconds}s: $f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('supplements payants: quantites, retrait, prix, contenu du panier', (t) async {
    final base = resolveBaseUrl(_api);
    final storage = (await t.runAsync(AppStorage.create))!;
    addTearDown(() async {
      for (final k in ['trusted-ca', 'backend-ip', 'mono-kek-cart-storage']) {
        await storage.remove(k);
      }
      await storage.clearSession();
      TrustedCa.install(null);
    });

    late Product product;
    await t.runAsync(() async {
      HttpOverrides.global = TrustingHttpOverrides();
      await storage.setBackendIp(_api);
      await storage.clearSession();
      await storage.remove('mono-kek-cart-storage');
      final dio = Dio(defaultClientOptions());
      final login = await dio.post('$base/api/login', data: {'email': _email, 'password': _password, 'deviceName': 'Flutter POS Terminal'});
      final token = (login.data['data'] as Map)['token'] as String;
      final res = await dio.get('$base/api/pos/products', options: Options(headers: {'Authorization': 'Bearer $token'}));
      product = (res.data as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).firstWhere((p) => p.name == _productName);
    });

    final acc = product.modifiers.firstWhere((m) => m.maxSelect == 1);
    final sup = product.modifiers.firstWhere((m) => m.type == 'supplement');
    expect(sup.items.length, greaterThanOrEqualTo(2));
    expect(sup.items.any((i) => i.price > 0), isTrue, reason: 'il faut des supplements payants');
    final riz = acc.items.first;
    final a = sup.items[0];
    final b = sup.items[1];
    debugPrint('PLAT: ${product.name} ${product.price} | accompagnement=${acc.name}(${riz.name} ${riz.price}) | supplements=${sup.name} min=${sup.effectiveMin} max=${sup.maxSelect} '
        '(${a.name} ${a.price}, ${b.name} ${b.price})');

    await app.main();
    await t.pump(const Duration(seconds: 2));
    await waitFor(t, find.text('SE CONNECTER'));
    await t.enterText(find.byType(TextFormField).at(0), _email);
    await t.enterText(find.byType(TextFormField).at(1), _password);
    await t.tap(find.text('SE CONNECTER'));
    await waitFor(t, txt('SESSION'), seconds: 40);
    await waitFor(t, find.textContaining('PERS.'));
    await t.tap(find.textContaining('PERS.').first);
    await waitFor(t, exact(product.name), seconds: 40);

    final confirm = find.widgetWithText(FilledButton, 'CONFIRMER LA SÉLECTION');
    Finder row(String name) => find.ancestor(of: exact(name), matching: find.byType(InkWell)).first;
    Finder add(String name) => find.descendant(of: row(name), matching: find.widgetWithText(OutlinedButton, 'Ajouter'));
    Finder plus(String name) => find.descendant(of: row(name), matching: find.byIcon(LucideIcons.plus));
    Finder minus(String name) => find.descendant(of: row(name), matching: find.byIcon(LucideIcons.minus));
    Future<void> tapBy(Finder f) async {
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 300));
    }

    // --- ouverture + regles
    await t.tap(exact(product.name).first);
    await waitFor(t, txt('OPTIONS'));
    expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'supplement obligatoire: confirmer desactive');
    debugPrint('1. popup ouvert, confirmer desactive (supplement obligatoire "${sup.ruleLabel}")');

    // accompagnement a choix unique: seul le dernier choix reste selectionne
    await tapBy(exact(riz.name).first);
    expect(t.widget<FilledButton>(confirm).onPressed, isNull, reason: 'l accompagnement seul ne suffit pas');
    debugPrint('2. accompagnement choisi, confirmer reste desactive tant qu aucun supplement');

    // --- supplements: ajouter A, +1 => x2, ajouter B puis le retirer
    await tapBy(add(a.name));
    expect(t.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tapBy(plus(a.name));
    await tapBy(add(b.name));
    await tapBy(minus(b.name)); // B x1 -> retire
    expect(add(b.name), findsOneWidget, reason: '${b.name} doit redevenir "Ajouter" apres retrait');
    expect(exact('2'), findsWidgets, reason: '${a.name} doit etre a x2');
    debugPrint('3. ${a.name} x2 (+), ${b.name} ajoute puis retire (-): ${b.name} de nouveau "Ajouter"');

    await tapBy(confirm);
    await t.pump(const Duration(seconds: 1));
    expect(txt('OPTIONS'), findsNothing);

    // --- panier: affichage et contenu exact
    final expected = product.price + riz.price + a.price * 2;
    expect(txt('+ ${riz.name}'), findsWidgets);
    expect(txt('+ ${a.name} ×2'), findsWidgets, reason: 'la quantite du supplement doit apparaitre (×2)');
    expect(txt('+ ${b.name}'), findsNothing, reason: '${b.name} a ete retire');
    expect(txt('${formatCurrency(expected)} / unité'), findsWidgets, reason: 'prix unitaire attendu ${formatCurrency(expected)}');

    final container = ProviderScope.containerOf(t.element(find.byType(MaterialApp)));
    final cart = container.read(cartProvider);
    expect(cart.items, hasLength(1));
    final line = cart.items.single;
    final payload = [for (final m in line.modifiers) {'modifierItemId': m.id, 'quantity': m.quantity < 1 ? 1 : m.quantity}];
    debugPrint('4. panier: ${line.qty}x ${line.name}, unite=${line.unitPrice} (attendu $expected)');
    debugPrint('5. modifiers qui seraient envoyes au serveur: $payload');
    expect(line.unitPrice, expected);
    expect(payload.map((m) => '${m['modifierItemId']}:${m['quantity']}').toSet(), {'${riz.id}:1', '${a.id}:2'});

    // --- meme plat, autre combinaison => deuxieme ligne; meme combinaison => fusion
    await t.tap(exact(product.name).first);
    await waitFor(t, txt('OPTIONS'));
    await tapBy(exact(riz.name).first);
    await tapBy(add(a.name));
    await tapBy(plus(a.name)); // memes choix: Riz + A x2
    await tapBy(confirm);
    await t.pump(const Duration(seconds: 1));
    final merged = container.read(cartProvider).items;
    expect(merged, hasLength(1), reason: 'memes options: la ligne doit fusionner');
    expect(merged.single.qty, 2);
    debugPrint('6. memes options choisies une 2e fois: une seule ligne, quantite ${merged.single.qty}');

    await t.tap(exact(product.name).first);
    await waitFor(t, txt('OPTIONS'));
    await tapBy(exact(riz.name).first);
    await tapBy(add(b.name)); // Riz + B
    await tapBy(confirm);
    await t.pump(const Duration(seconds: 1));
    final two = container.read(cartProvider).items;
    expect(two, hasLength(2), reason: 'options differentes: deux lignes');
    debugPrint('7. autre combinaison (Riz + ${b.name}): ${two.length} lignes distinctes');
    debugPrint('RESULTAT: OK (aucun round envoye)');
  });
}
