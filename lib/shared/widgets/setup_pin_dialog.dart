import 'package:flutter/material.dart';

import '../../core/security/setup_pin.dart';
import '../../core/storage/app_storage.dart';
import 'num_pad.dart';

/// Asks for the terminal's admin PIN (the same one that protects the server address) before opening a
/// configuration screen. Completes true at once when no PIN has been created yet.
Future<bool> confirmSetupPin(BuildContext context, AppStorage storage) async {
  if (!hasSetupPin(storage)) return true;
  return await showDialog<bool>(context: context, builder: (_) => _PinDialog(storage)) ?? false;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog(this.storage);
  final AppStorage storage;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  String _pin = '';
  bool _error = false;

  void _onKey(String key) {
    setState(() => _error = false);
    if (key == 'C') return setState(() => _pin = '');
    if (key == 'del') return setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1));
    if (_pin.length >= 4) return;
    setState(() => _pin += key);
    if (_pin.length < 4) return;
    if (verifySetupPin(widget.storage, _pin)) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = true;
        _pin = '';
      });
    }
  }

  // A plain Dialog, not AlertDialog: AlertDialog measures intrinsic sizes, which the NumPad's shrink-wrapped grid cannot answer.
  @override
  Widget build(BuildContext context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Code PIN du poste', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Entrez le code PIN pour modifier la configuration.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              PinDots(length: _pin.length, error: _error),
              const SizedBox(height: 16),
              NumPad(onKey: _onKey),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ]),
          ),
        ),
      );
}
