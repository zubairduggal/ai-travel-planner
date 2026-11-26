/// High-level transport estimate and routing guidance returned by FastAPI
/// `TransportSummary` for the selected travel mode.
class TransportSummaryModel {
  const TransportSummaryModel({
    required this.mode,
    required this.estimatedCost,
    this.priceSource = 'ai_estimated',
    this.notes = '',
    this.routeTip = '',
  });

  final String mode;
  final double estimatedCost;
  final String priceSource;
  final String notes;
  final String routeTip;

  bool get isWebFound => priceSource == 'web_found';

  String get modeLabel {
    switch (mode.toLowerCase()) {
      case 'air':
        return 'By Air';
      case 'road':
        return 'By Road';
      case 'train':
        return 'Train';
      case 'bus':
        return 'Bus';
      case 'bike':
        return 'Bike';
      default:
        return mode.isEmpty ? 'Travel' : mode;
    }
  }

  factory TransportSummaryModel.fromJson(Map<String, dynamic> json) {
    return TransportSummaryModel(
      mode: json['mode'] as String? ?? 'air',
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble() ?? 0.0,
      priceSource: json['price_source'] as String? ?? 'ai_estimated',
      notes: json['notes'] as String? ?? '',
      routeTip: json['route_tip'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'estimated_cost': estimatedCost,
      'price_source': priceSource,
      'notes': notes,
      'route_tip': routeTip,
    };
  }

  TransportSummaryModel copyWith({
    String? mode,
    double? estimatedCost,
    String? priceSource,
    String? notes,
    String? routeTip,
  }) {
    return TransportSummaryModel(
      mode: mode ?? this.mode,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      priceSource: priceSource ?? this.priceSource,
      notes: notes ?? this.notes,
      routeTip: routeTip ?? this.routeTip,
    );
  }
}
