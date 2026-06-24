import 'package:flutter/material.dart';

import '../../models/dish.dart';
import '../../models/dish_estimate.dart';
import '../../models/macro_rating.dart';
import '../../models/restaurant.dart';
import '../../services/estimate_service.dart';

/// Assessment results (Session 6).
///
/// On open, estimates every selected dish via `estimate-dishes` (cached
/// server-side for consistency), then shows a per-dish nutrition range plus a
/// combined total. Each dish has a local portion selector (½× / 1× / 2×) that
/// rescales its stored numbers with no new model call. Estimates are AI ranges,
/// explicitly not medical advice (persistent disclaimer below).
class AssessmentScreen extends StatefulWidget {
  const AssessmentScreen({
    super.key,
    required this.restaurant,
    required this.dishes,
  });

  final Restaurant restaurant;
  final List<Dish> dishes;

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  late Future<Map<String, DishEstimate>> _future;

  /// Per-dish portion multiplier (defaults to 1×). Purely local — never sent to
  /// the model; we just rescale the stored estimate.
  final Map<String, double> _portions = {};

  /// View mode: false = show low–high ranges (default), true = "precise" mode,
  /// collapsing each range to its midpoint average. Display-only; the underlying
  /// estimate is untouched.
  bool _precise = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = EstimateService.estimate(
      widget.dishes.map((d) => d.id).toList(),
    );
  }

  void _reload() => setState(_load);

  void _setPortion(String dishId, double factor) {
    setState(() => _portions[dishId] = factor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('הערכה תזונתית')),
      body: FutureBuilder<Map<String, DishEstimate>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _EstimateLoading();
          }
          if (snapshot.hasError) {
            return _EstimateError(onRetry: _reload);
          }
          return _Results(
            dishes: widget.dishes,
            estimates: snapshot.data ?? const {},
            portions: _portions,
            onPortion: _setPortion,
            precise: _precise,
            onPreciseChanged: (v) => setState(() => _precise = v),
          );
        },
      ),
      bottomNavigationBar: const _Disclaimer(),
    );
  }
}

/// The scrollable results: a combined-total summary on top, then a card per
/// selected dish. Combined totals recompute on every build, so portion changes
/// flow straight through.
class _Results extends StatelessWidget {
  const _Results({
    required this.dishes,
    required this.estimates,
    required this.portions,
    required this.onPortion,
    required this.precise,
    required this.onPreciseChanged,
  });

  final List<Dish> dishes;
  final Map<String, DishEstimate> estimates;
  final Map<String, double> portions;
  final void Function(String dishId, double factor) onPortion;
  final bool precise;
  final void Function(bool precise) onPreciseChanged;

  double _portion(String dishId) => portions[dishId] ?? 1;

  @override
  Widget build(BuildContext context) {
    // Combined total = sum of each dish's (portion-scaled) range.
    final scaled = <DishEstimate>[];
    for (final dish in dishes) {
      final est = estimates[dish.id];
      if (est != null) scaled.add(est.scaled(_portion(dish.id)));
    }

    return Column(
      children: [
        _ViewModeToggle(precise: precise, onChanged: onPreciseChanged),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              if (scaled.isNotEmpty)
                _CombinedCard(estimates: scaled, precise: precise),
              for (final dish in dishes)
                _DishCard(
                  dish: dish,
                  estimate: estimates[dish.id],
                  portion: _portion(dish.id),
                  onPortion: (f) => onPortion(dish.id, f),
                  precise: precise,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pinned טווח / מדויק (Range / Precise) view switch. In precise mode every
/// low–high figure collapses to its midpoint average. Display-only.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.precise, required this.onChanged});

  final bool precise;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('טווח'),
                icon: Icon(Icons.unfold_more),
              ),
              ButtonSegment(
                value: true,
                label: Text('מדויק'),
                icon: Icon(Icons.center_focus_strong),
              ),
            ],
            selected: {precise},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ),
      ),
    );
  }
}

/// Combined total across all selected dishes (summed ranges).
class _CombinedCard extends StatelessWidget {
  const _CombinedCard({required this.estimates, required this.precise});

