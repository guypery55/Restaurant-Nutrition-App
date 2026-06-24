import '../models/dish_estimate.dart';
import 'supabase_service.dart';

/// Talks to the `estimate-dishes` Edge Function. That function holds the cache:
/// for each dish id it reuses a stored estimate (numbers never wobble) or calls
/// the Haiku estimator once and stores the result. The client just hands it the
/// selected dish ids and renders the ranges that come back.
class EstimateService {
  const EstimateService._();

  static const _functionName = 'estimate-dishes';

  /// Estimate the given dishes. Returns a map keyed by `dish_id` so callers can
  /// line estimates up with their dishes regardless of order. Ids the backend
  /// couldn't estimate are simply absent from the map.
  static Future<Map<String, DishEstimate>> estimate(
    List<String> dishIds,
  ) async {
    if (dishIds.isEmpty) return const {};

    final res = await SupabaseService.client.functions.invoke(
      _functionName,
      body: {'dish_ids': dishIds},
    );
    final data = res.data as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'Estimation failed');
    }
    final list = (data['estimates'] as List? ?? const []);
    final out = <String, DishEstimate>{};
    for (final e in list) {
      final est = DishEstimate.fromJson(e as Map<String, dynamic>);
      out[est.dishId] = est;
    }
    return out;
  }
}
