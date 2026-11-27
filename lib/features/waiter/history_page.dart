import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/sse/notifications_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/pos_api.dart';
import '../../models/ordering.dart';
import '../../shared/widgets/pulse.dart';

typedef _Filter = ({String date, String? status});

final _myOrdersProvider = FutureProvider.autoDispose.family<List<Order>, _Filter>((ref, f) {
  // Live refresh only matters for today's list.
  if (f.date == DateFormat('yyyy-MM-dd').format(DateTime.now())) {
    final sub = ref.listen(sseEventsProvider, (_, next) {
      if (next.value?.name == 'order.updated') {
        ref.invalidateSelf(); // the sound is rung once, centrally, by WaiterAlerts (and only for my orders)
      }
    });
    ref.onDispose(sub.close);
  }
  return ref.watch(posApiProvider).waiterOrders(date: f.date, status: f.status);
});

const _statuses = [
  ('all', 'Tous', LucideIcons.listFilter),
  ('pending', 'En attente', LucideIcons.timer),
  ('ready', 'Prêt', LucideIcons.utensils),
  ('paid', 'Payés', LucideIcons.circleCheck),
];

/// "Mes services": the waiter's own orders, with the "mark as served" action (port of tables/history/page.tsx).
class WaiterHistoryPage extends ConsumerStatefulWidget {
  const WaiterHistoryPage({super.key});
  @override
  ConsumerState<WaiterHistoryPage> createState() => _WaiterHistoryPageState();
}

class _WaiterHistoryPageState extends ConsumerState<WaiterHistoryPage> {
  DateTime _date = DateTime.now();
  String _status = 'all';
  final Set<int> _served = {}; // optimistic

  _Filter get _filter => (date: DateFormat('yyyy-MM-dd').format(_date), status: _status == 'all' ? null : _status);

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d != null) setState(() => _date = d);
  }

  Future<void> _serve(Order o) async {
    setState(() => _served.add(o.id));
    try {
      await ref.read(posApiProvider).markAsServed(o.id);
      ref.invalidate(_myOrdersProvider(_filter));
    } catch (e) {
      if (!mounted) return;
      setState(() => _served.remove(o.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, 'Impossible de marquer comme servi')), backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final orders = ref.watch(_myOrdersProvider(_filter));

    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: scheme.outline))),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('MES SERVICES', style: titleStyle.copyWith(fontSize: 20)),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(LucideIcons.calendar, size: 12),
              label: Text(DateFormat('dd MMM', 'fr_FR').format(_date).toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (id, label, icon) in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _status = id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _status == id ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _status == id ? scheme.primary : scheme.outline),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 12, color: _status == id ? scheme.onPrimary : AppColors.slate400),
                        const SizedBox(width: 8),
                        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _status == id ? scheme.onPrimary : AppColors.slate400)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(_myOrdersProvider(_filter).future),
          child: orders.when(
            loading: () => ListView(children: const [SizedBox(height: 120), Center(child: CircularProgressIndicator())]),
            error: (e, _) => ListView(children: [
              const SizedBox(height: 100),
              Center(child: Text(errorMessage(e, 'Impossible de charger les commandes'))),
              Center(child: TextButton(onPressed: () => ref.invalidate(_myOrdersProvider(_filter)), child: const Text('Réessayer'))),
            ]),
            data: (list) => list.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 100),
                    Center(child: Text('AUCUNE COMMANDE', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 2))),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _OrderCard(order: list[i], served: _served.contains(list[i].id), onServe: () => _serve(list[i])),
                  ),
          ),
        ),
      ),
    ]);
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.served, required this.onServe});
  final Order order;
  final bool served;
  final VoidCallback onServe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ready = order.status == 'ready' && !served;
    final done = order.status == 'completed' || served;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppColors.slate900 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.reference, style: const TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 14)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(LucideIcons.clock, size: 12, color: AppColors.slate400),
              const SizedBox(width: 4),
              Text('${order.time} • ${order.tableName ?? 'Table'}'.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate400)),
            ]),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(order.formattedTotal, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: scheme.primary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(6)),
              child: Text((served ? 'completed' : order.status).toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: scheme.onPrimary)),
            ),
          ]),
        ]),
        if (ready) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Pulse(
              child: const Row(children: [
                Icon(LucideIcons.utensils, size: 12, color: AppColors.orange),
                SizedBox(width: 8),
                Text('À SERVIR MAINTENANT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.orange)),
              ]),
            ),
            FilledButton(
              onPressed: onServe,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('MARQUER COMME SERVI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ]),
        ],
        if (done)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.circleCheck, size: 12, color: AppColors.success),
                SizedBox(width: 4),
                Text('Livré à table', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.slate400)),
              ]),
            ),
          ),
      ]),
    );
  }
}
