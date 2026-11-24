class CashRegister {
  const CashRegister({required this.id, required this.name, required this.branchId, required this.isOpen, this.openedByUserName});
  final int id;
  final String name;
  final int branchId;
  final bool isOpen;
  final String? openedByUserName;

  factory CashRegister.fromJson(Map<String, dynamic> j) => CashRegister(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        branchId: (j['branchId'] as num?)?.toInt() ?? 0,
        isOpen: j['isOpen'] == true,
        openedByUserName: j['openedByUserName'] as String?,
      );
}

class CashSession {
  const CashSession({required this.id, required this.registerId, required this.registerName, required this.openingAmount, required this.openedAt});
  final int id;
  final int registerId;
  final String registerName;
  final double openingAmount;
  final DateTime? openedAt;

  factory CashSession.fromJson(Map<String, dynamic> j) => CashSession(
        id: (j['id'] as num).toInt(),
        registerId: (j['registerId'] as num?)?.toInt() ?? 0,
        registerName: j['registerName'] as String? ?? '',
        openingAmount: (j['openingAmount'] as num?)?.toDouble() ?? 0,
        openedAt: j['openedAt'] == null ? null : DateTime.tryParse(j['openedAt'] as String)?.toLocal(),
      );
}

class PaymentBreakdown {
  const PaymentBreakdown({required this.method, required this.total});
  final String method;
  final double total;
  factory PaymentBreakdown.fromJson(Map<String, dynamic> j) =>
      PaymentBreakdown(method: j['method'] as String? ?? '', total: (j['total'] as num?)?.toDouble() ?? 0);
}

class CashStatus {
  const CashStatus({required this.isOpen, this.session});
  final bool isOpen;
  final CashSession? session;
  factory CashStatus.fromJson(Map<String, dynamic> j) => CashStatus(
        isOpen: j['isOpen'] == true,
        session: j['session'] == null ? null : CashSession.fromJson(j['session'] as Map<String, dynamic>),
      );
}

class CashSummary {
  const CashSummary({required this.session, required this.payments, required this.totalSales});
  final CashSession session;
  final List<PaymentBreakdown> payments;
  final double totalSales;
  factory CashSummary.fromJson(Map<String, dynamic> j) => CashSummary(
        session: CashSession.fromJson(j['session'] as Map<String, dynamic>),
        payments: ((j['paymentsDetail'] as List?) ?? const []).map((e) => PaymentBreakdown.fromJson(e as Map<String, dynamic>)).toList(),
        totalSales: (j['totalSales'] as num?)?.toDouble() ?? 0,
      );
}

class CloseReport {
  const CloseReport({
    required this.openedAt,
    required this.closedAt,
    required this.openingAmount,
    required this.totalPayments,
    required this.expectedTotal,
    required this.actualTotal,
    required this.difference,
    required this.payments,
    this.note,
  });
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double openingAmount;
  final double totalPayments;
  final double expectedTotal;
  final double actualTotal;
  final double difference;
  final String? note;
  final List<PaymentBreakdown> payments;

  factory CloseReport.fromJson(Map<String, dynamic> j) {
    final r = j['report'] as Map<String, dynamic>;
    DateTime? d(String k) => r[k] == null ? null : DateTime.tryParse(r[k] as String)?.toLocal();
    double n(String k) => (r[k] as num?)?.toDouble() ?? 0;
    return CloseReport(
      openedAt: d('openedAt'),
      closedAt: d('closedAt'),
      openingAmount: n('openingAmount'),
      totalPayments: n('totalPayments'),
      expectedTotal: n('expectedTotal'),
      actualTotal: n('actualTotal'),
      difference: n('difference'),
      note: r['note'] as String?,
      payments: ((r['paymentsDetail'] as List?) ?? const []).map((e) => PaymentBreakdown.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
