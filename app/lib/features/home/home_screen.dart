import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/restaurant.dart';
import '../menu/menu_screen.dart';
import '../search/search_screen.dart';

/// Home / landing screen.
///
/// The warm entry point to the loop: a short welcome and the search as the hero
/// action (search → menu → assess). After a restaurant is resolved it stays
/// pinned as a "last viewed" card so it's one tap to return to its menu.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Restaurant? _resolved;

  Future<void> _openSearch() async {
    final restaurant = await Navigator.of(context).push<Restaurant>(
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
    if (restaurant == null || !mounted) return;
    setState(() => _resolved = restaurant);
    // search → menu: go straight into the selected restaurant's menu.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MenuScreen(restaurant: restaurant)),
    );
  }

  void _openResolved() {
    final r = _resolved;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MenuScreen(restaurant: r)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configured = AppConfig.isConfigured;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('הערכת תזונה במסעדות')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.restaurant_menu,
                size: 72,
                color: scheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'מה אוכלים?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'חפשו מסעדה, בחרו מנות, וקבלו הערכת תזונה מבוססת בינה מלאכותית — '
                'קלוריות ומרכיבים, לכל מנה ובסך הכול.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: configured ? _openSearch : null,
                icon: const Icon(Icons.search),
                label: const Text('חיפוש מסעדה'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              if (!configured) ...[
                const SizedBox(height: 12),
                Text(
                  'החיבור לשרת אינו מוגדר.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                ),
              ],
              if (_resolved != null) ...[
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(Icons.history, color: scheme.primary),
                    title: Text(_resolved!.name),
                    subtitle: (_resolved!.address?.isNotEmpty ?? false)
                        ? Text(
                            _resolved!.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: const Icon(Icons.chevron_left),
                    onTap: _openResolved,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                'הערכת בינה מלאכותית — אינה ייעוץ רפואי.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
