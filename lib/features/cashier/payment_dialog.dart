import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../data/pos_api.dart';
import '../../models/ordering.dart';
import '../pos/cart_store.dart';
import '../pos/pos_providers.dart';
import 'cashier_providers.dart';

class _Method {
  const _Method(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const _allMethods = [
  _Method('cash', 'Espèces', LucideIcons.banknote),
  _Method('momo', 'MoMo', LucideIcons.smartphone),
  _Method('om', 'OM', LucideIcons.smartphoneCharging),
  _Method('card', 'Carte Bancaire', LucideIcons.creditCard),
  _Method('room_charge', 'Chambre', LucideIcons.bedDouble),
];

/// One slice of a split payment: [amount] settles the bill, [received] is what the client handed over.
class _Part {
  const _Part(this.method, this.amount, this.received);
  final String method;
  final double amount;
  final double received;
}

/// Mirrors the backend limit on the number of slices of one bill.
const _maxParts = 5;

const _padKeys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', 'back'];

/// Cash-in dialog (port of components/pos/PaymentModal.tsx). Resolves true when the order was paid.
Future<bool> showPaymentDialog(BuildContext context, Order order) async {
  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: PaymentView(order: order)),
    ),
  );
  return paid ?? false;
}

class PaymentView extends ConsumerStatefulWidget {
  const PaymentView({super.key, required this.order});
  final Order order;
  @override
  ConsumerState<PaymentView> createState() => _PaymentViewState();
}

class _PaymentViewState extends ConsumerState<PaymentView> {
  late Order _order = widget.order; // replaced by the server's copy after a coupon change
  late String _received = _fmt(widget.order.total);
  String _method = 'cash';
  bool _processing = false;

  // Split payment ("paiement partagé"): the bill is settled by several methods, added one by one.
  bool _split = false;
  final List<_Part> _parts = [];

  final _room = TextEditingController();
  ({int bookingId, String guestName})? _guest;
  String? _roomError;
  bool _checkingRoom = false;

