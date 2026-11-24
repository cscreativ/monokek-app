class OrderItemModifier {
  const OrderItemModifier({required this.id, required this.name, required this.price, required this.quantity});
  final int id;
  final String name;
  final double price;
  final int quantity;
  factory OrderItemModifier.fromJson(Map<String, dynamic> j) => OrderItemModifier(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      );
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.total,
    required this.status,
    required this.modifiers,
  });
  final int id;
  final int productId;
  final String productName;
  final int qty;
  final double total;
  final String status;
  final List<OrderItemModifier> modifiers;

  factory OrderItem.fromJson(Map<String, dynamic> j) {
    final product = (j['product'] as Map<String, dynamic>?) ?? const {};
    return OrderItem(
      id: (j['id'] as num).toInt(),
      productId: (product['id'] as num?)?.toInt() ?? 0,
      productName: product['name'] as String? ?? '',
      qty: (j['qty'] as num?)?.toInt() ?? 1,
      total: (j['total'] as num?)?.toDouble() ?? 0,
      status: j['status'] as String? ?? 'pending',
      modifiers: ((j['modifiers'] as List?) ?? const []).map((e) => OrderItemModifier.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class Round {
  const Round({required this.id, required this.number, required this.status, required this.sentAt, required this.items, required this.total, this.voidReason});
  final int id;
  final int number;
  final String status; // sent | served | voided ...
  final DateTime? sentAt;
  final List<OrderItem> items;
  final double total;
  final String? voidReason;

  /// A round can only be edited while it has not been served yet.
  bool get editable => status == 'sent';

  factory Round.fromJson(Map<String, dynamic> j) => Round(
        id: (j['id'] as num).toInt(),
        number: (j['roundNumber'] as num?)?.toInt() ?? 1,
        status: j['status'] as String? ?? '',
        sentAt: j['sentAt'] == null ? null : DateTime.tryParse(j['sentAt'] as String)?.toLocal(),
        items: ((j['items'] as List?) ?? const []).map((e) => OrderItem.fromJson(e as Map<String, dynamic>)).toList(),
        total: (j['totalRound'] as num?)?.toDouble() ?? 0,
        voidReason: j['voidReason'] as String?,
      );
}

class Order {
  const Order({
    required this.id,
    required this.uuid,
    required this.reference,
    required this.status,
    required this.subtotal,
    required this.total,
    required this.formattedTotal,
    required this.rounds,
    required this.time,
    this.tableId,
    this.tableName,
    this.waiterName,
    this.type = '',
    this.discount = 0,
    this.couponCode,
    this.note,
    this.date = '',
  });
  final int id;
  final String uuid;
  final String reference;
  final String status;
  final double subtotal;
  final double total;
  final String formattedTotal;
  final List<Round> rounds;
  final String time; // "H:i"
  final int? tableId;
  final String? tableName;
  final String? waiterName;
  final String type;
  final double discount;
  final String? couponCode;
  final String? note;
  final String date; // "d/m/Y"

  factory Order.fromJson(Map<String, dynamic> j) {
    final amounts = (j['amounts'] as Map<String, dynamic>?) ?? const {};
    final table = j['table'] as Map<String, dynamic>?;
    return Order(
      id: (j['id'] as num).toInt(),
      uuid: j['uuid'] as String? ?? '',
      reference: j['reference'] as String? ?? '',
      status: j['status'] as String? ?? '',
      subtotal: (amounts['subtotal'] as num?)?.toDouble() ?? 0,
      total: (amounts['total'] as num?)?.toDouble() ?? 0,
      formattedTotal: amounts['formattedTotal'] as String? ?? '',
      rounds: ((j['rounds'] as List?) ?? const []).map((e) => Round.fromJson(e as Map<String, dynamic>)).toList(),
      time: j['time'] as String? ?? '',
      tableId: (table?['id'] as num?)?.toInt(),
      tableName: table?['name'] as String?,
      waiterName: (j['waiter'] as Map<String, dynamic>?)?['name'] as String?,
      type: j['type'] as String? ?? '',
      discount: (amounts['discount'] as num?)?.toDouble() ?? 0,
      couponCode: amounts['couponCode'] as String?,
      note: j['note'] as String?,
      date: j['date'] as String? ?? '',
    );
  }
}

class SendRoundResult {
  const SendRoundResult(this.order, this.skippedProductNames);
  final Order order;
  final List<String> skippedProductNames;
}
