import '../core/utils/formatters.dart';
import 'day_plan_model.dart';

/// Outgoing request payload for `POST /api/v1/itinerary/generate`.
class TripRequestModel {
  const TripRequestModel({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.budget,
    required this.currency,
    required this.interests,
    required this.travelStyle,
  });

  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final double budget;
  final String currency;
  final List<String> interests;
  final String travelStyle;

  /// Inclusive trip length calculated in UTC to avoid DST off-by-one bugs.
  int get durationDays {
    final startUtc = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final endUtc = DateTime.utc(endDate.year, endDate.month, endDate.day);
    return endUtc.difference(startUtc).inDays + 1;
  }

  Map<String, dynamic> toJson() {
    return {
      'destination': destination.trim(),
      'start_date': AppFormatters.toIsoDate(startDate),
      'end_date': AppFormatters.toIsoDate(endDate),
      'budget': budget,
      'currency': currency.toUpperCase(),
      'interests': interests,
      'travel_style': travelStyle,
    };
  }
}

/// Complete itinerary returned by FastAPI `TripItineraryResponseSchema`
/// plus optional client metadata (startDate, targetBudget, travelStyle, interests)
/// for offline viewing, budget tracking, and slot regeneration.
class TripModel {
  const TripModel({
    required this.tripId,
    required this.destination,
    required this.durationDays,
    required this.totalEstimatedCost,
    required this.currency,
    required this.days,
    this.startDate,
    this.endDate,
    this.targetBudget,
    this.travelStyle = 'Moderate',
    this.interests = const [],
    this.createdAt,
  });

  final String tripId;
  final String destination;
  final int durationDays;
  final double totalEstimatedCost;
  final String currency;
  final List<DayPlanModel> days;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? targetBudget;
  final String travelStyle;
  final List<String> interests;
  final DateTime? createdAt;

  double get effectiveBudget => targetBudget ?? totalEstimatedCost;

  List<String> get allActivityTitles => [
        for (final day in days)
          for (final act in day.activities) act.title,
      ];

  factory TripModel.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? const [];
    final rawInterests = json['interests'] as List<dynamic>? ?? const [];
    return TripModel(
      tripId: json['trip_id'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? rawDays.length,
      totalEstimatedCost:
          (json['total_estimated_cost'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] as String? ?? 'USD').toUpperCase(),
      days: rawDays
          .whereType<Map<String, dynamic>>()
          .map(DayPlanModel.fromJson)
          .toList(),
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'] as String)
          : null,
      targetBudget: (json['target_budget'] as num?)?.toDouble(),
      travelStyle: json['travel_style'] as String? ?? 'Moderate',
      interests: rawInterests.map((e) => e.toString()).toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'destination': destination,
      'duration_days': durationDays,
      'total_estimated_cost': totalEstimatedCost,
      'currency': currency,
      'days': days.map((d) => d.toJson()).toList(),
      if (startDate != null) 'start_date': AppFormatters.toIsoDate(startDate!),
      if (endDate != null) 'end_date': AppFormatters.toIsoDate(endDate!),
      if (targetBudget != null) 'target_budget': targetBudget,
      'travel_style': travelStyle,
      'interests': interests,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  TripModel copyWith({
    String? tripId,
    String? destination,
    int? durationDays,
    double? totalEstimatedCost,
    String? currency,
    List<DayPlanModel>? days,
    DateTime? startDate,
    DateTime? endDate,
    double? targetBudget,
    String? travelStyle,
    List<String>? interests,
    DateTime? createdAt,
  }) {
    return TripModel(
      tripId: tripId ?? this.tripId,
      destination: destination ?? this.destination,
      durationDays: durationDays ?? this.durationDays,
      totalEstimatedCost: totalEstimatedCost ?? this.totalEstimatedCost,
      currency: currency ?? this.currency,
      days: days ?? this.days,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      targetBudget: targetBudget ?? this.targetBudget,
      travelStyle: travelStyle ?? this.travelStyle,
      interests: interests ?? this.interests,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