  final _coupon = TextEditingController();
  bool _couponBusy = false;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _room.dispose();
    _coupon.dispose();
    super.dispose();
  }

  double get _receivedValue => double.tryParse(_received) ?? 0;
  bool get _isRoom => _method == 'room_charge';

  static double _round2(double v) => (v * 100).round() / 100;

  /// What is still to be settled once the slices already added are deducted.
  double get _remaining => _round2(_order.total - _parts.fold<double>(0, (sum, p) => sum + p.amount));

  /// Change to give back: on the single method, received minus total; when split, the change of the
  /// slices already added plus a live preview for the cash amount being typed.
  double get _change {
    if (!_split) return (_receivedValue - _order.total).clamp(0, double.infinity);
    final fromParts = _parts.fold<double>(0, (sum, p) => sum + (p.received - p.amount));
    final preview = (_remaining > 0 && _method == 'cash') ? (_receivedValue - _remaining).clamp(0, double.infinity) : 0.0;
    return fromParts + preview;
  }

  bool get _canAdd => _split && !_processing && _remaining > 0 && _receivedValue > 0 && _parts.length < _maxParts;
  bool get _canValidate => _split
      ? !_processing && _parts.isNotEmpty && _remaining <= 0
      : _receivedValue >= _order.total && (!_isRoom || _guest != null) && !_processing;

  void _setSplit(bool on) => setState(() {
        _split = on;
        _parts.clear();
        if (on && _isRoom) _method = 'cash'; // "Chambre" bills the whole order to the folio: never part of a split
        _received = _fmt(_order.total);
      });

  void _addPart() {
    final typed = _receivedValue;
    final remaining = _remaining;
    if (typed <= 0) return _toast('Saisissez un montant', error: true);
    if (_method != 'cash' && typed > remaining + 0.005) {
      return _toast('Le montant dépasse le reste à payer (${formatCurrency(remaining)})', error: true);
    }
    // Cash may exceed what is left (the change is given back); the slice itself never settles more than the rest.
    final amount = typed < remaining ? typed : remaining;
    setState(() {
      _parts.add(_Part(_method, amount, typed));
      final left = _remaining;
      _received = left > 0 ? _fmt(left) : '0';
    });
  }

  void _removePart(int index) => setState(() {
        _parts.removeAt(index);
        _received = _fmt(_remaining);
      });

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(context).colorScheme.error : null));

  void _key(String k) => setState(() {
        if (k == 'back') {
          _received = _received.length <= 1 ? '0' : _received.substring(0, _received.length - 1);
        } else if (_received == '0') {
          _received = k == '00' ? '0' : k;
        } else {
          _received += k;
        }
      });

  Future<void> _checkRoom() async {
    final n = _room.text.trim();
    if (n.isEmpty) return;
    setState(() {
      _checkingRoom = true;
      _guest = null;
      _roomError = null;
    });
    try {
      final g = await ref.read(posApiProvider).checkRoom(n);
      if (mounted) setState(() => _guest = g);
    } catch (e) {
      if (mounted) setState(() => _roomError = errorMessage(e, 'Chambre introuvable ou non occupée'));
    } finally {
      if (mounted) setState(() => _checkingRoom = false);
    }
  }

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _couponBusy = true);
    try {
      final updated = await ref.read(posApiProvider).applyCoupon(_order.uuid, code);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _parts.clear(); // the total changed: slices already added no longer add up
        _received = _fmt(updated.total);
      });
      _toast('Coupon ${updated.couponCode} appliqué');
    } catch (e) {
      if (mounted) _toast(errorMessage(e, 'Coupon invalide'), error: true);
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  Future<void> _removeCoupon() async {
    setState(() => _couponBusy = true);
    try {
      final updated = await ref.read(posApiProvider).removeCoupon(_order.uuid);
      if (!mounted) return;
      setState(() {
        _order = updated;
        _parts.clear(); // the total changed: slices already added no longer add up
        _received = _fmt(updated.total);
        _coupon.clear();
      });
      _toast('Coupon retiré');
    } catch (e) {
      if (mounted) _toast(errorMessage(e, 'Impossible de retirer le coupon'), error: true);
    } finally {
      if (mounted) setState(() => _couponBusy = false);
    }
  }

  Future<void> _validate() async {
    if (_split && _remaining > 0) return _toast('Il reste ${formatCurrency(_remaining)} à payer', error: true);
    if (!_split && _receivedValue < _order.total) return _toast('Le montant reçu est insuffisant', error: true);
    if (_isRoom && _room.text.trim().isEmpty) return _toast('Le numéro de chambre est requis', error: true);
    if (_isRoom && _guest == null) return _toast('Vérifiez la chambre et confirmez le client avant de facturer', error: true);

    setState(() => _processing = true);
    try {
      final message = await ref.read(posApiProvider).finalizePayment(
            _order.uuid,
            method: _split ? null : _method,
            amountReceived: _split ? null : _receivedValue,
            roomNumber: !_split && _isRoom ? _room.text.trim() : null,
            payments: _split ? [for (final p in _parts) (method: p.method, amount: p.amount, amountReceived: p.received)] : null,
          );
      // Payment decrements storable stock server-side: refresh the menu so the stock guard is current.
      ref.invalidate(productsProvider);
      ref.invalidate(salesOrdersProvider);
      ref.invalidate(floorsProvider);
      // Compared with the exact paid order id: virtual/counter tables are reused by unrelated orders.
      ref.read(cartProvider.notifier).resetAfterPayment(_order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message ?? 'Paiement validé !')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        _toast(errorMessage(e, 'Une erreur est survenue lors du paiement'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomEnabled = ref.watch(roomChargeEnabledProvider).value ?? false;
    final methods = _allMethods.where((m) => m.key != 'room_charge' || (roomEnabled && !_split)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 860;

    final left = _left(context, methods);
    final right = _right(context);

    // Fixed height (not IntrinsicHeight: the shrink-wrapped numpad grid cannot report intrinsics).
    final height = (MediaQuery.sizeOf(context).height * 0.92).clamp(0.0, 820.0);
    return wide
        ? SizedBox(
            height: height,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: SingleChildScrollView(child: left)),
              SizedBox(width: 400, child: SingleChildScrollView(child: right)),
            ]),
          )
        : SingleChildScrollView(child: Column(children: [left, right]));
  }

  Widget _left(BuildContext context, List<_Method> methods) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? AppColors.slate900.withValues(alpha: 0.4) : AppColors.slate50,
      padding: const EdgeInsets.all(28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 32, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8))),
          const SizedBox(width: 12),
          Flexible(child: Text("FINALISER L'ENCAISSEMENT", style: titleStyle.copyWith(fontSize: 24))),
        ]),
        const SizedBox(height: 24),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final m in methods)
            SizedBox(
              width: 120,
              child: InkWell(
                borderRadius: BorderRadius.circular(32),
                onTap: () => setState(() => _method = m.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                  decoration: BoxDecoration(
                    color: _method == m.key ? scheme.primary : (dark ? AppColors.darkMuted : Colors.white),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: _method == m.key ? scheme.primary : scheme.outline, width: 2),
                  ),
                  child: Column(children: [
                    Icon(m.icon, size: 30, color: _method == m.key ? scheme.onPrimary : AppColors.slate400),
                    const SizedBox(height: 10),
                    Text(m.label.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: _method == m.key ? scheme.onPrimary : null)),
                  ]),
                ),
              ),
            ),
        ]),
        if (!_isRoom) ...[const SizedBox(height: 16), _splitSection(context)],
        if (_isRoom) ...[const SizedBox(height: 20), _roomSection(context)],
        const SizedBox(height: 20),
        _couponSection(context),
        const SizedBox(height: 20),
        _amounts(context),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _change > 0 ? AppColors.success.withValues(alpha: 0.1) : AppColors.slate400.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: _change > 0 ? AppColors.success.withValues(alpha: 0.2) : Colors.transparent, width: 2),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RELIQUAT / MONNAIE', style: microLabelStyle.copyWith(color: _change > 0 ? const Color(0xFF059669) : AppColors.slate400, letterSpacing: 1.5)),
              Text('À rendre au client', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: _change > 0 ? const Color(0xFF059669) : AppColors.slate400)),
            ]),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(formatCurrency(_change), style: titleStyle.copyWith(fontSize: 30, color: _change > 0 ? const Color(0xFF059669) : AppColors.slate400)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  String _methodLabel(String key) => _allMethods.firstWhere((m) => m.key == key, orElse: () => _Method(key, key, LucideIcons.wallet)).label;

  Widget _splitSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = _remaining;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(LucideIcons.split, size: 14, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text('PAIEMENT PARTAGÉ (PLUSIEURS MOYENS)', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 1.5))),
        Switch(value: _split, onChanged: _processing ? null : _setSplit),
      ]),
      if (_split) ...[
        const SizedBox(height: 8),
        for (var i = 0; i < _parts.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.only(left: 16, right: 4),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.2), width: 2),
            ),
            child: Row(children: [
              Expanded(child: Text(_methodLabel(_parts[i].method).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1))),
              Text(formatCurrency(_parts[i].amount), style: const TextStyle(fontWeight: FontWeight.w900)),
              IconButton(
                tooltip: 'Retirer ce paiement',
                onPressed: _processing ? null : () => _removePart(i),
                icon: Icon(LucideIcons.x, size: 16, color: scheme.error),
              ),
            ]),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: (remaining > 0 ? AppColors.slate400 : AppColors.success).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(remaining > 0 ? 'RESTE À PAYER' : 'TOTAL RÉGLÉ', style: microLabelStyle.copyWith(letterSpacing: 1.5)),
            Text(formatCurrency(remaining > 0 ? remaining : _order.total), style: titleStyle.copyWith(fontSize: 22)),
          ]),
        ),
      ],
    ]);
  }

  Widget _roomSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('N° DE CHAMBRE', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 2)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _room,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {
              _guest = null;
              _roomError = null; // a new number invalidates the previous verification
            }),
            onSubmitted: (_) => _checkRoom(),
            style: titleStyle.copyWith(fontSize: 26),
            decoration: const InputDecoration(hintText: 'Ex: 204'),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: (_room.text.trim().isEmpty || _checkingRoom) ? null : _checkRoom,
          style: FilledButton.styleFrom(minimumSize: const Size(110, 58)),
          child: _checkingRoom ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('VÉRIFIER'),
        ),
      ]),
      if (_guest != null) ...[
        const SizedBox(height: 12),
        _Banner(
          color: AppColors.success,
          icon: LucideIcons.shieldCheck,
          title: 'CHAMBRE OCCUPÉE PAR',
          text: _guest!.guestName,
        ),
      ],
      if (_roomError != null) ...[
        const SizedBox(height: 12),
        _Banner(color: scheme.error, icon: LucideIcons.shieldAlert, text: _roomError!),
      ],
    ]);
  }

  Widget _couponSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(LucideIcons.tag, size: 12, color: scheme.primary),
        const SizedBox(width: 4),
        Text('COUPON DE RÉDUCTION', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 2)),
      ]),
      const SizedBox(height: 8),
      if (_order.couponCode != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.success.withValues(alpha: 0.2), width: 2)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${_order.couponCode} appliqué', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857))),
            TextButton.icon(
              onPressed: _couponBusy ? null : _removeCoupon,
              icon: _couponBusy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(LucideIcons.x, size: 14),
              label: const Text('RETIRER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
            ),
          ]),
        )
      else
        Row(children: [
          Expanded(
            child: TextField(
              controller: _coupon,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _applyCoupon(),
              style: const TextStyle(fontWeight: FontWeight.w900),
              decoration: const InputDecoration(hintText: 'Code coupon'),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: (_couponBusy || _coupon.text.trim().isEmpty) ? null : _applyCoupon,
            style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
            child: _couponBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('APPLIQUER'),
          ),
        ]),
    ]);
  }

  Widget _amounts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: dark ? AppColors.darkMuted : Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: scheme.outline, width: 2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_order.discount > 0) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('SOUS-TOTAL', style: microLabelStyle.copyWith(color: AppColors.slate400, letterSpacing: 1.5)),
              Text(formatCurrency(_order.subtotal), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.slate400)),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('REMISE', style: microLabelStyle.copyWith(color: const Color(0xFF059669), letterSpacing: 1.5)),
              Text('- ${formatCurrency(_order.discount)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF059669))),
            ]),
            const Divider(height: 24),
          ],
          Text('NET À PERCEVOIR', style: microLabelStyle.copyWith(color: AppColors.slate400, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(formatCurrency(_order.total), style: titleStyle.copyWith(fontSize: 54, height: 1))),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkMuted : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.15), width: 4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Align(alignment: Alignment.centerLeft, child: Text(_split ? 'MONTANT DE CE PAIEMENT (${_methodLabel(_method).toUpperCase()})' : 'SOMME ENCAISSÉE', style: microLabelStyle.copyWith(color: scheme.primary, letterSpacing: 2))),
          FittedBox(fit: BoxFit.scaleDown, child: Text(_received, style: titleStyle.copyWith(fontSize: 46))),
        ]),
      ),
    ]);
  }

  Widget _right(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.outline))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            for (final k in _padKeys)
              OutlinedButton(
                onPressed: _processing ? null : () => _key(k),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  foregroundColor: k == 'back' ? scheme.error : null,
                  side: BorderSide(color: scheme.outline, width: 2),
                ),
                child: k == 'back' ? const Icon(LucideIcons.delete, size: 28) : Text(k, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _processing ? null : () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const Text('ABANDONNER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppColors.slate400)),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_split && _remaining > 0) ? (_canAdd ? _addPart : null) : (_canValidate ? _validate : null),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(88), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
          child: _processing
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                  SizedBox(width: 10),
                  Flexible(child: Text('TRAITEMENT...', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                ])
              : (_split && _remaining > 0)
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(LucideIcons.plus, size: 30),
                      SizedBox(width: 12),
                      Flexible(child: Text('AJOUTER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                    ])
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(LucideIcons.circleCheck, size: 30),
                      SizedBox(width: 12),
                      Text('VALIDER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    ]),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.title});
  final Color color;
  final IconData icon;
  final String text;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.2), width: 2)),
        child: Row(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Text(title!, style: microLabelStyle.copyWith(color: color, letterSpacing: 1.5)),
              Text(text, style: TextStyle(fontWeight: FontWeight.w900, fontSize: title != null ? 18 : 14, fontStyle: title != null ? FontStyle.italic : null, color: color)),
            ]),
          ),
        ]),
      );
}
