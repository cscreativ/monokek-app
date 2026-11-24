class KitchenStation {
  const KitchenStation({required this.id, required this.name, required this.type, required this.pendingTicketsCount, this.branchId});
  final int id;
  final int? branchId;
  final String name;
  final String type; // KITCHEN | BAR | GRILL | PASTRY | OTHER
  final int pendingTicketsCount;

  factory KitchenStation.fromJson(Map<String, dynamic> j) => KitchenStation(
        id: (j['id'] as num).toInt(),
        branchId: (j['branchId'] as num?)?.toInt(),
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'KITCHEN',
        pendingTicketsCount: (j['pendingTicketsCount'] as num?)?.toInt() ?? 0,
      );
}

enum TicketStatus {
  pending,
  preparing,
  ready,
  served;

  static TicketStatus parse(String? s) => TicketStatus.values.firstWhere((e) => e.name == s, orElse: () => TicketStatus.pending);
}

class TicketModifier {
  const TicketModifier({required this.name, required this.quantity});
  final String name;
  final int quantity;
  factory TicketModifier.fromJson(Map<String, dynamic> j) =>
      TicketModifier(name: j['name'] as String? ?? '', quantity: (j['quantity'] as num?)?.toInt() ?? 1);
}

class TicketItem {
  const TicketItem({required this.id, required this.name, required this.qty, required this.modifiers});
  final int id;
  final String name;
  final int qty;
  final List<TicketModifier> modifiers;
  factory TicketItem.fromJson(Map<String, dynamic> j) => TicketItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        modifiers: ((j['modifiers'] as List?) ?? const []).map((m) => TicketModifier.fromJson(m as Map<String, dynamic>)).toList(),
      );
}

class KitchenTicket {
  const KitchenTicket({
    required this.id,
    required this.reference,
    required this.table,
    required this.status,
    required this.createdAt,
    required this.roundNumber,
    required this.items,
    this.originBranchId,
    this.originBranchName,
  });
  final int id;
  final String reference;
  final String table;
  final TicketStatus status;
  final String createdAt; // server-formatted "H:i"
  final int roundNumber;
  final List<TicketItem> items;

  /// Branch that sent the order. [originBranchName] is only set when it differs from the branch that
  /// prepares it (central kitchen): the server leaves it null for a kitchen's own orders.
  final int? originBranchId;
  final String? originBranchName;

  KitchenTicket copyWith({TicketStatus? status}) => KitchenTicket(
        id: id,
        reference: reference,
        table: table,
        status: status ?? this.status,
        createdAt: createdAt,
        roundNumber: roundNumber,
        items: items,
        originBranchId: originBranchId,
        originBranchName: originBranchName,
      );

  factory KitchenTicket.fromJson(Map<String, dynamic> j) => KitchenTicket(
        id: (j['id'] as num).toInt(),
        reference: j['reference'] as String? ?? '',
        table: j['table']?.toString() ?? '',
        status: TicketStatus.parse(j['status'] as String?),
        createdAt: j['createdAt']?.toString() ?? '',
        roundNumber: (j['roundNumber'] as num?)?.toInt() ?? 1,
        items: ((j['items'] as List?) ?? const []).map((i) => TicketItem.fromJson(i as Map<String, dynamic>)).toList(),
        originBranchId: (j['originBranchId'] as num?)?.toInt(),
        originBranchName: j['originBranchName'] as String?,
      );
}
