/// Элемент списка покупок (название и опциональная подгруппа).
class ShoppingItem {
  final String name;
  final String? group;

  const ShoppingItem({required this.name, this.group});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (group != null && group!.isNotEmpty) 'group': group,
      };

  static ShoppingItem fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      name: json['name'] as String? ?? '',
      group: json['group'] as String?,
    );
  }
}
