/// A restaurant candidate returned by Places Autocomplete (not yet stored).
/// The user picks one of these to disambiguate the branch.
class RestaurantCandidate {
  const RestaurantCandidate({
    required this.placeId,
    required this.name,
    required this.address,
    required this.fullText,
  });

  final String placeId;
  final String name;
  final String address;
  final String fullText;

  factory RestaurantCandidate.fromJson(Map<String, dynamic> json) {
    return RestaurantCandidate(
      placeId: json['placeId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      fullText: json['fullText'] as String? ?? '',
    );
  }
}

/// A canonical restaurant row stored in Supabase (keyed by Google `place_id`).
class Restaurant {
  const Restaurant({
    required this.id,
    required this.placeId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.website,
  });

  final String id;
  final String placeId;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;

  /// Official website from Google Places — Session 3's primary menu source.
  final String? website;

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id'] as String,
      placeId: json['place_id'] as String,
      name: json['name'] as String? ?? '',
      address: json['address'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      website: json['website'] as String?,
    );
  }
}
