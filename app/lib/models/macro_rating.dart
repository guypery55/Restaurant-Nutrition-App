// Macro-rating logic — rates each macro by its share of total CALORIES.
//
// We deliberately do NOT use or require the meal's total weight; a macro's
// rating is its contribution to the dish's calories, computed from grams and a
// per-gram calorie factor. Pure Dart (no Flutter import) so it's unit-testable
// in isolation — see `test/macro_rating_test.dart`.

/// Where a macro's calorie-share lands relative to its thresholds.
enum MacroLevel { low, moderate, high }

/// Whether a higher share is good, bad, or neither — lets the UI flag a rating
/// as a positive (good) or a warning appropriately.
enum MacroDirection { higherBetter, lowerBetter, neutral }

// Energy density per gram for the macros we rate.
const int _kcalPerGramProtein = 4;
const int _kcalPerGramCarbs = 4;
const int _kcalPerGramSugars = 4;
const int _kcalPerGramFat = 9;

/// One macro's rating: its [level], the calorie-share [percentOfCalories] it was
/// derived from, and which [direction] counts as "good".
class MacroRating {
  const MacroRating({
    required this.level,
    required this.direction,
    required this.percentOfCalories,
  });

  final MacroLevel level;
  final MacroDirection direction;
  final double percentOfCalories;

  /// True when this rating is a clearly good thing to surface: a high share of
  /// a higher-better macro (e.g. protein), or a low share of a lower-better one
  /// (e.g. sugar, fat). Neutral macros are never "positive".
  bool get isPositive =>
      (direction == MacroDirection.higherBetter && level == MacroLevel.high) ||
      (direction == MacroDirection.lowerBetter && level == MacroLevel.low);
}

/// The four macro ratings for a single dish / meal.
class MealRating {
  const MealRating({
    required this.protein,
    required this.carbs,
    required this.sugars,
    required this.fat,
  });

  final MacroRating protein;
  final MacroRating carbs;
  final MacroRating sugars;
  final MacroRating fat;
}

/// Rate each macro by its share of total CALORIES (never by weight):
///
///   pct = grams * kcalPerGram / calories * 100
///
/// Thresholds (percent of total calories):
/// - protein: high ≥20, moderate ≥12, else low   (higher is better)
/// - carbs:   high ≥65, moderate ≥45, else low    (neutral)
/// - sugars:  high ≥10, moderate ≥5,  else low     (lower is better)
/// - fat:     high ≥35, moderate ≥20, else low     (lower is better)
///
/// When [calories] is zero or negative the share is undefined, so we guard
/// against divide-by-zero and report 0% / low for every macro instead of
/// throwing.
MealRating rateMacros({
  required num calories,
  required num protein,
  required num carbs,
  required num sugars,
  required num fat,
}) {
  double pct(num grams, int kcalPerGram) {
    if (calories <= 0) return 0; // divide-by-zero guard
    return grams * kcalPerGram / calories * 100;
  }

  return MealRating(
    protein: _rate(
      pct(protein, _kcalPerGramProtein),
      high: 20,
      moderate: 12,
      direction: MacroDirection.higherBetter,
    ),
    carbs: _rate(
      pct(carbs, _kcalPerGramCarbs),
      high: 65,
      moderate: 45,
      direction: MacroDirection.neutral,
    ),
    sugars: _rate(
      pct(sugars, _kcalPerGramSugars),
      high: 10,
      moderate: 5,
      direction: MacroDirection.lowerBetter,
    ),
    fat: _rate(
      pct(fat, _kcalPerGramFat),
      high: 35,
      moderate: 20,
      direction: MacroDirection.lowerBetter,
    ),
  );
}

/// Classify a single [pct] against its [high]/[moderate] thresholds (inclusive
/// lower bounds, matching the spec's `>=`).
MacroRating _rate(
  double pct, {
  required double high,
  required double moderate,
  required MacroDirection direction,
}) {
  final MacroLevel level;
  if (pct >= high) {
    level = MacroLevel.high;
  } else if (pct >= moderate) {
    level = MacroLevel.moderate;
  } else {
    level = MacroLevel.low;
  }
  return MacroRating(
    level: level,
    direction: direction,
    percentOfCalories: pct,
  );
}
