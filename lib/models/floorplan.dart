class PosTable {
  const PosTable({required this.id, required this.name, required this.status, required this.seats, this.virtual = false});
  final int id;
  final String name;
  final String status; // free | occupied | billing | maintenance
  final int seats;
  final bool virtual;

  factory PosTable.fromJson(Map<String, dynamic> j) => PosTable(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? 'free',
        seats: (j['seats'] as num?)?.toInt() ?? 0,
        virtual: j['virtual'] == true,
      );
}

class Floor {
  const Floor({required this.id, required this.name, required this.tables});
  final int id;
  final String name;
  final List<PosTable> tables;

  factory Floor.fromJson(Map<String, dynamic> j) => Floor(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        tables: ((j['tables'] as List?) ?? const []).map((e) => PosTable.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
