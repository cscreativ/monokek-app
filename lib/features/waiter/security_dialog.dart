import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/pos_api.dart';

/// Self-service PIN / password change (port of SecurityModal + the layout's update handlers).
Future<void> showSecurityDialog(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _SecurityDialog());

class _SecurityDialog extends ConsumerStatefulWidget {
  const _SecurityDialog();
  @override
  ConsumerState<_SecurityDialog> createState() => _SecurityDialogState();
}

class _SecurityDialogState extends ConsumerState<_SecurityDialog> {
  final _pin = TextEditingController();
  final _oldPass = TextEditingController();
  final _newPass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    _oldPass.dispose();
    _newPass.dispose();
    super.dispose();
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _run(Future<void> Function() action, String ok, String fallback) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(ok);
    } catch (e) {
      if (mounted) _toast(errorMessage(e, fallback), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePin() async {
    if (!RegExp(r'^\d{4}$').hasMatch(_pin.text)) return _toast('Le code PIN doit comporter 4 chiffres', error: true);
    await _run(() => ref.read(posApiProvider).updatePin(_pin.text), 'Code PIN modifié !', 'Impossible de modifier le PIN. Réessayez plus tard.');
    if (mounted) _pin.clear();
  }

  Future<void> _savePassword() async {
    if (_newPass.text.length < 8) return _toast('Le nouveau mot de passe doit faire au moins 8 caractères.', error: true);
    await _run(() => ref.read(posApiProvider).updatePassword(_oldPass.text, _newPass.text), 'Mot de passe modifié avec succès !', 'Impossible de modifier le mot de passe.');
    if (mounted) {
      _oldPass.clear();
      _newPass.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(LucideIcons.userCog),
              const SizedBox(width: 12),
              Text('SÉCURITÉ DU COMPTE', style: titleStyle.copyWith(fontSize: 18)),
            ]),
            const SizedBox(height: 24),
            Text('NOUVEAU CODE PIN (4 CHIFFRES)', style: microLabelStyle.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  decoration: const InputDecoration(counterText: '', prefixIcon: Icon(LucideIcons.keyRound, size: 18)),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(onPressed: _busy ? null : _savePin, style: FilledButton.styleFrom(minimumSize: const Size(90, 52)), child: const Text('OK')),
            ]),
            const SizedBox(height: 24),
            Text('MOT DE PASSE ACTUEL', style: microLabelStyle.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            TextField(controller: _oldPass, obscureText: true, decoration: const InputDecoration(prefixIcon: Icon(LucideIcons.lock, size: 18))),
            const SizedBox(height: 16),
            Text('NOUVEAU MOT DE PASSE (8 CARACTÈRES MIN.)', style: microLabelStyle.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            TextField(controller: _newPass, obscureText: true, decoration: const InputDecoration(prefixIcon: Icon(LucideIcons.lock, size: 18))),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _savePassword, child: const Text('CHANGER LE MOT DE PASSE')),
            const SizedBox(height: 8),
            Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('FERMER'))),
          ]),
        ),
      ),
    );
  }
}
