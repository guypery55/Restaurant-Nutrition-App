import '../models/restaurant.dart';
import 'supabase_service.dart';

/// Talks to the `resolve-restaurant` Edge Function. The Google Places key lives
/// only inside that function — this client never sees it (principle #1).
class RestaurantService {
  const RestaurantService._();

  static const _functionName = 'resolve-restaurant';

  /// Autocomplete: typed text → candidate restaurants to disambiguate by branch.
  /// [lat]/[lng] bias results toward the user when known.
  static Future<List<RestaurantCandidate>> autocomplete(
    String input, {
    double? lat,
    double? lng,
  }) async {
    final res = await SupabaseService.client.functions.invoke(
      _functionName,
      body: {
        'action': 'autocomplete',
        'input': input,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      },
    );
    final data = res.data as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Autocomplete failed');
    }
    final list = (data['candidates'] as List? ?? const []);
    return list
        .map((e) => RestaurantCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Select: resolve a chosen [placeId] to a stored canonical `restaurants` row
  /// (upserted server-side, deduped on place_id).
  static Future<Restaurant> select(String placeId) async {
    final res = await SupabaseService.client.functions.invoke(
      _functionName,
      body: {'action': 'select', 'placeId': placeId},
    );
    final data = res.data as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Select failed');
    }
    return Restaurant.fromJson(data['restaurant'] as Map<String, dynamic>);
  }
}
