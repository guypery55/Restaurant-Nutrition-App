// Unit tests for the calorie-share macro rating (lib/models/macro_rating.dart).
//
// Inputs are chosen so the percentages come out to exact, readable values:
// - 4 kcal/g macros with calories = 100  -> pct == grams * 4
// - fat (9 kcal/g)        with calories = 900 -> pct == grams
// Other macros are zeroed so each test isolates one macro.

import 'package:flutter_test/flutter_test.dart';
import 'package:restaurant_nutrition_app/models/macro_rating.dart';

void main() {
  group('rateMacros — percentage maths', () {
    test('pct = grams * kcalPerGram / calories * 100', () {
      // protein 5 g, 100 kcal -> 5 * 4 / 100 * 100 = 20%
      final r = rateMacros(
        calories: 100,
        protein: 5,
        carbs: 0,
        sugars: 0,
        fat: 0,
      );
      expect(r.protein.percentOfCalories, closeTo(20, 1e-9));
    });

    test('fat uses 9 kcal/g', () {
      // fat 35 g, 900 kcal -> 35 * 9 / 900 * 100 = 35%
      final r = rateMacros(
        calories: 900,
        protein: 0,
        carbs: 0,
        sugars: 0,
        fat: 35,
      );
      expect(r.fat.percentOfCalories, closeTo(35, 1e-9));
    });
  });

  group('protein thresholds (higher is better)', () {
    MacroRating rate(num grams) => rateMacros(
          calories: 100,
          protein: grams,
          carbs: 0,
          sugars: 0,
          fat: 0,
        ).protein;

    test('exactly 20% is high (boundary, inclusive)', () {
      expect(rate(5).level, MacroLevel.high); // 20%
    });
    test('just below 20% is moderate', () {
      expect(rate(4.99).level, MacroLevel.moderate); // 19.96%
    });
    test('exactly 12% is moderate (boundary, inclusive)', () {
      expect(rate(3).level, MacroLevel.moderate); // 12%
    });
    test('just below 12% is low', () {
      expect(rate(2.99).level, MacroLevel.low); // 11.96%
    });
    test('direction is higherBetter', () {
      expect(rate(5).direction, MacroDirection.higherBetter);
    });
  });

  group('carbs thresholds (neutral)', () {
    MacroRating rate(num grams) => rateMacros(
          calories: 100,
          protein: 0,
          carbs: grams,
          sugars: 0,
          fat: 0,
        ).carbs;

    test('exactly 65% is high', () {
      expect(rate(16.25).level, MacroLevel.high); // 65%
    });
    test('exactly 45% is moderate', () {
      expect(rate(11.25).level, MacroLevel.moderate); // 45%
    });
    test('below 45% is low', () {
      expect(rate(10).level, MacroLevel.low); // 40%
    });
    test('direction is neutral', () {
      expect(rate(16.25).direction, MacroDirection.neutral);
    });
  });

  group('sugar thresholds (lower is better)', () {
    MacroRating rate(num grams) => rateMacros(
          calories: 100,
          protein: 0,
          carbs: 0,
          sugars: grams,
          fat: 0,
        ).sugars;

    test('exactly 10% is high (boundary, inclusive)', () {
      expect(rate(2.5).level, MacroLevel.high); // 10%
    });
    test('exactly 5% is moderate (boundary, inclusive)', () {
      expect(rate(1.25).level, MacroLevel.moderate); // 5%
    });
    test('just below 5% is low', () {
      expect(rate(1.24).level, MacroLevel.low); // 4.96%
    });
    test('direction is lowerBetter', () {
      expect(rate(1).direction, MacroDirection.lowerBetter);
    });
  });

  group('fat thresholds (lower is better)', () {
    MacroRating rate(num grams) => rateMacros(
          calories: 900,
          protein: 0,
          carbs: 0,
          sugars: 0,
          fat: grams,
        ).fat;

    test('exactly 35% is high', () {
      expect(rate(35).level, MacroLevel.high); // 35%
    });
    test('exactly 20% is moderate', () {
      expect(rate(20).level, MacroLevel.moderate); // 20%
    });
    test('below 20% is low', () {
      expect(rate(19).level, MacroLevel.low); // 19%
    });
    test('direction is lowerBetter', () {
      expect(rate(35).direction, MacroDirection.lowerBetter);
    });
  });

  group('divide-by-zero guard', () {
    test('calories = 0 does not throw and rates everything low at 0%', () {
      late MealRating r;
      expect(
        () => r = rateMacros(
          calories: 0,
          protein: 10,
          carbs: 10,
          sugars: 10,
          fat: 10,
        ),
        returnsNormally,
      );
      for (final m in [r.protein, r.carbs, r.sugars, r.fat]) {
        expect(m.percentOfCalories, 0);
        expect(m.level, MacroLevel.low);
      }
    });

    test('negative calories is guarded the same way', () {
      final r = rateMacros(
        calories: -100,
        protein: 10,
        carbs: 10,
        sugars: 10,
        fat: 10,
      );
      expect(r.protein.percentOfCalories, 0);
      expect(r.protein.level, MacroLevel.low);
    });
  });

  group('isPositive', () {
    test('high protein (higherBetter) is positive', () {
      final r = rateMacros(calories: 100, protein: 5, carbs: 0, sugars: 0, fat: 0);
      expect(r.protein.isPositive, isTrue);
    });
    test('low sugar (lowerBetter) is positive', () {
      final r = rateMacros(calories: 100, protein: 0, carbs: 0, sugars: 1, fat: 0);
      expect(r.sugars.isPositive, isTrue); // 4% -> low
    });
    test('low fat (lowerBetter) is positive', () {
      final r = rateMacros(calories: 900, protein: 0, carbs: 0, sugars: 0, fat: 10);
      expect(r.fat.isPositive, isTrue); // ~11% -> low
    });
    test('high sugar is NOT positive', () {
      final r = rateMacros(calories: 100, protein: 0, carbs: 0, sugars: 2.5, fat: 0);
      expect(r.sugars.isPositive, isFalse); // 10% -> high
    });
    test('high carbs (neutral) is never positive', () {
      final r = rateMacros(calories: 100, protein: 0, carbs: 16.25, sugars: 0, fat: 0);
      expect(r.carbs.isPositive, isFalse); // 65% high, but neutral
    });
  });
}