  final List<DishEstimate> estimates;
  final bool precise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double sum(double Function(DishEstimate) f) =>
        estimates.fold(0.0, (a, e) => a + f(e));

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'סך הכול',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${estimates.length} מנות',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
            ),
            const SizedBox(height: 12),
            _CaloriesLine(
              low: sum((e) => e.caloriesLow),
              high: sum((e) => e.caloriesHigh),
              color: scheme.onPrimaryContainer,
              precise: precise,
            ),
            const SizedBox(height: 12),
            _MacroGrid(
              proteinLow: sum((e) => e.proteinLow),
              proteinHigh: sum((e) => e.proteinHigh),
              carbsLow: sum((e) => e.carbsLow),
              carbsHigh: sum((e) => e.carbsHigh),
              sugarLow: sum((e) => e.sugarLow),
              sugarHigh: sum((e) => e.sugarHigh),
              fatLow: sum((e) => e.fatLow),
              fatHigh: sum((e) => e.fatHigh),
              color: scheme.onPrimaryContainer,
              precise: precise,
            ),
          ],
        ),
      ),
    );
  }
}

/// One dish's estimate card: name, calorie range, macros, tags, reasoning, and
/// the portion selector. Falls back to a calm "estimate unavailable" line when
/// the backend couldn't estimate this dish (never garbage).
class _DishCard extends StatelessWidget {
  const _DishCard({
    required this.dish,
    required this.estimate,
    required this.portion,
    required this.onPortion,
    required this.precise,
  });

  final Dish dish;
  final DishEstimate? estimate;
  final double portion;
  final void Function(double factor) onPortion;
  final bool precise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final est = estimate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              dish.nameHe,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (est == null) ...[
              const SizedBox(height: 12),
              Text(
                'לא הצלחנו להעריך את המנה הזו.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              _PortionSelector(value: portion, onChanged: onPortion),
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final scaled = est.scaled(portion);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CaloriesLine(
                      low: scaled.caloriesLow,
                      high: scaled.caloriesHigh,
                      color: scheme.onSurface,
                      precise: precise,
                    ),
                    const SizedBox(height: 12),
                    _MacroGrid(
                      proteinLow: scaled.proteinLow,
                      proteinHigh: scaled.proteinHigh,
                      carbsLow: scaled.carbsLow,
                      carbsHigh: scaled.carbsHigh,
                      sugarLow: scaled.sugarLow,
                      sugarHigh: scaled.sugarHigh,
                      fatLow: scaled.fatLow,
                      fatHigh: scaled.fatHigh,
                      color: scheme.onSurface,
                      precise: precise,
                    ),
                  ],
                );
              }),
              Builder(builder: (context) {
                // Show ONLY positive highlights: for a dessert, "low in
                // sugar"/"low in fat" when it genuinely is; otherwise (mains,
                // starters, …) "rich in protein" when it genuinely is. Nothing
                // is shown when there's nothing good to say — no warnings, no
                // shaming (build-plan neutral framing).
                final highlights = _positiveHighlights(dish, est);
                if (highlights.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final label in highlights) _PositiveChip(label: label),
                    ],
                  ),
                );
              }),
              if (est.reasoning.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  est.reasoning,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Calorie range — the headline figure of each card.
class _CaloriesLine extends StatelessWidget {
  const _CaloriesLine({
    required this.low,
    required this.high,
    required this.color,
    required this.precise,
  });

  final double low;
  final double high;
  final Color color;
  final bool precise;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _formatRange(low, high, precise: precise),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 6),
        Text(
          'קלוריות',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// The four macros in a simple two-column grid.
class _MacroGrid extends StatelessWidget {
  const _MacroGrid({
    required this.proteinLow,
    required this.proteinHigh,
    required this.carbsLow,
    required this.carbsHigh,
    required this.sugarLow,
    required this.sugarHigh,
    required this.fatLow,
    required this.fatHigh,
    required this.color,
    required this.precise,
  });

  final double proteinLow, proteinHigh;
  final double carbsLow, carbsHigh;
  final double sugarLow, sugarHigh;
  final double fatLow, fatHigh;
  final Color color;
  final bool precise;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, double low, double high) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color),
            ),
            Text(
              '${_formatRange(low, high, precise: precise)} ג׳',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        cell('חלבון', proteinLow, proteinHigh),
        cell('פחמימות', carbsLow, carbsHigh),
        cell('מתוכן סוכר', sugarLow, sugarHigh),
        cell('שומן', fatLow, fatHigh),
      ],
    );
  }
}

