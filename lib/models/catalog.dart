class ModifierItem {
  const ModifierItem({required this.id, required this.name, required this.price});
  final int id;
  final String name;
  final double price;
  factory ModifierItem.fromJson(Map<String, dynamic> j) => ModifierItem(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
      );
}

/// A group of options attached to a product (accompaniment / supplement) with selection rules.
class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    required this.type,
    required this.required,
    required this.minSelect,
    required this.maxSelect,
    required this.items,
  });
  final int id;
  final String name;
  final String type;
  final bool required;
  final int minSelect;
  final int? maxSelect;
  final List<ModifierItem> items;

  /// Same rule as OrderService#validateModifierGroups: `required` forces a minimum of 1.
  int get effectiveMin => required ? (minSelect < 1 ? 1 : minSelect) : minSelect;

  /// Label of the selection rule. A group can be flagged optional yet still have minSelect > 0
  /// (the server then refuses an empty selection), so the minimum is shown either way.
  String get ruleLabel {
    final min = effectiveMin;
    final max = maxSelect;
    final range = max == null ? 'min $min' : (min == max ? '$min' : '$min-$max');
    if (required) return 'Obligatoire · $range';
    if (min > 0) return 'Au moins $min${max != null && max != min ? ' · max $max' : ''}';
    return max != null ? 'Optionnel · max $max' : 'Optionnel';
  }

  factory ModifierGroup.fromJson(Map<String, dynamic> j) => ModifierGroup(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'supplement',
        required: j['required'] == true,
        minSelect: (j['minSelect'] as num?)?.toInt() ?? 0,
        maxSelect: (j['maxSelect'] as num?)?.toInt(),
        items: ((j['items'] as List?) ?? const []).map((e) => ModifierItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryName,
    required this.type,
    required this.stockCount,
    required this.modifiers,
    this.imageUrl,
  });
  final int id;
  final String name;
  final double price;
  final String categoryName;
  final String type; // "storable" tracks real stock
  final int stockCount;
  final String? imageUrl;
  final List<ModifierGroup> modifiers;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        categoryName: j['categoryName'] as String? ?? '',
        type: j['type'] as String? ?? '',
        stockCount: (j['stockCount'] as num?)?.toInt() ?? 0,
        imageUrl: j['image'] as String?,
        modifiers: ((j['modifiers'] as List?) ?? const []).map((e) => ModifierGroup.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
