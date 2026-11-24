import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/api/envelope.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_theme.dart';

enum LicenseFailureKind { network, certificate, http }

/// Why the licence check failed, in terms the "unreachable" screen can show: a reachable server that
/// answers 401/5xx, or that presents an untrusted certificate, is NOT a network outage.
class LicenseFailure {
  const LicenseFailure(this.kind, this.detail, {this.status});
  final LicenseFailureKind kind;
  final String detail;
  final int? status;
}

/// Pure classification of an error thrown by GET /api/license/status (testable).
LicenseFailure classifyLicenseError(Object error) {
  if (error is DioException) {
    final inner = error.error;
    if (error.type == DioExceptionType.badCertificate || inner is HandshakeException || inner is TlsException) {
      return const LicenseFailure(LicenseFailureKind.certificate, 'Certificat HTTPS non approuvé');
    }
    final status = error.response?.statusCode;
    if (status != null) return LicenseFailure(LicenseFailureKind.http, 'Réponse HTTP $status', status: status);
    return LicenseFailure(
      LicenseFailureKind.network,
      switch (error.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout => 'Délai dépassé',
        DioExceptionType.connectionError => 'Connexion refusée ou réseau indisponible',
        _ => inner?.toString() ?? error.message ?? 'Erreur réseau',
      },
    );
  }
  return LicenseFailure(LicenseFailureKind.http, 'Réponse inattendue du serveur ($error)');
}

class LicenseStatus {
  const LicenseStatus({required this.active, required this.expired, this.licenseKey, this.expiryDate, this.daysLeft});
  final bool active;
  final bool expired;
  final String? licenseKey;
  final String? expiryDate;
  final int? daysLeft;

  factory LicenseStatus.fromJson(Map<String, dynamic> j) => LicenseStatus(
        active: j['active'] == true,
        expired: j['expired'] == true,
        licenseKey: j['license_key'] as String?,
        expiryDate: j['expiry_date'] as String?,
        daysLeft: (j['days_left'] as num?)?.toInt(),
      );
}

