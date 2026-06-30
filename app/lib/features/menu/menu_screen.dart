import 'package:flutter/material.dart';

import '../../models/dish.dart';
import '../../models/restaurant.dart';
import '../../services/menu_service.dart';
import '../assessment/assessment_screen.dart';

/// Menu display & assessment basket (Session 5).
///
/// Fetches a restaurant's stored menu via `fetch-menu`, renders it grouped by
/// section in Hebrew/RTL, and lets the user tap dishes into a local "basket".
/// A persistent "Check (N)" button carries the selection forward — but NOTHING
/// is estimated here. Estimation is on-demand and happens after Check (Session
/// 6/7); for seeded dishes it's already cached server-side.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late Future<MenuResult> _menuFuture;

  /// The basket: dish ids the user has selected. Kept alongside the dishes
  /// themselves so Check can hand the full objects to the assessment screen
  /// without re-fetching.
  final Map<String, Dish> _selected = {};

  @override
  void initState() {
    super.initState();
    _menuFuture = MenuService.fetchMenu(widget.restaurant.id);
  }

  void _reload() {
    setState(() {
      _menuFuture = MenuService.fetchMenu(widget.restaurant.id);
    });
  }

  void _toggle(Dish dish) {
    setState(() {
      if (_selected.containsKey(dish.id)) {
        _selected.remove(dish.id);
      } else {
        _selected[dish.id] = dish;
      }
    });
  }

  void _openCheck() {
    if (_selected.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssessmentScreen(
          restaurant: widget.restaurant,
          dishes: _selected.values.toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurant.name),
      ),
      body: FutureBuilder<MenuResult>(
        future: _menuFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _MenuLoading();
          }
          if (snapshot.hasError) {
            return _MenuError(onRetry: _reload);
          }
          final result = snapshot.data!;
          if (!result.found) {
            return const _NotCovered();
          }
          if (result.dishes.isEmpty) {
            return const _NotCovered();
          }
          return _MenuList(
            dishes: result.dishes,
            selectedIds: _selected.keys.toSet(),
            onTap: _toggle,
          );
        },
      ),
      bottomNavigationBar: _CheckBar(
        count: _selected.length,
        onPressed: _openCheck,
      ),
    );
  }
}

/// Groups dishes by section (preserving first-appearance order) and renders
/// each section with a header followed by its dishes.
class _MenuList extends StatelessWidget {
  const _MenuList({
    required this.dishes,
    required this.selectedIds,
    required this.onTap,
  });

  final List<Dish> dishes;
  final Set<String> selectedIds;
  final void Function(Dish) onTap;

  @override
  Widget build(BuildContext context) {
    // Preserve the order sections first appear in, rather than alphabetizing —
    // a menu's own ordering (starters → mains → dessert) is meaningful.
    final sections = <String, List<Dish>>{};
    for (final dish in dishes) {
      final key = (dish.section?.isNotEmpty ?? false) ? dish.section! : 'תפריט';
      sections.putIfAbsent(key, () => []).add(dish);
    }

    final entries = sections.entries.toList();
    return ListView.builder(
      // Leave room so the last items aren't hidden behind the Check bar.
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final section = entries[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: section.key),
            ...section.value.map(
              (dish) => _DishTile(
                dish: dish,
                selected: selectedIds.contains(dish.id),
                onTap: () => onTap(dish),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// Show a dish description only when it contains Hebrew. The catalog is
/// normalized to Hebrew, but a freshly live-fetched menu can still carry an
/// English description until the pipeline normalizer (v3 Session 10) translates
/// it — hide those rather than show English text under a Hebrew menu.
bool _showDescription(String? d) =>
    d != null && d.isNotEmpty && RegExp(r'[֐-׿]').hasMatch(d);

class _DishTile extends StatelessWidget {
  const _DishTile({
    required this.dish,
    required this.selected,
    required this.onTap,
  });

  final Dish dish;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = dish.price;
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: Icon(
        selected ? Icons.check_circle : Icons.add_circle_outline,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(dish.nameHe),
      subtitle: _showDescription(dish.description)
          ? Text(
              dish.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: price != null
          ? Text(
              '₪${_formatPrice(price)}',
              style: Theme.of(context).textTheme.titleSmall,
            )
          : null,
    );
  }

  String _formatPrice(double p) {
    // Drop a trailing ".0" so 52.0 shows as "52" but 52.5 stays "52.5".
    return p == p.roundToDouble() ? p.toInt().toString() : p.toString();
  }
}

class _CheckBar extends StatelessWidget {
  const _CheckBar({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: const Icon(Icons.science_outlined),
          label: Text(enabled ? 'בדיקה ($count)' : 'בדיקה'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ),
    );
  }
}

class _MenuLoading extends StatelessWidget {
  const _MenuLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('טוען תפריט…'),
        ],
      ),
    );
  }
}

class _MenuError extends StatelessWidget {
  const _MenuError({required this.onRetry});

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
              'טעינת התפריט נכשלה.',
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

/// The "we don't have this one yet" state — a miss must read as a gap in a
/// growing guide, never as breakage (build-plan framing).
class _NotCovered extends StatelessWidget {
  const _NotCovered();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu, size: 48),
            const SizedBox(height: 16),
            Text(
              'עדיין אין לנו את המסעדה הזו 🙏',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'הוספנו אותה לרשימה שלנו.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
