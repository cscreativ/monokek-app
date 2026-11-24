import '../../models/ordering.dart';
import 'cart_store.dart';

/// Quantity of a product already committed on this order: the unsent cart plus rounds already
/// sent but unpaid (the server only decrements stock at payment, so `stockCount` alone ignores them).
int qtyCommitted(int productId, CartState cart, Order? order) {
  final inCart = cart.items.where((i) => i.productId == productId).fold(0, (s, i) => s + i.qty);
  final inRounds = (order?.rounds ?? const <Round>[])
      .where((r) => r.status != 'voided')
      .expand((r) => r.items)
      .where((i) => i.productId == productId)
      .fold(0, (s, i) => s + i.qty);
  return inCart + inRounds;
}

/// Only "storable" products have real stock to protect (never rely on `trackStock`, which the
/// admin UI never sets — same convention as ProductService.deductForSale).
bool wouldExceedStock({
  required bool allowOversell,
  required CartState cart,
  required Order? order,
  required int productId,
  required String productType,
  required int stockCount,
}) =>
    !allowOversell && productType == 'storable' && qtyCommitted(productId, cart, order) >= stockCount;
