import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/net/server_check.dart';
import '../../core/net/trusted_ca.dart';
import '../../core/security/setup_pin.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';
import '../../shared/widgets/num_pad.dart';
import '../license/license_guard.dart';
import 'auth_controller.dart';

enum _Step { locked, form, setPin }

/// Backend address screen — port of mono-kep-tauri /setup. Once a server address AND an admin PIN
/// exist, changing the address requires that PIN; the first provisioning forces creating one.
class SetupPage extends ConsumerStatefulWidget {
  const SetupPage({super.key});
  @override
  ConsumerState<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends ConsumerState<SetupPage> {
  late final TextEditingController _ip;
  late _Step _step;
  bool _testing = false;
  bool? _ok;

  // PIN entry (unlock, or create + confirm)
  String _pin = '';
  String? _firstPin;
  bool _pinError = false;

  @override
  void initState() {
    super.initState();
    final storage = ref.read(storageProvider);
    _ip = TextEditingController(text: storage.backendIp ?? '');
    final configured = (storage.backendIp ?? '').isNotEmpty;
    _step = configured && hasSetupPin(storage) ? _Step.locked : _Step.form;
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Leaves the screen: back where we came from (login/guard) or to the app root on first run.
  void _leave() => context.canPop() ? context.pop() : context.go('/');

  bool _isCertificateError(Object e) =>
      e is DioException && (e.type == DioExceptionType.badCertificate || e.error is HandshakeException || e.error is TlsException);

  /// Downloads the server's CA, shows its fingerprint and, if the user confirms, trusts it from now on.
  Future<bool> _trustServerCa(String base) async {
    final String pem;
    try {
      pem = await TrustedCa.download(base);
    } catch (_) {
      return false;
    }
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Faire confiance à ce serveur ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ce serveur utilise son propre certificat. Vérifiez que l'empreinte ci-dessous est identique à celle affichée sur le serveur avant d'accepter."),
            const SizedBox(height: 12),
            SelectableText(TrustedCa.fingerprint(pem), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Refuser')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Faire confiance')),
        ],
      ),
    );
    if (ok != true) return false;
    await ref.read(storageProvider).setTrustedCa(pem);
    TrustedCa.install(pem);
    ref.invalidate(apiClientProvider); // its HttpClient was built before the CA was known
    return true;
  }

  Future<void> _save() async {
    setState(() {
      _testing = true;
      _ok = null;
    });
    final base = resolveBaseUrl(_ip.text);
    try {
      try {
        await verifyServer(base);
      } catch (e) {
        // HTTPS server signed by Caddy's own CA, which this device does not know yet: offer to trust it.
        if (!base.startsWith('https://') || !_isCertificateError(e) || !await _trustServerCa(base)) rethrow;
        await verifyServer(base);
      }
      // Stored with its scheme, like the Tauri build: it decides https (default) vs explicit http (debug).
      final storage = ref.read(storageProvider);
      final changedServer = (storage.backendIp ?? '').isNotEmpty && serverIdentity(storage.backendIp) != serverIdentity(base);
      await storage.setBackendIp(base);
      // Start from a clean state: a session from ANOTHER server is worthless here, and a licence check
      // that failed before the configuration must not be shown again.
      if (changedServer) await ref.read(authProvider.notifier).logout(remote: false);
      ref.invalidate(apiClientProvider);
      ref.invalidate(licenseProvider);
      if (!mounted) return;
      setState(() => _ok = true);
      _snack('Terminal connecté au serveur');
      if (!hasSetupPin(ref.read(storageProvider))) {
        setState(() {
          _step = _Step.setPin;
          _pin = '';
          _firstPin = null;
        });
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _ok = false);
      _snack('Connexion échouée : ${classifyLicenseError(e).detail}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _onPinKey(String key) {
    setState(() => _pinError = false);
    if (key == 'C') return setState(() => _pin = '');
    if (key == 'del') return setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1));
    if (_pin.length >= 4) return;
    setState(() => _pin += key);
    if (_pin.length < 4) return;

    final storage = ref.read(storageProvider);
    if (_step == _Step.locked) {
      if (verifySetupPin(storage, _pin)) {
        setState(() {
          _step = _Step.form;
          _pin = '';
        });
      } else {
        setState(() {
          _pinError = true;
          _pin = '';
        });
      }
    } else if (_step == _Step.setPin) {
      if (_firstPin == null) {
        setState(() {
          _firstPin = _pin;
          _pin = '';
        });
      } else if (_firstPin == _pin) {
        saveSetupPin(storage, _pin).then((_) {
          if (!mounted) return;
          _snack('Code PIN du poste enregistré');
          context.go('/');
        });
      } else {
        _snack('Les deux codes ne correspondent pas');
        setState(() {
          _pinError = true;
          _pin = '';
          _firstPin = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _step == _Step.setPin ? null : AppBar(backgroundColor: Colors.transparent, leading: context.canPop() ? BackButton(onPressed: _leave) : null),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandLogo(subtitle: 'Configuration du terminal'),
              const SizedBox(height: 32),
              Card(
                elevation: 8,
                shadowColor: Colors.black26,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: switch (_step) {
                    _Step.form => _form(context, scheme),
                    _Step.locked => _pinStep(scheme, 'Poste verrouillé', 'Entrez le code PIN du poste pour modifier la configuration.'),
                    _Step.setPin => _pinStep(
                        scheme,
                        _firstPin == null ? 'Créer le code PIN du poste' : 'Confirmer le code PIN',
                        'Ce code protège la configuration du serveur sur ce terminal.',
                      ),
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ColorScheme scheme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Serveur', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Adresse du serveur MonoKek sur le réseau local.', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        Text('ADRESSE IP : PORT', style: microLabelStyle.copyWith(color: scheme.onSurface)),
        const SizedBox(height: 8),
        TextField(
          controller: _ip,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _testing ? null : _save(),
          decoration: InputDecoration(
            hintText: '192.168.1.10:8080',
            prefixIcon: const Icon(LucideIcons.server, size: 18),
            suffixIcon: _ok == null ? null : Icon(_ok! ? LucideIcons.circleCheck : LucideIcons.circleAlert, color: _ok! ? AppColors.success : scheme.error),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _testing ? null : _save,
          child: _testing
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('TESTER ET ENREGISTRER'),
        ),
      ]);

  Widget _pinStep(ColorScheme scheme, String title, String subtitle) => Column(children: [
        Icon(LucideIcons.lock, color: scheme.primary),
        const SizedBox(height: 12),
        Text(title.toUpperCase(), textAlign: TextAlign.center, style: titleStyle.copyWith(fontSize: 18)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 20),
        PinDots(length: _pin.length, error: _pinError),
        const SizedBox(height: 16),
        NumPad(onKey: _onPinKey),
      ]);
}
