import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/catalog.dart';
import 'cart_store.dart';

/// Option picker for a product's modifier groups (port of ModifierModal.tsx).
/// Returns the chosen modifiers, or null if dismissed.
Future<List<CartModifier>?> showModifierDialog(BuildContext context, Product product) => showDialog<List<CartModifier>>(
      context: context,
      builder: (_) => _ModifierDialog(product: product),
    );

class _ModifierDialog extends StatefulWidget {
  const _ModifierDialog({required this.product});
  final Product product;
  @override
  State<_ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<_ModifierDialog> {
  /// groupId -> (itemId -> quantity)
  final Map<int, Map<int, int>> _sel = {};

  int _groupQty(ModifierGroup g) => (_sel[g.id] ?? const {}).values.fold(0, (s, q) => s + q);
  bool _satisfied(ModifierGroup g) => _groupQty(g) >= g.effectiveMin;
  bool get _canConfirm => widget.product.modifiers.every(_satisfied);

  /// Radio behaviour, reserved for groups whose maxSelect is exactly 1 (driven by config, not `type`).
  void _selectSingle(ModifierGroup g, ModifierItem item) => setState(() => _sel[g.id] = {item.id: 1});

  void _bump(ModifierGroup g, ModifierItem item, int delta) {
    setState(() {
      final cur = Map<int, int>.from(_sel[g.id] ?? const {});
      if (delta > 0 && g.maxSelect != null && _groupQty(g) >= g.maxSelect!) return;
      final next = (cur[item.id] ?? 0) + delta;
      if (next <= 0) {
        cur.remove(item.id);
      } else {
        cur[item.id] = next;
      }
      _sel[g.id] = cur;
    });
  }

  void _confirm() {
    final out = <CartModifier>[];
    for (final g in widget.product.modifiers) {
      for (final item in g.items) {
        final q = _sel[g.id]?[item.id] ?? 0;
        if (q > 0) out.add(CartModifier(id: item.id, name: item.name, price: item.price, quantity: q));
      }
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'OPTIONS '),
                  TextSpan(text: widget.product.name.toUpperCase(), style: TextStyle(color: scheme.onSurfaceVariant)),
                ]),
                style: titleStyle.copyWith(fontSize: 22),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              shrinkWrap: true,
              children: [for (final g in widget.product.modifiers) _group(context, g)],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: FilledButton(
              onPressed: _canConfirm ? _confirm : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
              child: const Text('CONFIRMER LA SÉLECTION', style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _group(BuildContext context, ModifierGroup g) {
    final scheme = Theme.of(context).colorScheme;
    final single = g.maxSelect == 1;
    final atLimit = g.maxSelect != null && _groupQty(g) >= g.maxSelect!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(g.name.toUpperCase(), style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 1.5))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: g.required ? AppColors.warning.withValues(alpha: 0.12) : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              g.ruleLabel.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: g.required ? const Color(0xFFD97706) : scheme.onSurfaceVariant),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        for (final item in g.items) _itemRow(context, g, item, single: single, atLimit: atLimit),
      ]),
    );
  }

  Widget _itemRow(BuildContext context, ModifierGroup g, ModifierItem item, {required bool single, required bool atLimit}) {
    final scheme = Theme.of(context).colorScheme;
    final qty = _sel[g.id]?[item.id] ?? 0;
    final selected = qty > 0;
    final priceText = item.price > 0 ? '+ ${formatCurrency(item.price)}' : 'Inclus';

    Widget trailing;
    if (single) {
      trailing = selected
          ? Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
              child: Icon(LucideIcons.check, size: 12, color: scheme.onPrimary),
            )
          : Text((item.price > 0 ? 'Choisir' : 'Inclus').toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.slate400));
    } else if (selected) {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(LucideIcons.minus, size: 14), onPressed: () => _bump(g, item, -1)),
        SizedBox(width: 20, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(LucideIcons.plus, size: 14), onPressed: atLimit ? null : () => _bump(g, item, 1)),
      ]);
    } else {
      trailing = OutlinedButton(onPressed: atLimit ? null : () => _bump(g, item, 1), child: const Text('Ajouter'));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: single ? () => _selectSingle(g, item) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? scheme.primary.withValues(alpha: 0.05) : null,
            border: Border.all(color: selected ? scheme.primary : scheme.outline, width: 2),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selected && single ? scheme.primary : null)),
                Text(priceText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: selected ? scheme.primary : AppColors.slate400)),
              ]),
            ),
            trailing,
          ]),
        ),
      ),
    );
  }
}
