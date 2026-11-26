import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_travel_planner/core/theme/app_theme.dart';
import 'package:ai_travel_planner/core/utils/formatters.dart';
import 'package:ai_travel_planner/main.dart';
import 'package:ai_travel_planner/models/activity_model.dart';
import 'package:ai_travel_planner/models/day_plan_model.dart';
import 'package:ai_travel_planner/models/place_option_model.dart';
import 'package:ai_travel_planner/models/transport_summary_model.dart';
import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/providers/trip_provider.dart';
import 'package:ai_travel_planner/screens/itinerary/itinerary_screen.dart';
import 'package:ai_travel_planner/screens/trip_creation/trip_creation_screen.dart';
import 'package:ai_travel_planner/services/api_service.dart';
import 'package:ai_travel_planner/services/storage_service.dart';
import 'package:ai_travel_planner/widgets/comparison_option_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

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

ResponseBody _jsonResponse(Object body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ApiService _makeApiService(_MockHandler handler) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = _MockAdapter(handler);
  return ApiService(dio: dio);
}

TripModel _buildComparisonTrip({double targetBudget = 40000}) {
  return TripModel(
    tripId: 'trip_lahore_road_01',
    destination: 'Lahore, Pakistan',
    durationDays: 2,
    totalEstimatedCost: 6000,
    currency: 'PKR',
    targetBudget: targetBudget,
    travelStyle: 'Moderate',
    travelMode: 'road',
    departureCity: 'Islamabad',
    transportSummary: const TransportSummaryModel(
      mode: 'road',
      estimatedCost: 8500,
      priceSource: 'ai_estimated',
      notes: 'Round-trip fuel and M-2 Motorway toll.',
      routeTip: 'Take M-2 Motorway via Kallar Kahar (~4.5 hrs).',
    ),
    hotelOptions: const [
      PlaceOptionModel(
        optionId: 'hotel_budget',
        name: 'Hotel One Gulberg',
        tier: 'budget',
        estimatedPrice: 9000,
        totalEstimatedCost: 18000,
        priceSource: 'web_found',
        priceNote: 'Public listing rate',
        latitude: 31.512,
        longitude: 74.351,
        verified: true,
        distanceToCenterKm: 2.3,
        highlights: ['Free parking', 'Breakfast included'],
        selected: true,
      ),
      PlaceOptionModel(
        optionId: 'hotel_comfort',
        name: 'Pearl Continental Lahore',
        tier: 'comfort',
        estimatedPrice: 22000,
        totalEstimatedCost: 44000,
        priceSource: 'ai_estimated',
        priceNote: 'Estimated nightly rate',
        latitude: 31.552,
        longitude: 74.338,
        verified: true,
        distanceToCenterKm: 1.1,
        highlights: ['Pool', 'Mall Road access'],
        selected: false,
      ),
    ],
    diningOptions: const [
      PlaceOptionModel(
        optionId: 'food_1',
        name: 'Haveli Restaurant',
        tier: 'mid_range',
        estimatedPrice: 2500,
        totalEstimatedCost: 2500,
        priceSource: 'web_found',
        priceNote: 'Menu price found online',
        latitude: 31.588,
        longitude: 74.311,
        verified: true,
        distanceToCenterKm: 0.6,
        highlights: ['Badshahi Mosque view', 'BBQ'],
        selected: true,
      ),
      PlaceOptionModel(
        optionId: 'food_2',
        name: 'Butt Karahi Lakshmi',
        tier: 'budget',
        estimatedPrice: 1800,
        totalEstimatedCost: 1800,
        priceSource: 'ai_estimated',
        priceNote: 'Estimated per-person meal',
        latitude: 31.564,
        longitude: 74.324,
        verified: true,
        distanceToCenterKm: 1.4,
        highlights: ['Desi Karahi'],
        selected: false,
      ),
    ],
    days: const [
      DayPlanModel(
        dayNumber: 1,
        title: 'Walled City & Food Street',
        totalDistanceKm: 6.4,
        feasible: true,
        activities: [
          ActivityModel(
            activityId: 'act_1',
            timeSlot: 'Morning',
            title: 'Badshahi Mosque',
            description: 'Iconic Mughal-era mosque.',
            category: 'Historical',
            estimatedCost: 500,
            latitude: 31.5881,
            longitude: 74.3105,
            verified: true,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('Phase 3 Models & Backward Compatibility', () {
    test('Legacy saved trip JSON without new fields deserializes safely', () {
      final legacyJson = <String, dynamic>{
        'trip_id': 'legacy_01',
        'destination': 'Skardu, Pakistan',
        'duration_days': 3,
        'total_estimated_cost': 320.0,
        'currency': 'USD',
        'days': [
          {
            'day_number': 1,
            'title': 'Arrival',
            'activities': [],
          },
        ],
      };

      final trip = TripModel.fromJson(legacyJson);
      expect(trip.travelMode, 'air');
      expect(trip.departureCity, isNull);
      expect(trip.transportSummary, isNull);
      expect(trip.hotelOptions, isEmpty);
      expect(trip.diningOptions, isEmpty);
      // Falls back cleanly to legacy totalEstimatedCost
      expect(trip.effectiveTotalCost, 320.0);
    });

    test('TransportSummaryModel and PlaceOptionModel JSON round-trip cleanly', () {
      const transport = TransportSummaryModel(
        mode: 'train',
        estimatedCost: 4200,
        priceSource: 'web_found',
        notes: 'Green Line Express',
        routeTip: 'Book AC Parlor early.',
      );
      final tDecoded = TransportSummaryModel.fromJson(transport.toJson());
      expect(tDecoded.mode, 'train');
      expect(tDecoded.modeLabel, 'Train');
      expect(tDecoded.estimatedCost, 4200);
      expect(tDecoded.isWebFound, isTrue);
      expect(tDecoded.routeTip, 'Book AC Parlor early.');

      const option = PlaceOptionModel(
        optionId: 'opt_1',
        name: 'Serena Hotel',
        tier: 'comfort',
        estimatedPrice: 25000,
        totalEstimatedCost: 50000,
        priceSource: 'web_found',
        priceNote: 'Online listing',
        latitude: 33.707,
        longitude: 73.101,
        verified: true,
        distanceToCenterKm: 2.0,
        highlights: ['Garden', 'Buffet'],
        selected: true,
      );
      final oDecoded = PlaceOptionModel.fromJson(option.toJson());
      expect(oDecoded.optionId, 'opt_1');
      expect(oDecoded.tierLabel, 'Comfort');
      expect(oDecoded.hasCoordinates, isTrue);
      expect(oDecoded.isWebFound, isTrue);
      expect(oDecoded.highlights, ['Garden', 'Buffet']);
      expect(oDecoded.selected, isTrue);
    });

    test('TripRequestModel includes travel_mode and optional departure_city', () {
      final roadReq = TripRequestModel(
        destination: 'Lahore',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 2),
        budget: 45000,
        currency: 'PKR',
        interests: const ['Historical', 'Local Food'],
        travelStyle: 'Moderate',
        travelMode: 'road',
        departureCity: '  Islamabad  ',
      );
      final json = roadReq.toJson();
      expect(json['travel_mode'], 'road');
      expect(json['departure_city'], 'Islamabad');

      final defaultReq = TripRequestModel(
        destination: 'Lahore',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 2),
        budget: 45000,
        currency: 'PKR',
        interests: const ['Historical'],
        travelStyle: 'Moderate',
        departureCity: '   ',
      );
      final defaultJson = defaultReq.toJson();
      expect(defaultJson['travel_mode'], 'air');
      expect(defaultJson.containsKey('departure_city'), isFalse);
    });

    test('TripModel JSON round-trip preserves comparison options & effectiveTotalCost', () {
      final trip = _buildComparisonTrip();
      // 18000 (selected hotel) + 2500 (selected food) + 8500 (transport) = 29000
      expect(trip.effectiveTotalCost, 29000.0);

      final roundTrip = TripModel.fromJson(
        jsonDecode(jsonEncode(trip.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip.travelMode, 'road');
      expect(roundTrip.departureCity, 'Islamabad');
      expect(roundTrip.transportSummary?.estimatedCost, 8500);
      expect(roundTrip.hotelOptions.length, 2);
      expect(roundTrip.diningOptions.length, 2);
      expect(roundTrip.effectiveTotalCost, 29000.0);
    });
  });

  group('Phase 3 TripProvider Reactive Selection & Persistence', () {
    test('selectHotelOption & toggleDiningOption update effectiveTotalCost and persist', () async {
      final storage = InMemoryStorageService();
      final trip = _buildComparisonTrip();
      await storage.saveTrip(trip);

      final provider = TripProvider(storage: storage);
      await provider.loadSavedTrips();
      provider.selectTrip(trip);

      expect(provider.activeTrip?.effectiveTotalCost, 29000.0);

      // Switch to comfort hotel (44000) -> 44000 + 2500 + 8500 = 55000
      provider.selectHotelOption(trip.tripId, 'hotel_comfort');
      expect(provider.activeTrip?.effectiveTotalCost, 55000.0);
      expect(
        provider.activeTrip!.hotelOptions
            .where((h) => h.selected)
            .map((h) => h.optionId)
            .toList(),
        ['hotel_comfort'],
      );

      // Include second dining option (+1800) -> 56800
      provider.toggleDiningOption(trip.tripId, 'food_2');
      expect(provider.activeTrip?.effectiveTotalCost, 56800.0);

      // Exclude first dining option (-2500) -> 54300
      provider.toggleDiningOption(trip.tripId, 'food_1');
      expect(provider.activeTrip?.effectiveTotalCost, 54300.0);

      // Verify persisted cleanly in storage
      final reloaded = await storage.loadTrips();
      expect(reloaded.single.effectiveTotalCost, 54300.0);
      expect(
        reloaded.single.hotelOptions
            .firstWhere((h) => h.optionId == 'hotel_comfort')
            .selected,
        isTrue,
      );
      expect(
        reloaded.single.diningOptions
            .firstWhere((d) => d.optionId == 'food_2')
            .selected,
        isTrue,
      );
    });
  });

  group('Phase 3 UI Widgets (Travel Mode Picker & Comparison Cards)', () {
    testWidgets(
      'TripCreationScreen submits chosen Travel Mode and optional departureCity',
      (tester) async {
        Map<String, dynamic>? capturedPayload;
        final api = _makeApiService((options) {
          capturedPayload = Map<String, dynamic>.from(
            options.data as Map<String, dynamic>,
          );
          return _jsonResponse(_buildComparisonTrip().toJson());
        });

        await tester.pumpWidget(AITravelPlannerApp(apiService: api));

        await tester.tap(find.text('Explore as Guest'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Create Trip'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Destination'),
          'Lahore, Pakistan',
        );
        await tester.pumpAndSettle();

        // Scroll to Travel Mode picker, choose "By Road", and type departure city.
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -340),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('By Road'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Departing From (optional)'),
          'Islamabad',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate AI Itinerary'));
        await tester.pumpAndSettle();

        expect(capturedPayload, isNotNull);
        expect(capturedPayload!['travel_mode'], 'road');
        expect(capturedPayload!['departure_city'], 'Islamabad');
      },
    );

    testWidgets(
      'ItineraryScreen renders live budget meter, transport banner, honest badges & updates live at 390px',
      (tester) async {
        // Test at realistic 390x844 mobile viewport to guarantee zero RenderFlex overflow.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final storage = InMemoryStorageService();
        final trip = _buildComparisonTrip(targetBudget: 40000);
        await storage.saveTrip(trip);
        final provider = TripProvider(storage: storage);
        await provider.loadSavedTrips();
        provider.selectTrip(trip);

        await tester.pumpWidget(
          ChangeNotifierProvider<TripProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ItineraryScreen(trip: trip),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Live Budget Meter initial state: 29,000 / 40,000 -> Rs 11,000 left
        expect(find.textContaining('Rs 29,000'), findsOneWidget);
        expect(find.text('Rs 11,000 left'), findsOneWidget);

        // Section switcher shows dynamic counts
        expect(find.text('Itinerary'), findsOneWidget);
        expect(find.text('Hotels (2)'), findsOneWidget);
        expect(find.text('Food (2)'), findsOneWidget);

        // Transport Summary Banner in Itinerary view
        expect(find.text('By Road from Islamabad'), findsOneWidget);
        expect(
          find.text('Take M-2 Motorway via Kallar Kahar (~4.5 hrs).'),
          findsOneWidget,
        );

        // Switch to Hotels tab -> verify honest Web Rate vs AI Est. badges & live switch
        await tester.tap(find.text('Hotels (2)'));
        await tester.pumpAndSettle();

        expect(find.text('Hotel One Gulberg'), findsOneWidget);
        expect(find.text('Pearl Continental Lahore'), findsOneWidget);
        expect(find.text('Web Rate'), findsOneWidget);
        expect(find.text('AI Est.'), findsOneWidget);
        expect(find.text('Selected ✓'), findsOneWidget);
        expect(find.text('Choose Hotel'), findsOneWidget);
        expect(find.text('Check Live'), findsNWidgets(2));
        expect(find.text('Show on Map'), findsNWidgets(2));

        // Switch to Pearl Continental Lahore -> live total jumps to 55,000 (Over by Rs 15,000)
        await tester.ensureVisible(find.text('Choose Hotel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose Hotel'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Rs 55,000'), findsOneWidget);
        expect(find.text('Over by Rs 15,000'), findsOneWidget);

        // Switch to Food tab -> include Butt Karahi Lakshmi (+1,800 -> 56,800, Over by Rs 16,800)
        await tester.tap(find.text('Food (2)'));
        await tester.pumpAndSettle();

        expect(find.text('Haveli Restaurant'), findsOneWidget);
        expect(find.text('Butt Karahi Lakshmi'), findsOneWidget);
        expect(find.text('Included ✓'), findsOneWidget);
        expect(find.text('Include'), findsOneWidget);

        await tester.ensureVisible(find.text('Include'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Include'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Rs 56,800'), findsOneWidget);
        expect(find.text('Over by Rs 16,800'), findsOneWidget);
      },
    );

    testWidgets(
      'ItineraryScreen shows clean empty states for legacy trips with 0 options',
      (tester) async {
        final legacyTrip = TripModel.fromJson({
          'trip_id': 'legacy_ui_01',
          'destination': 'Swat Valley',
          'duration_days': 1,
          'total_estimated_cost': 120.0,
          'currency': 'USD',
          'days': [
            {
              'day_number': 1,
              'title': 'Mingora & Fizagat',
              'activities': [
                {
                  'activity_id': 'a1',
                  'time_slot': 'Morning',
                  'title': 'Fizagat Park',
                  'description': 'Riverside park.',
                  'category': 'Nature',
                  'estimated_cost': 10.0,
                },
              ],
            },
          ],
        });

        final provider = TripProvider();
        provider.selectTrip(legacyTrip);

        await tester.pumpWidget(
          ChangeNotifierProvider<TripProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ItineraryScreen(trip: legacyTrip),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hotels (0)'), findsOneWidget);
        expect(find.text('Food (0)'), findsOneWidget);

        await tester.tap(find.text('Hotels (0)'));
        await tester.pumpAndSettle();
        expect(find.text('No hotel comparisons saved'), findsOneWidget);

        await tester.tap(find.text('Food (0)'));
        await tester.pumpAndSettle();
        expect(find.text('No dining comparisons saved'), findsOneWidget);
      },
    );

    testWidgets(
      'ComparisonOptionCard builds proper Google search URI and fires callbacks',
      (tester) async {
        var checkLiveCalled = false;
        var mapCalled = false;
        const opt = PlaceOptionModel(
          optionId: 'h1',
          name: 'Serena Hotel',
          tier: 'comfort',
          estimatedPrice: 120,
          totalEstimatedCost: 240,
          priceSource: 'web_found',
          verified: true,
        );

        final card = ComparisonOptionCard(
          option: opt,
          currency: 'USD',
          destination: 'Hunza',
          isHotel: true,
          onToggleSelect: () {},
          onShowOnMap: () => mapCalled = true,
          onCheckLive: () => checkLiveCalled = true,
        );

        expect(
          card.liveSearchUri.toString(),
          'https://www.google.com/search?q=Serena+Hotel+Hunza+price',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: card),
          ),
        );

        await tester.tap(find.text('Check Live'));
        await tester.tap(find.text('Show on Map'));
        expect(checkLiveCalled, isTrue);
        expect(mapCalled, isTrue);
      },
    );

    testWidgets(
      'TripCreationScreen defaults to PKR / 50000 and renders full Budget, Moderate, Luxury at 390x844',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        expect(AppFormatters.formatCurrency(50000.49, 'PKR'), 'Rs 50,000');
        expect(AppFormatters.formatCompactPrice(12000, 'PKR'), 'Rs 12k');
        expect(AppFormatters.formatCompactPrice(1500, 'PKR'), 'Rs 1.5k');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TripCreationScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Default currency is PKR and default budget is 50000
        expect(find.text('PKR'), findsOneWidget);
        final budgetField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Total Budget'),
        );
        expect(budgetField.controller?.text, '50000');

        // Scroll to Travel Style and verify all 3 labels render cleanly without overflow
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -420),
        );
        await tester.pumpAndSettle();

        expect(find.text('Budget'), findsOneWidget);
        expect(find.text('Moderate'), findsOneWidget);
        expect(find.text('Luxury'), findsOneWidget);

        await tester.tap(find.text('Luxury'));
        await tester.pumpAndSettle();
      },
    );
  });
}