/// GET /api/license/status, re-checked every 30 min (a licence can expire mid-shift).
/// No automatic retry: the guard distinguishes a network drop from an invalid licence itself.
final licenseProvider = FutureProvider<LicenseStatus>(
  (ref) async {
    final timer = Timer(const Duration(minutes: 30), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
    final res = await ref.read(apiClientProvider).get('/api/license/status');
    return LicenseStatus.fromJson(res.data as Map<String, dynamic>);
  },
  retry: (_, _) => null,
);

/// Blocks the app unless the licence is active. Network failures are NOT a licence problem:
/// they show a "server unreachable" screen with automatic retry instead of asking for a key.
class LicenseGuard extends ConsumerStatefulWidget {
  const LicenseGuard({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LicenseGuard> createState() => _LicenseGuardState();
}

class _LicenseGuardState extends ConsumerState<LicenseGuard> {
  final _key = TextEditingController();
  bool _activating = false;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    _key.dispose();
    super.dispose();
  }

  /// Arms ONE automatic retry. Idempotent: build() runs on every rebuild of this widget, and a timer
  /// that was cancelled and re-created each time could be pushed back forever. Never armed while a
  /// request is in flight either, otherwise a slow server (answering after 8 s) would be restarted
  /// before it could answer, for ever.
  void _scheduleRetry() {
    if (_retry?.isActive ?? false) return;
    _retry = Timer(const Duration(seconds: 8), () => ref.invalidate(licenseProvider));
  }

  Future<void> _activate() async {
    if (_key.text.trim().isEmpty) return;
    setState(() => _activating = true);
    try {
      final res = await ref.read(apiClientProvider).post('/api/license/activate', data: {'key': _key.text.trim()});
      final data = res.data;
      if (!mounted) return;
      if (data is Map && data['expired'] == true) {
        _toast('Licence expirée depuis le ${data['expiry_date']}');
      } else {
        _toast('Système activé !');
      }
      ref.invalidate(licenseProvider);
    } catch (e) {
      if (mounted) _toast(errorMessage(e, "Erreur d'activation"));
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  void _toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseProvider);

    // Background refresh keeps showing the last known value (no flash of the loading screen).
    if (license.isLoading && !license.hasValue && !license.hasError) return const _Splash();

    final error = license.error;
    final isNetwork = error is DioException && error.response == null;
    final isFraud = error is DioException && error.response?.statusCode == 403;

    final status = license.value;
    if (isNetwork || (license.hasError && !isFraud && status == null)) {
      // Never ask for a key blindly. The screen says WHY (network, certificate, HTTP code) and which
      // URL was called, instead of calling every failure an outage.
      if (!license.isLoading) _scheduleRetry();
      return _Unreachable(
        failure: classifyLicenseError(error!),
        url: '${resolveBaseUrl(ref.read(storageProvider).backendIp)}/api/license/status',
        onRetry: () => ref.invalidate(licenseProvider),
      );
    }

    _retry?.cancel(); // the check went through: no pending retry
    if (isFraud || status == null || !status.active || status.expired) {
      return _Blocked(
        fraud: isFraud,
        expired: status?.expired ?? false,
        expiryDate: status?.expiryDate,
        controller: _key,
        activating: _activating,
        onActivate: _activate,
      );
    }
    return widget.child;
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('VÉRIFICATION...', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 4)),
          ]),
        ),
      );
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.failure, required this.url, required this.onRetry});
  final LicenseFailure failure;
  final String url;
  final VoidCallback onRetry;

  (String, String, IconData) get _texts => switch (failure.kind) {
        LicenseFailureKind.network => (
            'SERVEUR INJOIGNABLE',
            'Nouvelle tentative automatique dans quelques secondes. Vérifiez la connexion réseau du poste.',
            LucideIcons.wifiOff,
          ),
        LicenseFailureKind.certificate => (
            'CERTIFICAT NON RECONNU',
            "Le serveur répond, mais son certificat HTTPS n'est pas approuvé par ce terminal. Ouvrez la configuration réseau pour refaire confiance au serveur.",
            LucideIcons.shieldAlert,
          ),
        LicenseFailureKind.http => (
            'RÉPONSE INATTENDUE DU SERVEUR',
            'Le serveur est joignable mais la vérification de la licence échoue. Nouvelle tentative automatique dans quelques secondes.',
            LucideIcons.serverCrash,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (title, message, icon) = _texts;
    return _body(context, title, message, icon);
  }

  Widget _body(BuildContext context, String title, String message, IconData icon) => Scaffold(
        backgroundColor: AppColors.slate950,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: const Color(0xFFFBBF24), size: 32),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: titleStyle.copyWith(fontSize: 20, color: Colors.white)),
              const SizedBox(height: 6),
              SizedBox(
                width: 300,
                child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.slate400, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 300,
                child: SelectableText(
                  '${failure.detail}\n$url',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate400, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
              const SizedBox(height: 16),
              // The screen is always dark (slate950): the theme's default button colours (primary, dark in
              // the light theme) were nearly invisible on it, so the colours are explicit.
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                OutlinedButton(
                  onPressed: onRetry,
                  style: onDarkOutlinedButton,
                  child: const Text('Réessayer maintenant'),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/setup'),
                  style: onDarkFilledButton,
                  icon: const Icon(LucideIcons.settings, size: 14),
                  label: const Text('Configuration réseau'),
                ),
              ]),
            ]),
          ),
        ),
      );
}

class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.fraud,
    required this.expired,
    required this.expiryDate,
    required this.controller,
    required this.activating,
    required this.onActivate,
  });
  final bool fraud;
  final bool expired;
  final String? expiryDate;
  final TextEditingController controller;
  final bool activating;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final accent = fraud ? const Color(0xFFDC2626) : const Color(0xFF4F46E5);
    return Scaffold(
      backgroundColor: AppColors.slate950,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/setup'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate900,
        shape: const CircleBorder(),
        child: const Icon(LucideIcons.settings),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(48)),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: AppColors.slate900),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(fraud ? LucideIcons.shieldAlert : LucideIcons.lock, color: accent, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  (fraud ? 'Sécurité violée' : (expired ? 'Licence expirée' : 'Activation requise')).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: titleStyle.copyWith(fontSize: 24, color: fraud ? accent : AppColors.slate900),
                ),
                const SizedBox(height: 8),
                Text(
                  (fraud
                          ? 'Modification non autorisée détectée'
                          : expired
                              ? 'Fin de validité : $expiryDate'
                              : 'Veuillez activer votre produit')
                      .toUpperCase(),
                  textAlign: TextAlign.center,
                  style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 1.5),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.slate50, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    "ENTREZ UNE CLÉ DE LICENCE OFFICIELLE POUR RESTAURER L'ACCÈS AU SYSTÈME.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.blueGrey.shade600, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.slate900),
                  decoration: InputDecoration(
                    hintText: 'RESTO-PRO-XXXX-...',
                    fillColor: AppColors.slate50,
                    prefixIcon: const Icon(LucideIcons.key, size: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: activating ? null : onActivate,
                  style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: activating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('RESTAURER LE SYSTÈME', style: TextStyle(fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 24),
                Text(
                  'IDENTIFIANT TECHNIQUE : ${fraud ? 'ERR_INTEGRITY_FAIL' : 'ERR_LICENSE_REQ'}',
                  style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 9, letterSpacing: 0.5),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
