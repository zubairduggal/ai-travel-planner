import 'dart:io';

import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

const bool _runLiveE2e = bool.fromEnvironment('RUN_LIVE_E2E');

/// Real end-to-end test calling a running local FastAPI backend (M1–M5).
///
/// Run with:
/// `flutter test test/live_backend_e2e_test.dart --dart-define=RUN_LIVE_E2E=true`
void main() {
  test(
    'Live Flutter ApiService -> FastAPI (/health, /generate MISS & HIT)',
    () async {
      // Allow real HTTP connections inside flutter_test when live E2E is enabled.
      HttpOverrides.global = null;

      final api = ApiService(baseUrl: 'http://127.0.0.1:8000');

      expect(await api.checkHealth(), isTrue);

      final req = TripRequestModel(
        destination: 'Hunza Valley, Pakistan',
        startDate: DateTime(2026, 6, 10),
        endDate: DateTime(2026, 6, 10),
        budget: 150.0,
        currency: 'USD',
        interests: const ['Nature', 'Historical'],
        travelStyle: 'Moderate',
      );

      final first = await api.generateItinerary(req);
      expect(first.trip.tripId, startsWith('itinerary_'));
      expect(first.trip.durationDays, 1);
      expect(first.trip.days.length, 1);
      expect(first.trip.days.first.activities, isNotEmpty);

      final second = await api.generateItinerary(req);
      expect(second.wasCached, isTrue);
      expect(second.trip.tripId, first.trip.tripId);

      // Print concise live telemetry for FM2 report.
      final allActs = first.trip.days.expand((d) => d.activities).toList();
      final verifiedCount = allActs.where((a) => a.verified).length;
      // ignore: avoid_print
      print(
        'LIVE_E2E_OK trip_id=${first.trip.tripId} '
        'first_cache=${first.cacheStatus} second_cache=${second.cacheStatus} '
        'days=${first.trip.days.length} acts=${allActs.length} '
        'verified=$verifiedCount/${allActs.length} '
        'cost=${first.trip.totalEstimatedCost} ${first.trip.currency}',
      );
    },
    skip: !_runLiveE2e,
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
