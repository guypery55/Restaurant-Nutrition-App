/// A cached AI nutrition estimate for one dish (a row of `dish_estimates`,
/// returned by the `estimate-dishes` Edge Function).
///
/// Every figure is a low–high RANGE to express uncertainty (build-plan
/// principle #7). Numbers are stored once per dish for consistency, so the same
/// dish always reports the same values.
class DishEstimate {
  const DishEstimate({
    required this.dishId,
    required this.caloriesLow,
    required this.caloriesHigh,
    required this.proteinLow,
    required this.proteinHigh,
    required this.carbsLow,
    required this.carbsHigh,
    required this.sugarLow,
    required this.sugarHigh,
    required this.fatLow,
    required this.fatHigh,
    this.tags = const [],
    this.reasoning = '',
    this.model,
    this.cached = false,
  });

  final String dishId;
  final double caloriesLow;
  final double caloriesHigh;
  final double proteinLow;
  final double proteinHigh;
  final double carbsLow;
  final double carbsHigh;
  final double sugarLow;
  final double sugarHigh;
  final double fatLow;
  final double fatHigh;
  final List<String> tags;
  final String reasoning;
  final String? model;

  /// Whether the backend served this from cache (vs a fresh model call).
  final bool cached;

  factory DishEstimate.fromJson(Map<String, dynamic> json) {
    double n(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return DishEstimate(
      dishId: json['dish_id'] as String,
      caloriesLow: n('calories_low'),
      caloriesHigh: n('calories_high'),
      proteinLow: n('protein_low'),
      proteinHigh: n('protein_high'),
      carbsLow: n('carbs_low'),
      carbsHigh: n('carbs_high'),
      sugarLow: n('sugar_low'),
      sugarHigh: n('sugar_high'),
      fatLow: n('fat_low'),
      fatHigh: n('fat_high'),
      tags: (json['tags'] as List?)
              ?.whereType<String>()
              .where((t) => t.isNotEmpty)
              .toList() ??
          const [],
      reasoning: (json['reasoning'] as String?)?.trim() ?? '',
      model: json['model'] as String?,
      cached: json['cached'] == true,
    );
  }

  /// This estimate scaled by a portion factor (0.5×, 2×, …). Portion scaling is
  /// purely local arithmetic on the stored numbers — never a new model call
  /// (build-plan Session 6).
  DishEstimate scaled(double factor) {
    if (factor == 1) return this;
    return DishEstimate(
      dishId: dishId,
      caloriesLow: caloriesLow * factor,
      caloriesHigh: caloriesHigh * factor,
      proteinLow: proteinLow * factor,
      proteinHigh: proteinHigh * factor,
      carbsLow: carbsLow * factor,
      carbsHigh: carbsHigh * factor,
      sugarLow: sugarLow * factor,
      sugarHigh: sugarHigh * factor,
      fatLow: fatLow * factor,
      fatHigh: fatHigh * factor,
      tags: tags,
      reasoning: reasoning,
      model: model,
      cached: cached,
    );
  }
}
