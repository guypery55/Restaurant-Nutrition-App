import '../models/dish.dart';
import 'supabase_service.dart';

/// Outcome of a menu fetch.
///
/// Either we [found] a menu (then [dishes] is populated) or we didn't (then
/// [reason] explains why — driving the "not covered yet" UI in Session 7).
class MenuResult {
  const MenuResult.found({
    required this.dishes,
    this.source,
    this.scraper,
    this.sourceUrl,
  })  : found = true,
        reason = null;

  const MenuResult.notCovered({this.reason})
      : found = false,
        dishes = const [],
        source = null,
        scraper = null,
        sourceUrl = null;

  final bool found;
  final List<Dish> dishes;
  final String? source;
  final String? scraper;
  final String? sourceUrl;

  /// 'no_website' | 'platform_only' | 'no_menu_found' | 'timeout' — only when
  /// [found] is false.
  final String? reason;
}

/// Talks to the `fetch-menu` Edge Function. That function handles the cache,
/// the inline scrape/parse on a miss, and the "not covered yet" fallback — the
/// client just asks for a restaurant's menu and renders whatever comes back.
class MenuService {
  const MenuService._();

  static const _functionName = 'fetch-menu';

  /// Fetch the stored (or freshly acquired) menu for a resolved restaurant.
  static Future<MenuResult> fetchMenu(String restaurantId) async {
    final res = await SupabaseService.client.functions.invoke(
      _functionName,
      body: {'restaurant_id': restaurantId},
    );
    final data = res.data as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Menu fetch failed');
    }
    if (data['found'] != true) {
      return MenuResult.notCovered(reason: data['reason'] as String?);
    }
    final list = (data['dishes'] as List? ?? const []);
    final dishes = list
        .map((e) => Dish.fromJson(e as Map<String, dynamic>))
        .where((d) => d.nameHe.isNotEmpty)
        .toList();
    return MenuResult.found(
      dishes: dishes,
      source: data['source'] as String?,
      scraper: data['scraper'] as String?,
      sourceUrl: data['source_url'] as String?,
    );
  }
}
