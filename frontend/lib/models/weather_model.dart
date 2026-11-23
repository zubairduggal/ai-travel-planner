/// Single-day forecast item returned by FastAPI `GET /api/v1/weather`.
class DailyWeatherModel {
  const DailyWeatherModel({
    required this.date,
    required this.condition,
    this.tempMaxC,
    this.tempMinC,
    this.precipitationProbabilityMax,
    this.weatherCode,
  });

  final DateTime date;
  final double? tempMaxC;
  final double? tempMinC;
  final int? precipitationProbabilityMax;
  final int? weatherCode;
  final String condition;

  factory DailyWeatherModel.fromJson(Map<String, dynamic> json) {
    return DailyWeatherModel(
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      tempMaxC: (json['temp_max_c'] as num?)?.toDouble(),
      tempMinC: (json['temp_min_c'] as num?)?.toDouble(),
      precipitationProbabilityMax:
          (json['precipitation_probability_max'] as num?)?.toInt(),
      weatherCode: (json['weather_code'] as num?)?.toInt(),
      condition: json['condition'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String().split('T').first,
      'temp_max_c': tempMaxC,
      'temp_min_c': tempMinC,
      'precipitation_probability_max': precipitationProbabilityMax,
      'weather_code': weatherCode,
      'condition': condition,
    };
  }
}

/// Multi-day weather forecast response matching FastAPI `WeatherResponseSchema`.
class WeatherForecastModel {
  const WeatherForecastModel({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.daily,
  });

  final double latitude;
  final double longitude;
  final String timezone;
  final List<DailyWeatherModel> daily;

  factory WeatherForecastModel.fromJson(Map<String, dynamic> json) {
    final rawDaily = json['daily'] as List<dynamic>? ?? const [];
    return WeatherForecastModel(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      timezone: json['timezone'] as String? ?? 'UTC',
      daily: rawDaily
          .whereType<Map<String, dynamic>>()
          .map(DailyWeatherModel.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timezone': timezone,
      'daily': daily.map((d) => d.toJson()).toList(),
    };
  }
}
