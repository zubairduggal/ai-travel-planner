import 'activity_model.dart';

/// One day inside a trip itinerary (matches FastAPI `DayPlanSchema`).
class DayPlanModel {
  const DayPlanModel({
    required this.dayNumber,
    required this.title,
    required this.activities,
    this.totalDistanceKm,
    this.feasible = true,
    this.distanceWarnings = const [],
  });

  final int dayNumber;
  final String title;
  final List<ActivityModel> activities;
  final double? totalDistanceKm;
  final bool feasible;
  final List<String> distanceWarnings;

  double get dayEstimatedCost =>
      activities.fold(0.0, (sum, item) => sum + item.estimatedCost);

  factory DayPlanModel.fromJson(Map<String, dynamic> json) {
    final rawActivities = json['activities'] as List<dynamic>? ?? const [];
    final rawWarnings = json['distance_warnings'] as List<dynamic>? ?? const [];
    return DayPlanModel(
      dayNumber: (json['day_number'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? 'Day Plan',
      activities: rawActivities
          .whereType<Map<String, dynamic>>()
          .map(ActivityModel.fromJson)
          .toList(),
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble(),
      feasible: json['feasible'] as bool? ?? true,
      distanceWarnings: rawWarnings.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_number': dayNumber,
      'title': title,
      'activities': activities.map((a) => a.toJson()).toList(),
      'total_distance_km': totalDistanceKm,
      'feasible': feasible,
      'distance_warnings': distanceWarnings,
    };
  }

  DayPlanModel copyWith({
    int? dayNumber,
    String? title,
    List<ActivityModel>? activities,
    double? totalDistanceKm,
    bool? feasible,
    List<String>? distanceWarnings,
  }) {
    return DayPlanModel(
      dayNumber: dayNumber ?? this.dayNumber,
      title: title ?? this.title,
      activities: activities ?? this.activities,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      feasible: feasible ?? this.feasible,
      distanceWarnings: distanceWarnings ?? this.distanceWarnings,
    );
  }
}
