/// Comparable real-world hotel or dining option returned by FastAPI
/// `PlaceOption` with honest price provenance and verified GPS metadata.
class PlaceOptionModel {
  const PlaceOptionModel({
    required this.optionId,
    required this.name,
    this.tier = 'mid_range',
    required this.estimatedPrice,
    required this.totalEstimatedCost,
    this.priceSource = 'ai_estimated',
    this.priceNote = '',
    this.latitude,
    this.longitude,
    this.verified = false,
    this.distanceToCenterKm,
    this.highlights = const [],
    this.selected = false,
  });

  final String optionId;
  final String name;
  final String tier;
  final double estimatedPrice;
  final double totalEstimatedCost;
  final String priceSource;
  final String priceNote;
  final double? latitude;
  final double? longitude;
  final bool verified;
  final double? distanceToCenterKm;
  final List<String> highlights;
  final bool selected;

  bool get hasCoordinates => latitude != null && longitude != null;
  bool get isWebFound => priceSource == 'web_found';

  String get tierLabel {
    switch (tier.toLowerCase()) {
      case 'budget':
        return 'Budget';
      case 'comfort':
        return 'Comfort';
      case 'mid_range':
      default:
        return 'Mid-Range';
    }
  }

  factory PlaceOptionModel.fromJson(Map<String, dynamic> json) {
    final rawHighlights = json['highlights'] as List<dynamic>? ?? const [];
    final price = (json['estimated_price'] as num?)?.toDouble() ?? 0.0;
    final total = (json['total_estimated_cost'] as num?)?.toDouble() ?? price;
    return PlaceOptionModel(
      optionId: json['option_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      tier: json['tier'] as String? ?? 'mid_range',
      estimatedPrice: price,
      totalEstimatedCost: total,
      priceSource: json['price_source'] as String? ?? 'ai_estimated',
      priceNote: json['price_note'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      verified: json['verified'] as bool? ?? false,
      distanceToCenterKm: (json['distance_to_center_km'] as num?)?.toDouble(),
      highlights: rawHighlights
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      selected: json['selected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'option_id': optionId,
      'name': name,
      'tier': tier,
      'estimated_price': estimatedPrice,
      'total_estimated_cost': totalEstimatedCost,
      'price_source': priceSource,
      'price_note': priceNote,
      'latitude': latitude,
      'longitude': longitude,
      'verified': verified,
      'distance_to_center_km': distanceToCenterKm,
      'highlights': highlights,
      'selected': selected,
    };
  }

  PlaceOptionModel copyWith({
    String? optionId,
    String? name,
    String? tier,
    double? estimatedPrice,
    double? totalEstimatedCost,
    String? priceSource,
    String? priceNote,
    double? latitude,
    double? longitude,
    bool? verified,
    double? distanceToCenterKm,
    List<String>? highlights,
    bool? selected,
  }) {
    return PlaceOptionModel(
      optionId: optionId ?? this.optionId,
      name: name ?? this.name,
      tier: tier ?? this.tier,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      totalEstimatedCost: totalEstimatedCost ?? this.totalEstimatedCost,
      priceSource: priceSource ?? this.priceSource,
      priceNote: priceNote ?? this.priceNote,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      verified: verified ?? this.verified,
      distanceToCenterKm: distanceToCenterKm ?? this.distanceToCenterKm,
      highlights: highlights ?? this.highlights,
      selected: selected ?? this.selected,
    );
  }
}
