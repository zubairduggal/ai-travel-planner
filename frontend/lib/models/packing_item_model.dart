/// Editable packing checklist item persisted per trip (FM4).
class PackingItemModel {
  const PackingItemModel({
    required this.id,
    required this.title,
    this.category = 'Essentials',
    this.isPacked = false,
  });

  final String id;
  final String title;
  final String category;
  final bool isPacked;

  factory PackingItemModel.fromJson(Map<String, dynamic> json) {
    return PackingItemModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? 'Essentials',
      isPacked: json['is_packed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'is_packed': isPacked,
    };
  }

  PackingItemModel copyWith({
    String? id,
    String? title,
    String? category,
    bool? isPacked,
  }) {
    return PackingItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      isPacked: isPacked ?? this.isPacked,
    );
  }

  static List<PackingItemModel> defaultItems() {
    return const [
      PackingItemModel(id: 'pack_1', title: 'Passport / National ID', category: 'Documents'),
      PackingItemModel(id: 'pack_2', title: 'Phone charger & power bank', category: 'Tech'),
      PackingItemModel(id: 'pack_3', title: 'Comfortable walking shoes', category: 'Clothing'),
      PackingItemModel(id: 'pack_4', title: 'Weather-appropriate jacket', category: 'Clothing'),
      PackingItemModel(id: 'pack_5', title: 'Reusable water bottle', category: 'Essentials'),
      PackingItemModel(id: 'pack_6', title: 'Basic first-aid & medications', category: 'Health'),
    ];
  }
}
