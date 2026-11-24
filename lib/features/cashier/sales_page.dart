import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/format.dart';
import '../../core/sse/notifications_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/cashier_api.dart';
import '../../data/pos_api.dart';
import '../../models/ordering.dart';
import 'cash_dialogs.dart';
import 'cashier_providers.dart';
import 'manager_pin_dialog.dart';
import 'payment_dialog.dart';

const _status = <String, (String, Color, Color)>{
  'draft': ('Brouillon', Color(0xFFF1F5F9), Color(0xFF475569)),
  'pending': ('En attente', Color(0xFFFEF3C7), Color(0xFFB45309)),
  'pending_payment': ('Attente Paiement', Color(0xFFFFEDD5), Color(0xFFC2410C)),
  'billing': ('Facturation', Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'paid': ('Payé', Color(0xFFD1FAE5), Color(0xFF047857)),
  'completed': ('Terminé', Color(0xFFDCFCE7), Color(0xFF15803D)),
  'cancelled': ('Annulé', Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  'ready': ('Prêt pour livraison', Color(0xFFDBEAFE), Color(0xFF1D4ED8)),
  'preparing': ('En préparation', Color(0xFFF1F5F9), Color(0xFF475569)),
  'reserved': ('Réservation', Color(0xFFF3F4F6), Color(0xFF475569)),
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _status[status] ?? (status, const Color(0xFFF1F5F9), const Color(0xFF475569));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: fg)),
    );
  }
}

/// Shift screen: orders of the open session, cash-in, cancel / void, close shift (port of pos/sales/order/page.tsx).
class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});
  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  String _search = '';
  String? _selectedUuid;
  bool _closing = false;

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _closeShift() async {
    setState(() => _closing = true);
    try {
      final summary = await ref.read(cashierApiProvider).currentSummary();
      if (!mounted) return;
      final report = await showCloseShiftDialog(context, summary);
      if (report != null && mounted) {
        ref.invalidate(cashStatusProvider);
        _toast('Shift terminé et enregistré');
        await showCloseReportDialog(context, report);
      }
    } catch (e) {
      if (mounted) _toast(errorMessage(e, 'Impossible de récupérer le résumé de caisse'), error: true);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cash = ref.watch(cashStatusProvider);

    // Shift events are announced like in the Tauri screen.
    ref.listen(sseEventsProvider, (_, next) {
      final e = next.value;
      if (e == null) return;
      if (e.name == 'order.created') _toast('Commande ${e.map['reference'] ?? ''} créée !'.replaceAll('  ', ' '));
      if (e.name == 'order.updated') _toast('Commande #${e.map['orderId'] ?? ''} : ${e.map['newStatus'] ?? ''}');
      // The kitchen (possibly a central one) answers: the till is told when a ticket is ready to be served.
      if (e.name == 'ticket.delayed') _toast('Commande #${e.map['orderId'] ?? ''} : en attente de la cuisine depuis ${e.map['pendingMinutes'] ?? '?'} min');
      if (e.name == 'ticket.updated' && e.map['status'] == 'ready') _toast('Commande #${e.map['orderId'] ?? ''} : prête');
    });

    return cash.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(errorMessage(e, 'Erreur de synchro caisse')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => ref.invalidate(cashStatusProvider), child: const Text('Réessayer')),
        ]),
      ),
      data: (status) => !status.isOpen ? CashOpenGate(onNoRegister: () => context.go('/pos/sales')) : _shift(context),
    );
  }

  Widget _shift(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final orders = ref.watch(salesOrdersProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final all = orders.value ?? const <Order>[];
    final list = all.where((o) => o.total.toStringAsFixed(0).contains(_search.trim())).toList();
    final selected = list.where((o) => o.uuid == _selectedUuid).firstOrNull ?? all.where((o) => o.uuid == _selectedUuid).firstOrNull;

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: scheme.outline))),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          spacing: 16,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.history, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text('HISTORIQUE DU SHIFT', style: titleStyle.copyWith(fontSize: 16, letterSpacing: -0.3)),
            ]),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, minWidth: 220),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                keyboardType: TextInputType.number,
                style: const TextStyle(fontWeight: FontWeight.w700),
                decoration: const InputDecoration(hintText: 'Rechercher par montant...', prefixIcon: Icon(LucideIcons.search, size: 16), isDense: true),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: Row(children: [
          // Phone: the list takes the whole width (Expanded must be a direct child of the Row).
          if (wide) SizedBox(width: 450, child: _list(context, list, orders, selected)) else Expanded(child: _list(context, list, orders, selected)),
          if (wide)
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(left: BorderSide(color: scheme.outline))),
                child: selected == null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
                            child: const Icon(LucideIcons.receiptText, size: 40, color: AppColors.slate400),
                          ),
                          const SizedBox(height: 16),
                          Text('SÉLECTIONNEZ UN TICKET', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 3, fontSize: 12)),
                        ]),
                      )
                    : SaleDetail(order: selected),
              ),
            ),
        ]),
      ),
      // Session footer
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: const BoxDecoration(color: AppColors.slate900, borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
        child: SafeArea(
          top: false,
          child: Row(children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _FooterStat(label: 'TOTAL DU SHIFT', value: formatCurrency(all.fold<double>(0, (s, o) => s + o.total))),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 560) ...[
              const SizedBox(width: 32),
              _FooterStat(label: 'TICKETS VALIDÉS', value: '${all.length}'),
            ],
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _closing ? null : _closeShift,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.slate900,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _closing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(MediaQuery.sizeOf(context).width < 420 ? 'CLÔTURER' : 'CLÔTURER SHIFT', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _list(BuildContext context, List<Order> list, AsyncValue<List<Order>> orders, Order? selected) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).cardColor,
      child: orders.isLoading && !orders.hasValue
          ? Center(child: Text('CHARGEMENT...', style: microLabelStyle.copyWith(color: AppColors.slate400)))
          : RefreshIndicator(
              onRefresh: () async => ref.refresh(salesOrdersProvider.future),
              child: list.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      Center(child: Text('AUCUN TICKET', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 3))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final o = list[i];
                        final on = selected?.uuid == o.uuid;
                        return InkWell(
                          borderRadius: BorderRadius.circular(32),
                          onTap: () {
                            setState(() => _selectedUuid = o.uuid);
                            if (MediaQuery.sizeOf(context).width < 900) {
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                showDragHandle: true,
                                builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: _SheetDetail(uuid: o.uuid)),
                              );
                            }
                          },
                          child: Opacity(
                            opacity: o.status == 'cancelled' ? 0.6 : 1,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                color: o.status == 'cancelled' ? const Color(0xFFFEF2F2).withValues(alpha: 0.4) : null,
                                border: Border.all(color: on ? scheme.primary : scheme.outline, width: on ? 2 : 1.5),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(o.reference, style: const TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -0.5)),
                                    const SizedBox(height: 4),
                                    Text('${o.tableName ?? 'Emporter'} • ${o.time}'.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate400)),
                                  ]),
                                ),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  Text(o.formattedTotal, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                                  const SizedBox(height: 4),
                                  StatusPill(o.status),
                                ]),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white38)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: Colors.white)),
      ]);
}

