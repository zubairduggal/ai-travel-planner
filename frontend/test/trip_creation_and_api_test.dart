import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_travel_planner/core/utils/formatters.dart';
import 'package:ai_travel_planner/main.dart';
import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/providers/trip_provider.dart';
import 'package:ai_travel_planner/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

typedef _MockHandler = ResponseBody Function(RequestOptions options);

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this._handler);

  final _MockHandler _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(
  Object body, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?headers,
    },
  );
}

final _sampleApiItinerary = <String, dynamic>{
  'trip_id': 'itinerary_ab12cd34',
  'destination': 'Hunza Valley, Pakistan',
  'duration_days': 2,
  'total_estimated_cost': 65.0,
  'currency': 'USD',
  'days': [
    {
      'day_number': 1,
      'title': 'Karimabad Heritage',
      'total_distance_km': 2.1,
      'feasible': true,
      'distance_warnings': <String>[],
      'activities': [
        {
          'activity_id': 'act_01',
          'time_slot': 'Morning',
          'title': 'Visit Baltit Fort',
          'description': 'Historic 700-year-old fort overlooking Hunza.',
          'category': 'Historical',
          'estimated_cost': 15.0,
          'latitude': 36.3256,
          'longitude': 74.6678,
          'verified': true,
        },
      ],
    },
    {
      'day_number': 2,
      'title': 'Attabad & Passu',
      'total_distance_km': 62.5,
      'feasible': false,
      'distance_warnings': [
        'Distance exceeds the 50 km same-day limit.',
      ],
      'activities': [
        {
          'activity_id': 'act_02',
          'time_slot': 'Afternoon',
          'title': 'Boat ride at Attabad Lake',
          'description': 'Turquoise alpine lake.',
          'category': 'Nature',
          'estimated_cost': 50.0,
          'latitude': 36.3274,
          'longitude': 74.8439,
          'verified': true,
        },
      ],
    },
  ],
};

final _sampleRequest = TripRequestModel(
  destination: 'Hunza Valley, Pakistan',
  startDate: DateTime(2026, 6, 10),
  endDate: DateTime(2026, 6, 11),
  budget: 300.0,
  currency: 'USD',
  interests: const ['Nature', 'Photography'],
  travelStyle: 'Moderate',
);

ApiService _makeApiService(_MockHandler handler) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = _MockAdapter(handler);
  return ApiService(dio: dio);
}

