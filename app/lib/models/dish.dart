/// A dish parsed from a stored menu (a row of the `dishes` table).
///
/// Estimation is intentionally NOT part of this model — nutrition is fetched
/// on demand in Session 6, keyed by [id].
class Dish {
  const Dish({
    required this.id,
    required this.nameHe,
    this.nameTranslit,
    this.description,
    this.section,
    this.price,
  });

  final String id;
  final String nameHe;
  final String? nameTranslit;
  final String? description;
  final String? section;
  final double? price;

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      id: json['id'] as String,
      nameHe: (json['name_he'] as String?)?.trim() ?? '',
      nameTranslit: (json['name_translit'] as String?)?.trim(),
      description: (json['description'] as String?)?.trim(),
      section: (json['section'] as String?)?.trim(),
      price: (json['price'] as num?)?.toDouble(),
    );
  }
}
