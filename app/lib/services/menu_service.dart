import '../models/dish.dart';
import 'supabase_service.dart';

/// Outcome of a menu fetch. Exactly one of three states:
///
/// - [found]: [dishes] is populated.
/// - [pending]: the live fetch was taking too long, so it was handed to the
///   background acquisition queue (Session 9). The menu isn't ready yet — the
///   screen shows "we're working on it" and auto-polls until it lands.
/// - neither: not covered (then [reason] explains why — the "not covered yet" UI).
class MenuResult {
  const MenuResult.found({
    required this.dishes,
    this.source,
    this.scraper,
    this.sourceUrl,
    this.verified = false,
  })  : found = true,
        pending = false,
        reason = null;

  const MenuResult.pending()
      : found = false,
        pending = true,
        dishes = const [],
        source = null,
        scraper = null,
        sourceUrl = null,
        verified = false,
        reason = null;

  const MenuResult.notCovered({this.reason})
      : found = false,
        pending = false,
        dishes = const [],
        source = null,
        scraper = null,
        sourceUrl = null,
        verified = false;

  final bool found;

  /// Being acquired in the background right now (the live fetch exceeded its
  /// budget). Not an error and not a miss — just "check back in a moment".
  final bool pending;

  final List<Dish> dishes;
  final String? source;
  final String? scraper;
  final String? sourceUrl;

  /// Whether this menu has been human-verified against its source
  /// (`menus.verified`). Drives the verified badge; nothing sets it true until
  /// Session 11's verification flow, so today it's always false.
  final bool verified;

  /// 'no_website' | 'platform_only' | 'no_menu_found' | 'timeout' — only when
  /// [found] is false and not [pending].
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
    if (data['pending'] == true) {
      return const MenuResult.pending();
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
      verified: data['verified'] == true,
    );
  }
}
