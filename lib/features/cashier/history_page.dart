import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../data/pos_api.dart';
import '../../models/ordering.dart';
import 'sales_page.dart' show StatusPill;

typedef _Filter = ({String date, String search, String status});

final _ordersProvider = FutureProvider.autoDispose.family<List<Order>, _Filter>((ref, f) {
  // 30 s of freshness like the Tauri query, instead of refetching on every revisit.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 30), link.close);
  ref.onDispose(timer.cancel);
  return ref.watch(posApiProvider).listOrders(
        date: f.date,
        search: f.search.isEmpty ? null : f.search,
        status: f.status == 'all' ? null : f.status,
      );
});

const _statusFilters = [('all', 'Tous'), ('paid', 'Payés'), ('pending_payment', 'Attente'), ('cancelled', 'Annulés')];

/// Order history with date / status / reference-or-table filters (port of pos/sales/history/page.tsx).
class SalesHistoryPage extends ConsumerStatefulWidget {
  const SalesHistoryPage({super.key});
  @override
  ConsumerState<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends ConsumerState<SalesHistoryPage> {
  DateTime _date = DateTime.now();
  String _status = 'all';
  String _search = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _search = v.trim()));
  }

  _Filter get _filter => (date: DateFormat('yyyy-MM-dd').format(_date), search: _search, status: _status);

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final orders = ref.watch(_ordersProvider(_filter));
    final count = orders.value?.length;

    return Column(children: [
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outline)),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          spacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.receiptText, size: 22, color: scheme.primary),
                const SizedBox(width: 8),
                Text('HISTORIQUE DES VENTES', style: titleStyle.copyWith(fontSize: 18, letterSpacing: -0.3)),
              ]),
              const SizedBox(height: 4),
              Text(count == null ? '...' : '$count COMMANDE(S) TROUVÉE(S)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.slate400)),
            ]),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: _onSearch,
                  decoration: const InputDecoration(hintText: 'Référence ou Table...', prefixIcon: Icon(LucideIcons.search, size: 16), isDense: true),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(LucideIcons.calendar, size: 16),
                label: Text(DateFormat('d MMMM yyyy', 'fr_FR').format(_date), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _status,
                  borderRadius: BorderRadius.circular(12),
                  items: [for (final (id, label) in _statusFilters) DropdownMenuItem(value: id, child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))],
                  onChanged: (v) => setState(() => _status = v ?? 'all'),
                ),
              ),
            ]),
          ],
        ),
      ),
      if (orders.hasError)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFECACA))),
          child: Text('⚠️ ${errorMessage(orders.error!, 'Impossible de charger les commandes. Vérifiez votre connexion.')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C))),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(_ordersProvider(_filter).future),
          child: orders.isLoading && !orders.hasValue
              ? ListView(children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())])
              : (orders.value ?? const <Order>[]).isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      Center(child: Text('AUCUNE COMMANDE TROUVÉE', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 2))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: orders.value!.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _Row(order: orders.value![i]),
                    ),
        ),
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showDialog<void>(context: context, builder: (_) => _DetailDialog(order: order)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outline)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(order.reference, style: const TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                    child: Text((order.tableName ?? 'EMPORTÉ').toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                  Text('${order.time} • ${order.waiterName ?? 'N/A'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate400)),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(order.formattedTotal, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              StatusPill(order.status),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _DetailDialog extends StatelessWidget {
  const _DetailDialog({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(order.reference, style: const TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text('${order.tableName ?? 'EMPORTÉ'} • ${order.date} ${order.time} • ${order.waiterName ?? 'N/A'}'.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate400)),
                ]),
              ),
              StatusPill(order.status),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(LucideIcons.x)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: order.rounds.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Text('Aucun service enregistré', style: TextStyle(color: AppColors.slate400)))
                : ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
                    for (final r in order.rounds)
                      Opacity(
                        opacity: r.status == 'voided' ? 0.45 : 1,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outline)),
                          child: Column(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('ROUND ${r.number}${r.status == 'voided' ? ' · SUPPRIMÉ' : ''}', style: microLabelStyle.copyWith(letterSpacing: 1, color: scheme.onSurface)),
                                Text(formatCurrency(r.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                              ]),
                            ),
                            for (final i in r.items)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${i.qty}x', style: TextStyle(fontWeight: FontWeight.w900, color: scheme.primary)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(i.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                      for (final m in i.modifiers) Text('+ ${m.name}', style: const TextStyle(fontSize: 10, color: AppColors.slate400)),
                                    ]),
                                  ),
                                  Text(formatCurrency(i.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                ]),
                              ),
                          ]),
                        ),
                      ),
                    if (order.note != null && order.note!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('NOTE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B))),
                          Text(order.note!, style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                        ]),
                      ),
                  ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TOTAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.slate400)),
                if (order.discount > 0) Text('Remise : -${formatCurrency(order.discount)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF059669))),
              ]),
              Text(order.formattedTotal, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            ]),
          ),
        ]),
      ),
    );
  }
}