/// ½× / 1× / 2× portion picker. Local-only: rescales the stored estimate.
class _PortionSelector extends StatelessWidget {
  const _PortionSelector({required this.value, required this.onChanged});

  final double value;
  final void Function(double) onChanged;

  // (factor, label) pairs — a list, not a map, since const maps can't key on double.
  static const _options = <(double, String)>[
    (0.5, '½'),
    (1.0, '1'),
    (2.0, '2'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'מנה:',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(width: 8),
        ..._options.map((e) {
          final (factor, label) = e;
          final selected = value == factor;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ChoiceChip(
              label: Text('$label×'),
              selected: selected,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(factor),
            ),
          );
        }),
      ],
    );
  }
}

/// The good things worth surfacing for a dish, as ready-to-show Hebrew labels.
///
/// Ratings come from the macro shares of the dish's (range-midpoint) calories —
/// share is portion-independent, so these don't change with the ½×/2× selector.
/// Desserts surface "low in sugar"/"low in fat"; everything else (mains,
/// starters) surfaces "rich in protein". Only genuine positives are returned.
List<String> _positiveHighlights(Dish dish, DishEstimate est) {
  double mid(double low, double high) => (low + high) / 2;
  final rating = rateMacros(
    calories: mid(est.caloriesLow, est.caloriesHigh),
    protein: mid(est.proteinLow, est.proteinHigh),
    carbs: mid(est.carbsLow, est.carbsHigh),
    sugars: mid(est.sugarLow, est.sugarHigh),
    fat: mid(est.fatLow, est.fatHigh),
  );

  final out = <String>[];
  if (_isDessert(dish, est)) {
    if (rating.sugars.isPositive) out.add('דל בסוכר');
    if (rating.fat.isPositive) out.add('דל בשומן');
  } else {
    if (rating.protein.isPositive) out.add('עשיר בחלבון');
  }
  return out;
}

/// Whether to treat a dish as a dessert (drives which positives we look for).
/// Uses the menu section first, then falls back to the estimate's tags.
bool _isDessert(Dish dish, DishEstimate est) {
  const sectionHints = ['קינוח', 'דזרט', 'dessert', 'sweet'];
  final section = (dish.section ?? '').toLowerCase();
  if (sectionHints.any(section.contains)) return true;
  final tags = est.tags.map((t) => t.toLowerCase());
  return tags.contains('dessert') || tags.contains('sweet');
}

/// A calm green "good thing" chip. Positives only — there is no warning variant
/// by design (neutral, non-shaming framing).
class _PositiveChip extends StatelessWidget {
  const _PositiveChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3B7A57); // the app's seed green
    return Chip(
      avatar: const Icon(Icons.eco, size: 18, color: green),
      label: Text(label),
      labelStyle: const TextStyle(color: green, fontWeight: FontWeight.w600),
      backgroundColor: green.withValues(alpha: 0.10),
      side: BorderSide(color: green.withValues(alpha: 0.35)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Format a low–high range as "120–180", collapsing to a single number when
/// equal. In [precise] mode, show the midpoint average as one number instead.
/// Values keep one decimal when not whole, else round to integers.
String _formatRange(double low, double high, {bool precise = false}) {
  String fmt(double v) {
    final rounded = double.parse(v.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  if (precise) return fmt((low + high) / 2);

  final lo = fmt(low);
  final hi = fmt(high);
  return lo == hi ? lo : '$lo–$hi';
}

class _EstimateLoading extends StatelessWidget {
  const _EstimateLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('מעריכים את הערכים התזונתיים…'),
        ],
      ),
    );
  }
}

class _EstimateError extends StatelessWidget {
  const _EstimateError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 16),
            const Text(
              'ההערכה נכשלה.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('נסו שוב'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent "AI estimate — not medical advice" disclaimer (build-plan
/// principle #7). Always visible at the foot of the results.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      child: SafeArea(
        top: false,
        child: Text(
          'הערכת בינה מלאכותית — אינה ייעוץ רפואי.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