void main() {
  group('FM1 Review Fixes', () {
    test('formatCurrency places minus sign before currency symbol', () {
      expect(AppFormatters.formatCurrency(-50.5, 'USD'), r'-$50.5');
      expect(AppFormatters.formatCurrency(-1200, 'PKR'), '-Rs 1,200');
    });

    test('durationDays stays accurate across calendar boundaries', () {
      final req = TripRequestModel(
        destination: 'Lahore',
        startDate: DateTime(2026, 3, 7),
        endDate: DateTime(2026, 3, 10),
        budget: 200,
        currency: 'USD',
        interests: const ['Food'],
        travelStyle: 'Budget',
      );
      expect(req.durationDays, 4);
    });
  });

  group('ApiService (Dio REST client)', () {
    test('checkHealth returns true on 200 ok', () async {
      final api = _makeApiService(
        (_) => _jsonResponse({'status': 'ok', 'environment': 'development'}),
      );
      expect(await api.checkHealth(), isTrue);
    });

    test('generateItinerary parses trip, metadata, and X-Cache header', () async {
      final api = _makeApiService(
        (options) {
          expect(options.path, '/api/v1/itinerary/generate');
          expect(options.method, 'POST');
          return _jsonResponse(
            _sampleApiItinerary,
            headers: {
              'x-cache': ['HIT'],
            },
          );
        },
      );

      final result = await api.generateItinerary(_sampleRequest);
      expect(result.wasCached, isTrue);
      expect(result.trip.tripId, 'itinerary_ab12cd34');
      expect(result.trip.targetBudget, 300.0);
      expect(result.trip.travelStyle, 'Moderate');
      expect(result.trip.days.length, 2);
      expect(result.trip.days[1].feasible, isFalse);
    });

    test('maps 429 RATE_LIMIT_EXCEEDED to friendly message', () async {
      final api = _makeApiService(
        (_) => _jsonResponse(
          {
            'error': {
              'code': 'RATE_LIMIT_EXCEEDED',
              'message': 'Rate limit exceeded: 5 per 1 day',
            },
          },
          statusCode: 429,
        ),
      );

      expect(
        () => api.generateItinerary(_sampleRequest),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'RATE_LIMIT_EXCEEDED')
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', contains('daily limit of 5')),
        ),
      );
    });

    test('maps 401 UNAUTHORIZED and 422 validation errors cleanly', () async {
      final api401 = _makeApiService(
        (_) => _jsonResponse(
          {
            'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid API key.'},
          },
          statusCode: 401,
        ),
      );
      await expectLater(
        () => api401.generateItinerary(_sampleRequest),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );

      final api422 = _makeApiService(
        (_) => _jsonResponse(
          {
            'detail': [
              {'msg': 'Trip duration cannot exceed 14 days'},
            ],
          },
          statusCode: 422,
        ),
      );
      await expectLater(
        () => api422.generateItinerary(_sampleRequest),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'VALIDATION_ERROR')
              .having((e) => e.message, 'message', contains('14 days')),
        ),
      );
    });

    test('maps Dio timeout to AI_TIMEOUT', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException.receiveTimeout(
                timeout: const Duration(seconds: 65),
                requestOptions: options,
              ),
            );
          },
        ),
      );
      final api = ApiService(dio: dio);

      await expectLater(
        () => api.generateItinerary(_sampleRequest),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'AI_TIMEOUT'),
        ),
      );
    });
  });

  group('TripProvider & End-to-End FM2 UI Flow', () {
    test('TripProvider stores generated trip and captures errors', () async {
      final okApi = _makeApiService((_) => _jsonResponse(_sampleApiItinerary));
      final provider = TripProvider(apiService: okApi);

      final generated = await provider.generateTrip(_sampleRequest);
      expect(generated, isNotNull);
      expect(provider.trips.length, 1);
      expect(provider.activeTrip?.tripId, 'itinerary_ab12cd34');
      expect(provider.errorMessage, isNull);

      final badApi = _makeApiService(
        (_) => _jsonResponse(
          {
            'error': {'code': 'AI_PROVIDER_ERROR', 'message': 'Upstream down'},
          },
          statusCode: 502,
        ),
      );
      final failingProvider = TripProvider(apiService: badApi);
      final failed = await failingProvider.generateTrip(_sampleRequest);
      expect(failed, isNull);
      expect(failingProvider.errorCode, 'AI_PROVIDER_ERROR');
    });

    testWidgets(
      'TripCreationScreen validates input and navigates to ItineraryScreen',
      (tester) async {
        final api = _makeApiService(
          (_) => _jsonResponse(
            _sampleApiItinerary,
            headers: {
              'x-cache': ['HIT'],
            },
          ),
        );

        await tester.pumpWidget(AITravelPlannerApp(apiService: api));

        // Enter via Guest Mode -> opens Home Explore -> tap center '+' Create Trip FAB.
        await tester.tap(find.text('Explore as Guest'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Create Trip'));
        await tester.pumpAndSettle();

        // Scroll to Generate button and tap with empty destination -> validation blocks API.
        await tester.ensureVisible(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a destination.'), findsOneWidget);

        // Enter destination and test invalid budget.
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'Destination'),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Destination'),
          'Hunza Valley, Pakistan',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Total Budget'),
          '0',
        );
        await tester.ensureVisible(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();
        expect(find.text('Budget must be greater than 0.'), findsOneWidget);

        // Fix budget and submit -> LoadingScreen -> ItineraryScreen!
        await tester.ensureVisible(
          find.widgetWithText(TextFormField, 'Total Budget'),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Total Budget'),
          '500',
        );
        await tester.ensureVisible(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();

        // Verify Day 1 renders cleanly on ItineraryScreen with View Map pill.
        expect(find.text('Hunza Valley, Pakistan'), findsOneWidget);
        expect(find.text('Visit Baltit Fort'), findsOneWidget);
        expect(find.text('Verified GPS'), findsOneWidget);
        expect(find.text('Instant Cache'), findsOneWidget);
        expect(find.text('View Map'), findsOneWidget);

        // Switch to Day 2 tab and verify Haversine distance warning appears.
        await tester.tap(find.text('Day 2'));
        await tester.pumpAndSettle();
        expect(find.text('Boat ride at Attabad Lake'), findsOneWidget);
        expect(find.text('Long travel distance detected'), findsOneWidget);
      },
    );

    testWidgets('LoadingScreen shows Retry on API failure and recovers', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var attempt = 0;
      final flakyApi = _makeApiService((_) {
        attempt++;
        if (attempt == 1) {
          return _jsonResponse(
            {
              'error': {'code': 'AI_TIMEOUT', 'message': 'Timed out'},
            },
            statusCode: 504,
          );
        }
        return _jsonResponse(_sampleApiItinerary);
      });

      await tester.pumpWidget(AITravelPlannerApp(apiService: flakyApi));
      await tester.tap(find.text('Explore as Guest'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create Trip'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Destination'),
        'Hunza Valley, Pakistan',
      );
      await tester.ensureVisible(find.text('Generate AI Itinerary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate AI Itinerary'));
      await tester.pumpAndSettle();

      expect(find.text('Could not generate itinerary'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Visit Baltit Fort'), findsOneWidget);
    });
  });
}
