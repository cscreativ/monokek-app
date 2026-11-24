import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../data/pos_api.dart';
import '../../models/ordering.dart';
import 'cart_store.dart';
import 'pos_providers.dart';
import 'stock_guard.dart';

/// Order recap + round being composed + "launch round" action (port of CartPanel in PosContent.tsx).
/// Owns the round-sending and round-editing logic so the desktop aside and the mobile sheet share it.
class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key, required this.tableId, required this.tableLabel, this.onSent});
  final int tableId;
  final String tableLabel;
  final VoidCallback? onSent;
  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  bool _submitting = false;

  /// Idempotency key of the send in progress. Kept across failed attempts of the SAME cart so a retry after a
  /// lost response cannot create a second round; replaced as soon as the cart content changes, cleared on success.
  String? _sendKey;
  String? _sendId;

  String _idFor(String signature) {
    if (_sendId == null || _sendKey != signature) {
      _sendKey = signature;
      _sendId = _newUuid();
    }
    return _sendId!;
  }

  static String _newUuid() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }
  final Set<int> _pendingItems = {};

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  Future<void> _updateRoundItem(Round round, OrderItem item, int newQty) async {
    if (_pendingItems.contains(item.id)) return; // anti double-tap
    if (newQty > item.qty) {
      final products = ref.read(productsProvider).value ?? const [];
      final p = products.where((p) => p.id == item.productId).firstOrNull;
      if (p != null &&
          wouldExceedStock(
            allowOversell: ref.read(allowOversellProvider).value ?? false,
            cart: ref.read(cartProvider),
            order: ref.read(activeOrderProvider(widget.tableId)).value,
            productId: p.id,
            productType: p.type,
            stockCount: p.stockCount,
          )) {
        return _toast('Stock insuffisant pour ${p.name}', error: true);
      }
    }
    setState(() => _pendingItems.add(item.id));
    try {
      final order = await ref.read(posApiProvider).updateRoundItemQty(round.id, item.id, newQty);
      ref.read(activeOrderProvider(widget.tableId).notifier).setOrder(order);
      ref.read(cartProvider.notifier).syncOrderId(order.id);
      if (newQty == 0 && mounted) _toast('Article retiré du round');
    } catch (e) {
      if (mounted) _toast(errorMessage(e, 'Impossible de modifier cet article'), error: true);
    } finally {
      if (mounted) setState(() => _pendingItems.remove(item.id));
    }
  }

  void _updateCartQty(CartItem item, int qty) {
    if (qty > item.qty) {
      final products = ref.read(productsProvider).value ?? const [];
      final p = products.where((p) => p.id == item.productId).firstOrNull;
      if (p != null &&
          wouldExceedStock(
            allowOversell: ref.read(allowOversellProvider).value ?? false,
            cart: ref.read(cartProvider),
            order: ref.read(activeOrderProvider(widget.tableId)).value,
            productId: p.id,
            productType: p.type,
            stockCount: p.stockCount,
          )) {
        return _toast('Stock insuffisant pour ${p.name}', error: true);
      }
    }
    ref.read(cartProvider.notifier).updateQty(item.id, qty);
  }

  /// A dead orderId (paid/cancelled elsewhere) answers 409 with these exact messages. Matching the
  /// message — not just the status — avoids masking the other 409 ("order belongs to another
  /// table"), which must never be silently retried into a duplicate order.
  bool _isStaleOrder(Object e, int? orderId) {
    if (e is! DioException || e.response?.statusCode != 409 || orderId == null) return false;
    final m = errorMessage(e, '');
    return m.contains('déjà payée') || m.contains('est annulée');
  }

  Future<void> _sendRound() async {
    final cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return _toast('Le panier est vide', error: true);
    if (_submitting) return;
    setState(() => _submitting = true);

    final api = ref.read(posApiProvider);
    final lines = [
      for (final i in cart.items)
        {
          'productId': i.productId,
          'qty': i.qty,
          'modifiers': [for (final m in i.modifiers) {'modifierItemId': m.id, 'quantity': m.quantity < 1 ? 1 : m.quantity}],
        }
    ];

    final requestId = _idFor('${widget.tableId}|${jsonEncode(lines)}');

    try {
      SendRoundResult result;
      try {
        result = await api.sendRound(tableId: widget.tableId, orderId: cart.orderId, items: lines, clientRequestId: requestId);
      } catch (e) {
        if (!_isStaleOrder(e, cart.orderId)) rethrow;
        ref.read(cartProvider.notifier).clearStaleOrderId(widget.tableId);
        result = await api.sendRound(tableId: widget.tableId, items: lines, clientRequestId: requestId);
      }
      _sendKey = _sendId = null;

      ref.read(activeOrderProvider(widget.tableId).notifier).setOrder(result.order);
      ref.read(cartProvider.notifier)
        ..syncOrderId(result.order.id)
        ..clearItems();
      ref.invalidate(floorsProvider);

      if (!mounted) return;
      if (result.skippedProductNames.isNotEmpty) {
        // Saved on the order but no ticket was generated (category without a kitchen station).
        _toast('Non envoyé en cuisine : ${result.skippedProductNames.join(', ')} — assignez une station à leur catégorie.');
      } else {
        _toast('Round envoyé !');
      }
      widget.onSent?.call();
    } catch (e) {
      if (mounted) _toast(errorMessage(e, "Erreur lors de l'envoi"), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cart = ref.watch(cartProvider);
    final order = ref.watch(activeOrderProvider(widget.tableId)).value;
    final rounds = order?.rounds ?? const <Round>[];
    final roundCount = rounds.length + (cart.items.isEmpty ? 0 : 1);

    return Material(
      color: dark ? AppColors.slate900 : Colors.white,
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          color: dark ? null : AppColors.slate50.withValues(alpha: 0.5),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(12)),
              child: Icon(LucideIcons.utensils, size: 20, color: scheme.onPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TABLE ${widget.tableLabel}'.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle.copyWith(fontSize: 20, height: 1)),
                const SizedBox(height: 4),
                Text('SUIVI DE COMMANDE', style: microLabelStyle.copyWith(fontSize: 9, color: AppColors.slate400)),
              ]),
            ),
            if (order != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
                child: Text('#${order.reference.contains('-') ? order.reference.split('-')[1] : order.reference}',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: scheme.onPrimary)),
              ),
          ]),
        ),
        const Divider(height: 1),

        // Rounds + new round
        Expanded(
          child: (cart.items.isEmpty && rounds.isEmpty)
              ? Center(
                  child: Opacity(
                    opacity: 0.25,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(LucideIcons.utensils, size: 48),
                      const SizedBox(height: 16),
                      Text('EN ATTENTE DE COMMANDE', style: microLabelStyle.copyWith(letterSpacing: 2)),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final r in rounds) _roundCard(context, r),
                  if (cart.items.isNotEmpty) _newRound(context, cart),
                ]),
        ),

        // Footer
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          decoration: BoxDecoration(
            color: dark ? AppColors.slate900 : Colors.white,
            border: Border(top: BorderSide(color: scheme.outline)),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 40, offset: Offset(0, -10))],
          ),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('CUMUL ROUNDS', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 1.5)),
                Text(formatCurrency(order?.subtotal ?? 0), style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TOTAL GÉNÉRAL', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 2)),
                    // Large amounts shrink instead of overflowing the 400px panel.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(formatCurrency(cart.total + (order?.total ?? 0)), style: titleStyle.copyWith(fontSize: 28)),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                  child: Text('$roundCount ROUNDS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.primary)),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: (cart.items.isEmpty || _submitting) ? null : _sendRound,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  backgroundColor: dark ? scheme.primary : AppColors.slate900,
                  foregroundColor: dark ? scheme.onPrimary : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                ),
                child: _submitting
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: dark ? scheme.onPrimary : Colors.white)),
                        const SizedBox(width: 12),
                        const Flexible(child: Text('ENVOI EN COURS...', overflow: TextOverflow.ellipsis)),
                      ])
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('LANCER LE ROUND ${rounds.length + 1}', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(LucideIcons.chevronRight, size: 18),
                      ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _roundCard(BuildContext context, Round round) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sent = round.sentAt == null ? '--:--' : DateFormat('HH:mm').format(round.sentAt!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppColors.darkMuted.withValues(alpha: 0.4) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: dark ? null : AppColors.slate50,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(
                  'ROUND ${round.number} · ENVOYÉ À $sent',
                  overflow: TextOverflow.ellipsis,
                  style: microLabelStyle.copyWith(fontSize: 10, letterSpacing: 0.5, color: AppColors.slate400),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: scheme.outline)),
                child: Text(round.status == 'sent' ? '⏳ EN CUISINE' : (round.status == 'voided' ? 'ANNULÉ' : '✅ SERVI'),
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [for (final item in round.items) _roundItem(context, round, item)]),
          ),
        ]),
      ),
    );
  }

  Widget _roundItem(BuildContext context, Round round, OrderItem item) {
    final scheme = Theme.of(context).colorScheme;
    final pending = _pendingItems.contains(item.id);
    final editable = round.editable;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (editable)
          _Stepper(qty: item.qty, disabled: pending, onMinus: () => _updateRoundItem(round, item, item.qty - 1), onPlus: () => _updateRoundItem(round, item, item.qty + 1))
        else
          Text('${item.qty}x', style: TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: scheme.primary)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.productName.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
            for (final m in item.modifiers)
              Text('+ ${m.name}', style: const TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: AppColors.slate400)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(formatCurrency(item.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.slate400)),
        if (editable)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.trash2, size: 14),
            color: AppColors.slate400,
            onPressed: pending ? null : () => _updateRoundItem(round, item, 0),
          ),
      ]),
    );
  }

  Widget _newRound(BuildContext context, CartState cart) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkMuted.withValues(alpha: 0.2) : AppColors.slate50,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
          child: Text('NOUVEAU ROUND', style: microLabelStyle.copyWith(color: scheme.onPrimary, letterSpacing: 2)),
        ),
        const SizedBox(height: 12),
        for (final item in cart.items)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dark ? AppColors.slate900 : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.outline),
            ),
            child: Column(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 14, height: 1.1)),
                    for (final m in item.modifiers)
                      Text('+ ${m.name}${m.quantity > 1 ? ' ×${m.quantity}' : ''}', style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: AppColors.slate400)),
                    const SizedBox(height: 2),
                    Text('${formatCurrency(item.unitPrice)} / unité', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: scheme.primary)),
                  ]),
                ),
                Text(formatCurrency(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _Stepper(qty: item.qty, onMinus: () => _updateCartQty(item, item.qty - 1), onPlus: () => _updateCartQty(item, item.qty + 1)),
                IconButton(
                  icon: const Icon(LucideIcons.trash2, size: 16),
                  color: AppColors.slate400,
                  onPressed: () => ref.read(cartProvider.notifier).removeItem(item.id),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.qty, required this.onMinus, required this.onPlus, this.disabled = false});
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(constraints: const BoxConstraints(minWidth: 32, minHeight: 32), padding: EdgeInsets.zero, icon: const Icon(LucideIcons.minus, size: 12), onPressed: disabled ? null : onMinus),
        SizedBox(width: 22, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
        IconButton(constraints: const BoxConstraints(minWidth: 32, minHeight: 32), padding: EdgeInsets.zero, icon: const Icon(LucideIcons.plus, size: 12), onPressed: disabled ? null : onPlus),
      ]),
    );
  }
}
