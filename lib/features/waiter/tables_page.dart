import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/pos_api.dart';
import '../../models/floorplan.dart';
import '../../shared/widgets/pulse.dart';
import '../auth/auth_controller.dart';
import '../pos/pos_providers.dart';
import 'transfer_dialog.dart';

const _indigo600 = Color(0xFF4F46E5);
const _indigo100 = Color(0xFFE0E7FF);
const _indigo50 = Color(0xFFEEF2FF);

/// Floor plan with live table statuses (port of pos/tables/page.tsx).
class TablesPage extends ConsumerStatefulWidget {
  const TablesPage({super.key, this.orderRoute = '/pos/tables/order'});
  /// Where a tapped table opens (the cashier has its own route tree).
  final String orderRoute;
  @override
  ConsumerState<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends ConsumerState<TablesPage> {
  int? _zoneId;

  Future<void> _transfer(PosTable from, List<Floor> floors) async {
    final to = await showTransferDialog(context, from: from, floors: floors);
    if (to == null || !mounted) return;
    try {
      await ref.read(posApiProvider).transferTable(from.id, to);
      ref.invalidate(floorsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Table transférée')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, 'Transfert impossible')), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final floors = ref.watch(floorsProvider);

    return floors.when(
      loading: () => Center(child: Text('CHARGEMENT DU PLAN...', style: titleStyle.copyWith(fontSize: 14))),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(errorMessage(e, 'Impossible de charger le plan de salle')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => ref.invalidate(floorsProvider), child: const Text('Réessayer')),
        ]),
      ),
      data: (list) {
        final active = list.where((f) => f.id == _zoneId).firstOrNull ?? (list.isEmpty ? null : list.first);
        return Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: scheme.outline))),
            child: Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final z in list)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: z.id == active?.id,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _zoneId = z.id),
                          shape: const StadiumBorder(),
                          selectedColor: scheme.primary,
                          labelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: z.id == active?.id ? scheme.onPrimary : scheme.onSurface),
                          label: Text('${z.name.toUpperCase()}  (${z.tables.length})'),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => ref.read(authProvider.notifier).logout(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    if (MediaQuery.sizeOf(context).width >= 560) ...[
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        Text('SESSION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: scheme.onSurfaceVariant)),
                        const Text('QUITTER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ]),
                      const SizedBox(width: 10),
                    ],
                    const Icon(LucideIcons.logOut, size: 20),
                  ]),
                ),
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(floorsProvider.future),
              child: (active == null || active.tables.isEmpty)
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Text('AUCUNE TABLE', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 3))),
                    ])
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: 20, crossAxisSpacing: 20, mainAxisExtent: 188),
                      itemCount: active.tables.length,
                      itemBuilder: (_, i) {
                        final t = active.tables[i];
                        return _TableCard(
                          table: t,
                          onTap: () => context.push('${widget.orderRoute}?table=${t.id}'),
                          onLongPress: t.status == 'occupied' && !t.virtual ? () => _transfer(t, list) : null,
                        );
                      },
                    ),
            ),
          ),
        ]);
      },
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.onTap, this.onLongPress});
  final PosTable table;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s = table.status;
    final occupied = s == 'occupied';
    final billing = s == 'billing';

    final bg = occupied ? _indigo50 : (billing ? const Color(0xFFFFFBEB) : (dark ? AppColors.slate900 : Colors.white));
    final border = occupied ? _indigo100 : (billing ? const Color(0xFFFDE68A) : (dark ? AppColors.darkMuted : const Color(0xFFF1F5F9)));
    final (label, badgeBg, badgeFg) = switch (s) {
      'free' => ('Libre', const Color(0xFFD1FAE5), const Color(0xFF059669)),
      'occupied' => ('Occupée', _indigo600, Colors.white),
      'billing' => ('Addition', AppColors.warning, Colors.white),
      _ => ('Maintenance', const Color(0xFFE2E8F0), const Color(0xFF475569)),
    };

    final card = Material(
      color: dark && (occupied || billing) ? AppColors.slate900 : bg,
      borderRadius: BorderRadius.circular(40),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(40), border: Border.all(color: border, width: 2)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
                  child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: badgeFg)),
                ),
              ),
              if (occupied) Pulse(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _indigo600, shape: BoxShape.circle))),
            ]),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(
                  child: Text(
                    table.name,
                    style: titleStyle.copyWith(fontSize: 44, color: occupied && !dark ? const Color(0xFF312E81) : null),
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.slate400.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.users, size: 10, color: AppColors.slate400),
                      const SizedBox(width: 6),
                      Text('${table.seats} PERS.', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.slate400)),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
    return billing ? Pulse(child: card) : card;
  }
}