/// Bottom-sheet variant: re-reads the order from the live list so SSE refreshes show up.
class _SheetDetail extends ConsumerWidget {
  const _SheetDetail({required this.uuid});
  final String uuid;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(salesOrdersProvider).value?.where((o) => o.uuid == uuid).firstOrNull;
    return order == null ? const Center(child: CircularProgressIndicator()) : SaleDetail(order: order, compact: true);
  }
}

/// Ticket detail with rounds, "Encaisser", reprint, cancel and per-round void.
class SaleDetail extends ConsumerStatefulWidget {
  const SaleDetail({super.key, required this.order, this.compact = false});
  final Order order;
  final bool compact;
  @override
  ConsumerState<SaleDetail> createState() => _SaleDetailState();
}

class _SaleDetailState extends ConsumerState<SaleDetail> {
  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _pay() async {
    final paid = await showPaymentDialog(context, widget.order);
    if (paid && mounted && widget.compact) Navigator.of(context).maybePop();
  }

  Future<void> _print() async {
    try {
      await ref.read(posApiProvider).reprint(widget.order.id);
      if (mounted) _toast("Demande d'impression envoyée");
    } catch (e) {
      if (mounted) _toast(errorMessage(e, "Impossible de lancer l'impression"), error: true);
    }
  }

  Future<void> _cancel() async {
    final o = widget.order;
    final ok = await showManagerPinDialog(
      context,
      title: 'ANNULER LA COMMANDE',
      subtitle: '${o.reference} — ${o.formattedTotal}',
      confirmLabel: "Confirmer l'annulation",
      reasonHint: 'Ex: client parti sans payer, erreur de saisie...',
      onConfirm: (reason, pin) => ref.read(posApiProvider).cancelOrder(o.uuid, reason, pin),
    );
    if (ok) {
      ref.invalidate(salesOrdersProvider);
      if (mounted) _toast('Commande annulée');
    }
  }

