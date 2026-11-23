/// A single activity inside a daily itinerary plan.
///
/// Matches FastAPI `ActivitySchema` 1:1 plus local-only `notes` and optional
/// `duration` fields for mobile customization (MFR-06, MFR-07).
class ActivityModel {
  const ActivityModel({
    required this.activityId,
    required this.timeSlot,
    required this.title,
    required this.description,
    required this.category,
    required this.estimatedCost,
    this.latitude,
    this.longitude,
    this.verified = false,
    this.notes,
    this.duration,
  });

  final String activityId;
  final String timeSlot;
  final String title;
  final String description;
  final String category;
  final double estimatedCost;
  final double? latitude;
  final double? longitude;
  final bool verified;
  final String? notes;
  final String? duration;

  bool get hasCoordinates => latitude != null && longitude != null;

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      activityId: json['activity_id'] as String? ?? '',
      timeSlot: json['time_slot'] as String? ?? 'Morning',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      estimatedCost: (json['estimated_cost'] as num?)?.toDouble() ?? 0.0,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      verified: json['verified'] as bool? ?? false,
      notes: json['notes'] as String?,
      duration: json['duration'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activity_id': activityId,
      'time_slot': timeSlot,
      'title': title,
      'description': description,
      'category': category,
      'estimated_cost': estimatedCost,
      'latitude': latitude,
      'longitude': longitude,
      'verified': verified,
      if (notes != null) 'notes': notes,
      if (duration != null) 'duration': duration,
    };
  }

  ActivityModel copyWith({
    String? activityId,
    String? timeSlot,
    String? title,
    String? description,
    String? category,
    double? estimatedCost,
    double? latitude,
    double? longitude,
    bool? verified,
    String? notes,
    bool clearNotes = false,
    String? duration,
  }) {
    return ActivityModel(
      activityId: activityId ?? this.activityId,
      timeSlot: timeSlot ?? this.timeSlot,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      verified: verified ?? this.verified,
      notes: clearNotes ? null : (notes ?? this.notes),
      duration: duration ?? this.duration,
    );
  }
}
