import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/format.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../data/cashier_api.dart';
import '../../models/cashier.dart';
import '../auth/auth_controller.dart';
import 'cashier_providers.dart';

/// Shown instead of the sales screen while no session is open (port of CashOpenModal.tsx).
class CashOpenGate extends ConsumerStatefulWidget {
  const CashOpenGate({super.key, this.onNoRegister});
  final VoidCallback? onNoRegister;
  @override
  ConsumerState<CashOpenGate> createState() => _CashOpenGateState();
}

class _CashOpenGateState extends ConsumerState<CashOpenGate> {
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final registerId = ref.read(storageProvider).registerId;
    if (registerId == null) {
      widget.onNoRegister?.call();
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cashierApiProvider).open(registerId, double.tryParse(_amount.text.trim()) ?? 0);
      ref.invalidate(cashStatusProvider);
      ref.invalidate(salesOrdersProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session de caisse démarrée')));
    } catch (e) {
      // Surfaces the backend's real reason (e.g. "Cette caisse est déjà ouverte par X.").
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, "Vérifiez l'ID de caisse ou le montant")), backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: const Color(0xFF1C1917).withValues(alpha: 0.9),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(40)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(24)),
              child: const Icon(LucideIcons.banknote, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text('OUVERTURE DE CAISSE', style: titleStyle.copyWith(fontSize: 26)),
            const SizedBox(height: 6),
            Text('Saisissez le fond de caisse initial (FCFA)', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onSubmitted: (_) => _busy ? null : _open(),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '0',
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 20, right: 12), child: Center(widthFactor: 1, child: Text('FCFA', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.slate400)))),
                contentPadding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _open,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("CONFIRMER L'OUVERTURE", style: TextStyle(letterSpacing: 1.5)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => ref.read(authProvider.notifier).logout(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7F1D1D),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(64),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('QUITTER', style: TextStyle(letterSpacing: 1.5)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Vérification de caisse": system totals + counted cash → closes the session. Resolves with the
/// report on success, null when dismissed.
Future<CloseReport?> showCloseShiftDialog(BuildContext context, CashSummary summary) => showDialog<CloseReport>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CloseShiftDialog(summary: summary),
    );

class _CloseShiftDialog extends ConsumerStatefulWidget {
  const _CloseShiftDialog({required this.summary});
  final CashSummary summary;
  @override
  ConsumerState<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends ConsumerState<_CloseShiftDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final value = double.tryParse(_amount.text.trim());
    if (value == null) return;
    setState(() => _busy = true);
    try {
      final report = await ref.read(cashierApiProvider).close(value, _note.text.trim().isEmpty ? null : _note.text.trim());
      if (mounted) Navigator.of(context).pop(report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, 'Erreur lors de la validation finale')), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.summary;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('VÉRIFICATION DE CAISSE', style: titleStyle.copyWith(fontSize: 22, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text('RÉSUMÉ DES VENTES DU SYSTÈME', style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 1.5)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                for (final p in s.payments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(paymentMethodLabel(p.method), style: TextStyle(fontFamily: 'monospace', color: scheme.onSurfaceVariant)),
                      Text(formatCurrency(p.total), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                    ]),
                  ),
                const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('TOTAL VENTES', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900)),
                  Text(formatCurrency(s.totalSales), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft, child: Text('ARGENT RÉEL EN CAISSE (FCFA)', style: microLabelStyle.copyWith(color: scheme.onSurface))),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: Color(0xFF059669)),
              decoration: const InputDecoration(hintText: 'Saisissez le montant compté'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 4,
              decoration: const InputDecoration(hintText: "Notes ou explications sur d'éventuels écarts..."),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: const Text('ANNULER', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (_busy || double.tryParse(_amount.text.trim()) == null) ? null : _close,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('CLÔTURER DÉFINITIVEMENT', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Z-report shown right after closing the shift.
Future<void> showCloseReportDialog(BuildContext context, CloseReport r) => showDialog<void>(context: context, builder: (_) => _ReportDialog(report: r));

class _ReportDialog extends StatelessWidget {
  const _ReportDialog({required this.report});
  final CloseReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    String d(DateTime? t) => t == null ? '—' : fmt.format(t);
    final diffColor = report.difference == 0 ? AppColors.success : scheme.error;

    Widget row(String l, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l, style: TextStyle(fontFamily: 'monospace', color: scheme.onSurfaceVariant)),
            Text(v, style: TextStyle(fontFamily: 'monospace', fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: color)),
          ]),
        );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(LucideIcons.circleCheck, size: 44, color: AppColors.success),
            const SizedBox(height: 12),
            Text('SHIFT TERMINÉ', textAlign: TextAlign.center, style: titleStyle.copyWith(fontSize: 24)),
            const SizedBox(height: 4),
            Text('RAPPORT DE CLÔTURE', textAlign: TextAlign.center, style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 2)),
            const SizedBox(height: 20),
            row('Ouverture', d(report.openedAt)),
            row('Clôture', d(report.closedAt)),
            const Divider(height: 24),
            row('Fond de caisse', formatCurrency(report.openingAmount)),
            for (final p in report.payments) row(paymentMethodLabel(p.method), formatCurrency(p.total)),
            row('Total encaissé', formatCurrency(report.totalPayments), bold: true),
            const Divider(height: 24),
            row('Attendu', formatCurrency(report.expectedTotal)),
            row('Compté', formatCurrency(report.actualTotal)),
            row('Écart', formatCurrency(report.difference), color: diffColor, bold: true),
            if (report.note != null && report.note!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Text(report.note!, style: const TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('FERMER')),
          ]),
        ),
      ),
    );
  }
}
