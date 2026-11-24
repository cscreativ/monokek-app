import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monokek_flutter/core/storage/app_storage.dart';
import 'package:monokek_flutter/core/theme/app_theme.dart';
import 'package:monokek_flutter/features/cashier/cashier_providers.dart';
import 'package:monokek_flutter/features/cashier/comptoir_page.dart';
import 'package:monokek_flutter/features/kitchen/kitchen_tickets_page.dart';
import 'package:monokek_flutter/features/license/license_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _luminance(Color c) => c.computeLuminance();

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('unreachable screen buttons are readable on its dark background (${brightness.name} theme)', (t) async {
      SharedPreferences.setMockInitialValues({'backend-ip': '192.168.3.20:8443'});
      final storage = (await t.runAsync(AppStorage.create))!;
      await t.pumpWidget(ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          licenseProvider.overrideWith((ref) => throw DioException(requestOptions: RequestOptions(path: '/x'), type: DioExceptionType.connectionTimeout)),
        ],
        child: MaterialApp(theme: buildTheme(brightness), home: const LicenseGuard(child: SizedBox())),
      ));
      await t.pump(const Duration(milliseconds: 300));

      Color fg(Finder button) {
        final style = t.widget<ButtonStyleButton>(button).style!;
        return style.foregroundColor!.resolve(<WidgetState>{})!;
      }

      final retry = find.ancestor(of: find.text('Réessayer maintenant'), matching: find.bySubtype<ButtonStyleButton>());
      final config = find.ancestor(of: find.text('Configuration réseau'), matching: find.bySubtype<ButtonStyleButton>());
      final bg = AppColors.slate950;
      // Retry: light text straight on the dark background.
      expect(_luminance(fg(retry)), greaterThan(0.7), reason: 'Réessayer: texte trop sombre sur fond sombre');
      // Configuration: filled light button with dark text.
      final cfgBg = t.widget<ButtonStyleButton>(config).style!.backgroundColor!.resolve(<WidgetState>{})!;
      expect(_luminance(cfgBg), greaterThan(0.7));
      expect(_luminance(fg(config)), lessThan(0.1));
      expect(_luminance(bg), lessThan(0.05));
    });
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('other always-dark screens keep readable buttons (${brightness.name} theme)', (t) async {
      SharedPreferences.setMockInitialValues({});
      final storage = (await t.runAsync(AppStorage.create))!;
      Future<void> mount(Widget home) async {
        await t.pumpWidget(ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            barStationProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(theme: buildTheme(brightness), home: home),
        ));
        await t.pump(const Duration(milliseconds: 300));
      }

      void expectReadable(String label) {
        final button = find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
        final style = t.widget<ButtonStyleButton>(button).style;
        expect(style?.foregroundColor, isNotNull, reason: '$label: pas de couleur explicite (sombre sur fond sombre)');
        expect(_luminance(style!.foregroundColor!.resolve(<WidgetState>{})!), greaterThan(0.7), reason: '$label: texte trop sombre');
      }

      await mount(const ComptoirPage());
      expectReadable('Retour à la vente');
      await mount(const KitchenTicketsPage(stationId: null));
      expectReadable('Retour au dashboard');
    });
  }
}
