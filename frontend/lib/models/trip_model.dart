import '../core/utils/formatters.dart';
import 'day_plan_model.dart';
import 'place_option_model.dart';
import 'transport_summary_model.dart';

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
    this.travelMode = 'air',
    this.departureCity,
  });

  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final double budget;
  final String currency;
  final List<String> interests;
  final String travelStyle;
  final String travelMode;
  final String? departureCity;

  /// Inclusive trip length calculated in UTC to avoid DST off-by-one bugs.
  int get durationDays {
    final startUtc = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final endUtc = DateTime.utc(endDate.year, endDate.month, endDate.day);
    return endUtc.difference(startUtc).inDays + 1;
  }

  Map<String, dynamic> toJson() {
    final trimmedDeparture = departureCity?.trim();
    return {
      'destination': destination.trim(),
      'start_date': AppFormatters.toIsoDate(startDate),
      'end_date': AppFormatters.toIsoDate(endDate),
      'budget': budget,
      'currency': currency.toUpperCase(),
      'interests': interests,
      'travel_style': travelStyle,
      'travel_mode': travelMode,
      if (trimmedDeparture != null && trimmedDeparture.isNotEmpty)
        'departure_city': trimmedDeparture,
    };
  }
}

/// Outgoing request payload for `POST /api/v1/itinerary/regenerate-slot` (FM3).
class RegenerateSlotRequestModel {
  const RegenerateSlotRequestModel({
    required this.destination,
    required this.dayNumber,
    required this.timeSlot,
    required this.budgetRemaining,
    required this.currency,
    required this.interests,
    required this.travelStyle,
    this.existingActivityTitles = const [],
    this.activityId,
    this.userNote,
  });

  final String destination;
  final int dayNumber;
  final String timeSlot;
  final double budgetRemaining;
  final String currency;
  final List<String> interests;
  final String travelStyle;
  final List<String> existingActivityTitles;
  final String? activityId;
  final String? userNote;

  Map<String, dynamic> toJson() {
    return {
      'destination': destination.trim(),
      'day_number': dayNumber,
      'time_slot': timeSlot,
      'budget_remaining': budgetRemaining < 0 ? 0.0 : budgetRemaining,
      'currency': currency.toUpperCase(),
      'interests': interests.isEmpty ? const ['Sightseeing'] : interests,
      'travel_style': travelStyle,
      'existing_activity_titles': existingActivityTitles,
      if (activityId != null) 'activity_id': activityId,
      if (userNote != null && userNote!.trim().isNotEmpty)
        'user_note': userNote!.trim(),
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
    this.travelMode = 'air',
    this.departureCity,
    this.transportSummary,
    this.hotelOptions = const [],
    this.diningOptions = const [],
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
  final String travelMode;
  final String? departureCity;
  final TransportSummaryModel? transportSummary;
  final List<PlaceOptionModel> hotelOptions;
  final List<PlaceOptionModel> diningOptions;

  double get effectiveBudget => targetBudget ?? effectiveTotalCost;

  /// Reactive total trip estimate combining the selected hotel's total stay
  /// cost (if any), selected dining options (or activity costs when no dining
  /// options exist), and estimated transport cost. Falls back cleanly to
  /// [totalEstimatedCost] for legacy saved trips without comparison options.
  double get effectiveTotalCost {
    if (hotelOptions.isEmpty &&
        diningOptions.isEmpty &&
        transportSummary == null) {
      return totalEstimatedCost;
    }

    final hotelCost = hotelOptions
        .where((h) => h.selected)
        .fold<double>(0.0, (sum, h) => sum + h.totalEstimatedCost);

    final diningOrActivityCost = diningOptions.isNotEmpty
        ? diningOptions
            .where((d) => d.selected)
            .fold<double>(0.0, (sum, d) => sum + d.totalEstimatedCost)
        : totalEstimatedCost;

    final transportCost = transportSummary?.estimatedCost ?? 0.0;

    return double.parse(
      (hotelCost + diningOrActivityCost + transportCost).toStringAsFixed(2),
    );
  }

  List<String> get allActivityTitles => [
        for (final day in days)
          for (final act in day.activities) act.title,
      ];

  factory TripModel.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'] as List<dynamic>? ?? const [];
    final rawInterests = json['interests'] as List<dynamic>? ?? const [];
    final rawHotels = json['hotel_options'] as List<dynamic>? ?? const [];
    final rawDining = json['dining_options'] as List<dynamic>? ?? const [];
    final rawTransport = json['transport_summary'];

    return TripModel(
      tripId: json['trip_id'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? rawDays.length,
      totalEstimatedCost:
          (json['total_estimated_cost'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] as String? ?? 'PKR').toUpperCase(),
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
      travelMode: json['travel_mode'] as String? ?? 'air',
      departureCity: json['departure_city'] as String?,
      transportSummary: rawTransport is Map<String, dynamic>
          ? TransportSummaryModel.fromJson(rawTransport)
          : null,
      hotelOptions: rawHotels
          .whereType<Map<String, dynamic>>()
          .map(PlaceOptionModel.fromJson)
          .toList(),
      diningOptions: rawDining
          .whereType<Map<String, dynamic>>()
          .map(PlaceOptionModel.fromJson)
          .toList(),
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
      'travel_mode': travelMode,
      if (departureCity != null && departureCity!.trim().isNotEmpty)
        'departure_city': departureCity!.trim(),
      if (transportSummary != null)
        'transport_summary': transportSummary!.toJson(),
      'hotel_options': hotelOptions.map((h) => h.toJson()).toList(),
      'dining_options': diningOptions.map((d) => d.toJson()).toList(),
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
    String? travelMode,
    String? departureCity,
    TransportSummaryModel? transportSummary,
    List<PlaceOptionModel>? hotelOptions,
    List<PlaceOptionModel>? diningOptions,
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
      travelMode: travelMode ?? this.travelMode,
      departureCity: departureCity ?? this.departureCity,
      transportSummary: transportSummary ?? this.transportSummary,
      hotelOptions: hotelOptions ?? this.hotelOptions,
      diningOptions: diningOptions ?? this.diningOptions,
    );
  }
}
