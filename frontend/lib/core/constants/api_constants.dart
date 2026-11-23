import 'package:flutter/foundation.dart';

/// Backend REST API configuration and endpoints.
///
/// Override at build/run time with:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000 --dart-define=API_KEY=secret`
class ApiConstants {
  ApiConstants._();

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String apiKey = String.fromEnvironment('API_KEY');

  /// Default local FastAPI base URL per platform:
  /// - Android emulator uses 10.0.2.2 to reach host localhost.
  /// - iOS simulator, Web, and Desktop reach host via 127.0.0.1.
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl.endsWith('/')
          ? _envBaseUrl.substring(0, _envBaseUrl.length - 1)
          : _envBaseUrl;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  static const String apiV1Prefix = '/api/v1';
  static const String healthEndpoint = '$apiV1Prefix/health';
  static const String generateItineraryEndpoint =
      '$apiV1Prefix/itinerary/generate';
  static const String regenerateSlotEndpoint =
      '$apiV1Prefix/itinerary/regenerate-slot';
  static const String weatherEndpoint = '$apiV1Prefix/weather';

  static const Duration connectTimeout = Duration(seconds: 15);
  // Cold trips run Gemini + Nominatim (1 req/sec); cached trips return in ~5ms.
  static const Duration receiveTimeout = Duration(seconds: 90);
}
