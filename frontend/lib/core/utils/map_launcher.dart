import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds and launches native Google Maps or Apple Maps navigation URLs (MFR-09).
class MapLauncher {
  MapLauncher._();

  /// Returns an Apple Maps URL on iOS/macOS, and a Google Maps URL on Android/Web.
  static Uri buildExternalMapsUri({
    required double latitude,
    required double longitude,
    String? label,
    TargetPlatform? platform,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final coords =
        '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

    if (!kIsWeb &&
        (target == TargetPlatform.iOS || target == TargetPlatform.macOS)) {
      return Uri.https('maps.apple.com', '/', {
        'daddr': coords,
        if (label != null && label.trim().isNotEmpty) 'q': label.trim(),
      });
    }

    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': coords,
    });
  }

  /// Opens external maps app (or browser tab on Web) with pre-filled coordinates.
  static Future<bool> openExternalMaps({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final uri = buildExternalMapsUri(
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
