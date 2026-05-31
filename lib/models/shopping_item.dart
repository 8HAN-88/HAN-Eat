/// Элемент списка покупок (название, количество, группа, отметка «куплено»).
class ShoppingItem {
  final String name;
  final String? quantity;
  final String? group;
  final bool purchased;

  const ShoppingItem({
    required this.name,
    this.quantity,
    this.group,
    this.purchased = false,
  });

  ShoppingItem copyWith({bool? purchased, String? quantity}) {
    return ShoppingItem(
      name: name,
      quantity: quantity ?? this.quantity,
      group: group,
      purchased: purchased ?? this.purchased,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (quantity != null && quantity!.isNotEmpty) 'quantity': quantity,
        if (group != null && group!.isNotEmpty) 'group': group,
        'purchased': purchased,
      };

  static ShoppingItem fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] as String?,
      group: json['group'] as String?,
      purchased: json['purchased'] as bool? ?? false,
    );
  }

  bool sameIdentityAs(ShoppingItem other) =>
      name == other.name &&
      group == other.group &&
      quantity == other.quantity;
}