  Future<void> _voidRound(Round r) async {
    final ok = await showManagerPinDialog(
      context,
      title: 'SUPPRIMER LE ROUND ${r.number}',
      subtitle: "Retiré de l'addition — ne s'annule pas",
      confirmLabel: 'Confirmer la suppression',
      reasonHint: "Ex: erreur de saisie, client a changé d'avis...",
      onConfirm: (reason, pin) => ref.read(posApiProvider).voidRound(r.id, reason, pin),
    );
    if (ok) {
      ref.invalidate(salesOrdersProvider);
      if (mounted) _toast('Round ${r.number} supprimé');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final o = widget.order;
    final payable = o.status == 'completed' || o.status == 'pending_payment' || o.status == 'billing';
    final closed = o.status == 'cancelled' || o.status == 'paid';

    return Padding(
      padding: EdgeInsets.all(widget.compact ? 20 : 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: scheme.outline)),
          child: Text(o.reference, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 12)),
        ),
        const SizedBox(height: 12),
        FittedBox(fit: BoxFit.scaleDown, child: Text(o.formattedTotal, style: titleStyle.copyWith(fontSize: widget.compact ? 40 : 56, height: 1))),
        const SizedBox(height: 8),
        Wrap(spacing: 16, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.user, size: 12, color: scheme.primary),
            const SizedBox(width: 4),
            Text((o.waiterName ?? '—').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.primary)),
          ]),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'TABLE: '),
            TextSpan(text: (o.tableName ?? 'Emporter').toUpperCase(), style: TextStyle(color: scheme.primary)),
          ]), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.slate400)),
        ]),
        const SizedBox(height: 20),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: dark ? AppColors.darkMuted.withValues(alpha: 0.3) : AppColors.slate50.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: scheme.outline, width: 2),
            ),
            child: o.rounds.isEmpty
                ? Center(child: Opacity(opacity: 0.3, child: Text('AUCUN ROUND POUR CETTE COMMANDE', style: microLabelStyle.copyWith(letterSpacing: 2))))
                : ListView(children: [for (final r in o.rounds) _round(context, r, o, closed)]),
          ),
        ),
        const SizedBox(height: 20),
        if (payable)
          FilledButton(
            onPressed: _pay,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(76),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)), child: const Icon(LucideIcons.creditCard, size: 24)),
              const SizedBox(width: 14),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ACTION REQUISE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white70)),
                  Text('ENCAISSER ${o.formattedTotal}'.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ]),
              ),
            ]),
          ),
        if (payable) const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _print,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(76), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(LucideIcons.printer, size: 22),
                SizedBox(height: 4),
                Text('IMPRIMER FACTURE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: closed ? null : _cancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(76),
                foregroundColor: const Color(0xFFDC2626),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                side: BorderSide(color: scheme.outline, width: 2),
              ),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(LucideIcons.rotateCcw, size: 22),
                SizedBox(height: 4),
                Text('ANNULER TICKET', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _round(BuildContext context, Round r, Order o, bool closed) {
    final scheme = Theme.of(context).colorScheme;
    final voided = r.status == 'voided';
    final canVoid = !voided && r.status != 'served' && !closed;
    return Opacity(
      opacity: voided ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline))),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: voided ? const Color(0xFFEF4444) : scheme.primary, borderRadius: BorderRadius.circular(8)),
                child: Icon(LucideIcons.layers, size: 12, color: scheme.onPrimary),
              ),
              const SizedBox(width: 8),
              Text('ROUND ${r.number}',
                  style: TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 12, letterSpacing: 1.5, decoration: voided ? TextDecoration.lineThrough : null)),
              if (voided) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(999)),
                  child: const Text('Supprimé', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFB91C1C))),
                ),
              ],
              const Spacer(),
              const Icon(LucideIcons.clock, size: 12, color: AppColors.slate400),
              const SizedBox(width: 4),
              Text(r.sentAt == null ? 'ENVOYÉ' : DateFormat('HH:mm').format(r.sentAt!), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate400)),
              if (canVoid)
                IconButton(
                  tooltip: 'Supprimer ce round',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.trash2, size: 14),
                  color: const Color(0xFFEF4444),
                  onPressed: () => _voidRound(r),
                ),
            ]),
          ),
          if (voided && r.voidReason != null) ...[
            const SizedBox(height: 8),
            Text(r.voidReason!.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Color(0xFFEF4444))),
          ],
          const SizedBox(height: 12),
          for (final i in r.items)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                  child: Text('${i.qty}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i.productName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    for (final m in i.modifiers) Text('+ ${m.name}'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.primary)),
                  ]),
                ),
                Text(formatCurrency(i.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
            ),
        ]),
      ),
    );
  }
}
