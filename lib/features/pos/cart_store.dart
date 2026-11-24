import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_storage.dart';
import '../../models/catalog.dart';

class CartModifier {
  const CartModifier({required this.id, required this.name, required this.price, required this.quantity});
  final int id;
  final String name;
  final double price;
  final int quantity;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price, 'quantity': quantity};
  factory CartModifier.fromJson(Map<String, dynamic> j) => CartModifier(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      );
}

class CartItem {
  const CartItem({required this.id, required this.productId, required this.name, required this.price, required this.qty, required this.modifiers});
  final String id; // productId + sorted modifier selection: identical lines merge
  final int productId;
  final String name;
  final double price; // base unit price, WITHOUT modifiers
  final int qty;
  final List<CartModifier> modifiers;

  double get modifiersTotal => modifiers.fold(0.0, (s, m) => s + m.price * (m.quantity < 1 ? 1 : m.quantity));
  double get unitPrice => price + modifiersTotal;
  double get lineTotal => unitPrice * qty;

  CartItem withQty(int q) => CartItem(id: id, productId: productId, name: name, price: price, qty: q, modifiers: modifiers);

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'name': name,
        'price': price,
        'qty': qty,
        'modifiers': modifiers.map((m) => m.toJson()).toList(),
      };
  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        id: j['id'] as String,
        productId: (j['productId'] as num).toInt(),
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        modifiers: ((j['modifiers'] as List?) ?? const []).map((m) => CartModifier.fromJson(m as Map<String, dynamic>)).toList(),
      );
}

class CartState {
  const CartState({this.tableId, this.orderId, this.items = const []});
  final int? tableId;
  final int? orderId;
  final List<CartItem> items;

  double get total => items.fold(0.0, (s, i) => s + i.lineTotal);
  int get count => items.fold(0, (s, i) => s + i.qty);

  CartState copyWith({int? tableId, Object? orderId = _keep, List<CartItem>? items}) =>
      CartState(tableId: tableId ?? this.tableId, orderId: identical(orderId, _keep) ? this.orderId : orderId as int?, items: items ?? this.items);

  static const _keep = Object();

  Map<String, dynamic> toJson() => {'tableId': tableId, 'orderId': orderId, 'items': items.map((i) => i.toJson()).toList()};
  factory CartState.fromJson(Map<String, dynamic> j) => CartState(
        tableId: (j['tableId'] as num?)?.toInt(),
        orderId: (j['orderId'] as num?)?.toInt(),
        items: ((j['items'] as List?) ?? const []).map((i) => CartItem.fromJson(i as Map<String, dynamic>)).toList(),
      );
}

/// The round being composed for a table, persisted across restarts (port of use-cart-store.ts).
/// It only ever holds the CURRENT, unsent round — sent rounds come from the server's order.
final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

class CartController extends Notifier<CartState> {
  static const _key = 'mono-kek-cart-storage';

  @override
  CartState build() {
    final raw = ref.read(storageProvider).getString(_key);
    if (raw == null) return const CartState();
    try {
      return CartState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CartState();
    }
  }

  void _set(CartState next) {
    state = next;
    ref.read(storageProvider).setString(_key, jsonEncode(next.toJson()));
  }

  /// Resets only on a real table change: a background refetch must never wipe the round being composed.
  void initForTable(int tableId) {
    if (state.tableId == tableId) return;
    _set(CartState(tableId: tableId));
  }

  /// Adopts the server's order id without touching the local items.
  void syncOrderId(int? orderId) {
    if (state.orderId == orderId) return;
    _set(state.copyWith(orderId: orderId));
  }

  /// [price] is the BASE price; modifier extras are added by [CartItem.unitPrice].
  void addItem({required Product product, List<CartModifier> modifiers = const []}) {
    final key = '${product.id}-${(modifiers.map((m) => '${m.id}-q${m.quantity}').toList()..sort()).join('|')}';
    final items = [...state.items];
    final idx = items.indexWhere((i) => i.id == key);
    if (idx >= 0) {
      items[idx] = items[idx].withQty(items[idx].qty + 1);
    } else {
      items.add(CartItem(id: key, productId: product.id, name: product.name, price: product.price, qty: 1, modifiers: modifiers));
    }
    _set(state.copyWith(items: items));
  }

  void updateQty(String id, int qty) {
    final items = qty <= 0 ? state.items.where((i) => i.id != id).toList() : [for (final i in state.items) i.id == id ? i.withQty(qty) : i];
    _set(state.copyWith(items: items));
  }

  void removeItem(String id) => _set(state.copyWith(items: state.items.where((i) => i.id != id).toList()));

  /// After a round is sent: orderId is preserved so the next round attaches to the same order.
  void clearItems() => _set(state.copyWith(items: const []));

  /// Drops a stale (paid/cancelled) orderId but keeps the selection so nothing is retyped.
  void clearStaleOrderId(int? tableId) {
    if (tableId != null && state.tableId != tableId) return;
    _set(state.copyWith(orderId: null));
  }

  /// Only resets if the PAID order is exactly the one this cart tracks (virtual tables are reused).
  void resetAfterPayment(int? paidOrderId) {
    if (paidOrderId == null || state.orderId != paidOrderId) return;
    _set(CartState(tableId: state.tableId));
  }
}
