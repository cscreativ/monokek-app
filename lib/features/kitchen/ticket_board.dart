import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/theme/app_theme.dart';
import '../../models/kitchen.dart';
import '../../shared/widgets/pulse.dart';

const _orange50 = Color(0xFFFFF7ED);
const _orange100 = Color(0xFFFFEDD5);
const _orange600 = Color(0xFFEA580C);

class TicketEmptyState extends StatelessWidget {
  const TicketEmptyState({super.key, this.icon = LucideIcons.chefHat});
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 160),
        Opacity(
          opacity: 0.3,
          child: Column(children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(48)),
              child: Icon(icon, size: 60),
            ),
            const SizedBox(height: 24),
            Text('TOUT EST PRÊT !', style: titleStyle.copyWith(fontSize: 30)),
            const SizedBox(height: 8),
            Text('AUCUN TICKET EN ATTENTE POUR LE MOMENT', style: microLabelStyle.copyWith(fontSize: 12, letterSpacing: 4)),
          ]),
        ),
      ]);
}

/// Responsive grid of ticket cards, shared by the kitchen KDS and the bar counter screen.
/// [onChange] performs the status transition (and throws on failure).
class TicketBoard extends StatelessWidget {
  const TicketBoard({super.key, required this.tickets, required this.onChange, this.finalStatus = TicketStatus.ready, this.doneMessage = 'Commande prête à servir !'});
  final List<KitchenTicket> tickets;
  final Future<void> Function(int ticketId, TicketStatus next) onChange;
  final TicketStatus finalStatus;
  final String doneMessage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 24.0;
      final cols = (c.maxWidth / 340).floor().clamp(1, 5);
      final width = (c.maxWidth - 2 * gap - (cols - 1) * gap) / cols;
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(gap),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tickets)
              SizedBox(width: width, child: TicketCard(key: ValueKey(t.id), ticket: t, onChange: onChange, finalStatus: finalStatus, doneMessage: doneMessage)),
          ],
        ),
      );
    });
  }
}

class TicketCard extends StatefulWidget {
  const TicketCard({super.key, required this.ticket, required this.onChange, required this.finalStatus, required this.doneMessage});
  final KitchenTicket ticket;
  final Future<void> Function(int ticketId, TicketStatus next) onChange;
  final TicketStatus finalStatus;
  final String doneMessage;
  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  bool _busy = false;

  Future<void> _change(TicketStatus next) async {
    setState(() => _busy = true);
    try {
      await widget.onChange(widget.ticket.id, next);
      if (mounted && next == widget.finalStatus) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.doneMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e, 'Action impossible'))));
      }
    } finally {
      // The card survives a pending → preparing change, so the busy flag must be released.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final t = widget.ticket;
    final preparing = t.status == TicketStatus.preparing;
    final footerBg = dark ? AppColors.darkMuted.withValues(alpha: 0.5) : AppColors.slate50;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      transform: Matrix4.translationValues(0, preparing ? -4 : 0, 0),
      decoration: BoxDecoration(
        color: dark ? AppColors.slate900 : Colors.white,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: preparing ? AppColors.orange : Colors.transparent, width: 2),
        boxShadow: preparing ? [BoxShadow(color: AppColors.orange.withValues(alpha: 0.12), blurRadius: 0, spreadRadius: 4)] : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(24),
          color: preparing ? (dark ? AppColors.orange.withValues(alpha: 0.12) : _orange50) : footerBg,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(LucideIcons.layers, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('ROUND ${t.roundNumber}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: scheme.primary)),
                ]),
                const SizedBox(height: 4),
                Text(t.table, style: titleStyle.copyWith(fontSize: 30, height: 1)),
                const SizedBox(height: 8),
                Text('REF: ${t.reference}', style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 10, letterSpacing: 2)),
                if (t.originBranchName != null) ...[
                  const SizedBox(height: 8),
                  // Central kitchen: which branch this order comes from (and will be paid at).
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.store, size: 12, color: scheme.primary),
                    const SizedBox(width: 6),
                    Flexible(child: Text(t.originBranchName!.toUpperCase(), overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: scheme.primary))),
                  ]),
                ],
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: dark ? AppColors.slate900 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dark ? AppColors.darkMuted : const Color(0xFFE2E8F0), width: 2),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.timer, size: 12, color: scheme.primary),
                const SizedBox(width: 6),
                Text(t.createdAt, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              ]),
            ),
          ]),
        ),
        // Items
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 150),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < t.items.length; i++) ...[
                if (i > 0) const SizedBox(height: 20),
                _ItemRow(item: t.items[i], dark: dark),
              ],
            ]),
          ),
        ),
        // Action
        Container(
          padding: const EdgeInsets.all(16),
          color: footerBg,
          child: preparing
              ? Pulse(
                  enabled: !_busy,
                  child: _ActionButton(
                    label: 'TERMINER',
                    icon: LucideIcons.circleCheck,
                    color: AppColors.orange,
                    busy: _busy,
                    onTap: () => _change(widget.finalStatus),
                  ),
                )
              : _ActionButton(
                  label: 'COMMENCER',
                  icon: LucideIcons.circlePlay,
                  color: dark ? AppColors.darkPrimary : AppColors.slate900,
                  foreground: dark ? AppColors.darkOnPrimary : Colors.white,
                  busy: _busy,
                  onTap: () => _change(TicketStatus.preparing),
                ),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.dark});
  final TicketItem item;
  final bool dark;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: dark ? Colors.white : AppColors.slate950, borderRadius: BorderRadius.circular(12)),
          child: Text('${item.qty}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: dark ? AppColors.slate950 : Colors.white)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name.toUpperCase(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, height: 1.2)),
            if (item.modifiers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final m in item.modifiers)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _orange100, borderRadius: BorderRadius.circular(6)),
                    child: Text('+ ${m.name} (${m.quantity})'.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _orange600)),
                  ),
              ]),
            ],
          ]),
        ),
      ]);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.color, required this.busy, required this.onTap, this.foreground = Colors.white});
  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: busy
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: foreground))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 20),
                const SizedBox(width: 12),
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
              ]),
      );
}
