import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/envelope.dart';
import '../../core/theme/app_theme.dart';

/// Reason + manager PIN confirmation (cancel an order / void a round). [onConfirm] must throw on
/// failure: the dialog then stays open with the server's message. Resolves true once it succeeds.
Future<bool> showManagerPinDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String confirmLabel,
  required String reasonHint,
  required Future<void> Function(String reason, String pin) onConfirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ManagerPinDialog(title: title, subtitle: subtitle, confirmLabel: confirmLabel, reasonHint: reasonHint, onConfirm: onConfirm),
  );
  return ok ?? false;
}

class _ManagerPinDialog extends StatefulWidget {
  const _ManagerPinDialog({required this.title, required this.subtitle, required this.confirmLabel, required this.reasonHint, required this.onConfirm});
  final String title;
  final String subtitle;
  final String confirmLabel;
  final String reasonHint;
  final Future<void> Function(String reason, String pin) onConfirm;
  @override
  State<_ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<_ManagerPinDialog> {
  final _reason = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;

  bool get _valid => _reason.text.trim().isNotEmpty && _pin.text.trim().length == 4;

  @override
  void dispose() {
    _reason.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm(_reason.text.trim(), _pin.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, 'Action impossible')), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Text(widget.title, textAlign: TextAlign.center, style: titleStyle.copyWith(fontSize: 22, letterSpacing: -0.5))),
            const SizedBox(height: 6),
            Center(child: Text(widget.subtitle.toUpperCase(), textAlign: TextAlign.center, style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 1.5))),
            const SizedBox(height: 24),
            Text('MOTIF (OBLIGATOIRE)', style: microLabelStyle.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              autofocus: true,
              minLines: 3,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: widget.reasonHint),
            ),
            const SizedBox(height: 16),
            Text('CODE PIN MANAGER (OBLIGATOIRE)', style: microLabelStyle.copyWith(color: scheme.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 24, letterSpacing: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(hintText: '••••', counterText: ''),
            ),
            const SizedBox(height: 4),
            Text('UN MANAGER DOIT SAISIR SON CODE POUR VALIDER', style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant, letterSpacing: 1)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text('RETOUR', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (_valid && !_busy) ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.confirmLabel.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
