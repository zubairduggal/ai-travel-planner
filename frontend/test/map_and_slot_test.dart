import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_travel_planner/core/utils/map_launcher.dart';
import 'package:ai_travel_planner/models/activity_model.dart';
import 'package:ai_travel_planner/models/day_plan_model.dart';
import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/providers/trip_provider.dart';
import 'package:ai_travel_planner/screens/itinerary/itinerary_screen.dart';
import 'package:ai_travel_planner/screens/map/map_screen.dart';
import 'package:ai_travel_planner/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final ResponseBody Function(RequestOptions options) _handler;

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

ResponseBody _json(Object data, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

TripModel _sampleTrip() {
  return const TripModel(
    tripId: 'itinerary_fm3test1',
    destination: 'Hunza Valley, Pakistan',
    durationDays: 2,
    totalEstimatedCost: 45.0,
    currency: 'USD',
    targetBudget: 200.0,
    travelStyle: 'Moderate',
    interests: ['Historical', 'Nature'],
    days: [
      DayPlanModel(
        dayNumber: 1,
        title: 'Karimabad Forts',
        totalDistanceKm: 2.1,
        activities: [
          ActivityModel(
            activityId: 'act_01',
            timeSlot: 'Morning',
            title: 'Visit Baltit Fort',
            description: 'Historic fort.',
            category: 'Historical',
            estimatedCost: 15.0,
            latitude: 36.3256,
            longitude: 74.6678,
            verified: true,
          ),
          ActivityModel(
            activityId: 'act_02',
            timeSlot: 'Afternoon',
            title: 'Explore Altit Fort',
            description: 'Ancient fort & garden.',
            category: 'Historical',
            estimatedCost: 10.0,
            latitude: 36.3144,
            longitude: 74.6819,
            verified: true,
          ),
          ActivityModel(
            activityId: 'act_03',
            timeSlot: 'Evening',
            title: 'Hidden Local Tea Spot',
            description: 'No GPS coordinates yet.',
            category: 'Food',
            estimatedCost: 20.0,
            verified: false,
          ),
        ],
      ),
      DayPlanModel(
        dayNumber: 2,
        title: 'Relaxed Unmapped Day',
        activities: [
          ActivityModel(
            activityId: 'act_04',
            timeSlot: 'Morning',
            title: 'Village Walk',
            description: 'No GPS coordinates.',
            category: 'Culture',
            estimatedCost: 0.0,
            verified: false,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('External Maps Navigation Launcher (MFR-09)', () {
    test('builds Google Maps URI on Android and Apple Maps URI on iOS', () {
      final androidUri = MapLauncher.buildExternalMapsUri(
        latitude: 36.3256,
        longitude: 74.6678,
        label: 'Baltit Fort',
        platform: TargetPlatform.android,
      );
      expect(androidUri.host, 'www.google.com');
      expect(androidUri.path, '/maps/search/');
      expect(androidUri.queryParameters['query'], '36.325600,74.667800');

      final iosUri = MapLauncher.buildExternalMapsUri(
        latitude: 36.3256,
        longitude: 74.6678,
        label: 'Baltit Fort',
        platform: TargetPlatform.iOS,
      );
      expect(iosUri.host, 'maps.apple.com');
      expect(iosUri.queryParameters['daddr'], '36.325600,74.667800');
      expect(iosUri.queryParameters['q'], 'Baltit Fort');
    });
  });

  group('ApiService.regenerateSlot & TripProvider Customization (MFR-07)', () {
    test('regenerateSlot parses replacement ActivityModel and updates cost', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.httpClientAdapter = _FakeAdapter((options) {
        expect(options.path, '/api/v1/itinerary/regenerate-slot');
        return _json({
          'activity_id': 'act_02',
          'time_slot': 'Afternoon',
          'title': 'Eagle Nest Viewpoint',
          'description': 'Panoramic sunset viewpoint.',
          'category': 'Photography',
          'estimated_cost': 25.0,
          'latitude': 36.3202,
          'longitude': 74.6897,
          'verified': true,
        });
      });

      final provider = TripProvider(apiService: ApiService(dio: dio));
      final trip = _sampleTrip();
      provider.selectTrip(trip);

      final replacement = await provider.regenerateActivitySlot(
        trip: trip,
        dayNumber: 1,
        activity: trip.days.first.activities[1],
        userNote: 'Prefer a viewpoint',
      );

      expect(replacement, isNotNull);
      expect(replacement!.title, 'Eagle Nest Viewpoint');
      expect(replacement.verified, isTrue);
      expect(provider.activeTrip!.days.first.activities[1].title, 'Eagle Nest Viewpoint');
      // 15 + 25 + 20 = 60.0
      expect(provider.activeTrip!.totalEstimatedCost, 60.0);
    });

    test('updateActivityNotes and deleteActivity update state and cost', () {
      final provider = TripProvider();
      final trip = _sampleTrip();
      provider.selectTrip(trip);

      provider.updateActivityNotes(
        tripId: trip.tripId,
        dayNumber: 1,
        activityId: 'act_01',
        notes: 'Arrive before 10 AM',
      );
      expect(
        provider.activeTrip!.days.first.activities.first.notes,
        'Arrive before 10 AM',
      );

      provider.deleteActivity(
        tripId: trip.tripId,
        dayNumber: 1,
        activityId: 'act_03',
      );
      expect(provider.activeTrip!.days.first.activities.length, 2);
      // 15 + 10 = 25.0
      expect(provider.activeTrip!.totalEstimatedCost, 25.0);
    });
  });

  group('MapScreen & SlotEditorSheet Widget Tests', () {
    testWidgets(
      'MapScreen shows numbered markers for verified pins, polyline, preview card, and empty fallback',
      (tester) async {
        final trip = _sampleTrip();

        await tester.pumpWidget(
          MaterialApp(
            home: MapScreen(
              trip: trip,
              initialDayNumber: 1,
              showTileLayer: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Day 1 has 2 located activities (act_01, act_02) and skips unverified act_03.
        final markerLayer =
            tester.widget<MarkerLayer>(find.byType(MarkerLayer));
        expect(markerLayer.markers.length, 2);
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('3'), findsNothing);

        // Polyline connects the 2 verified points in order.
        final polylineLayer =
            tester.widget<PolylineLayer>(find.byType(PolylineLayer));
        expect(polylineLayer.polylines.first.points, [
          const LatLng(36.3256, 74.6678),
          const LatLng(36.3144, 74.6819),
        ]);

        // Tapping marker 1 displays preview card with Navigate button.
        await tester.tap(find.text('1'));
        await tester.pumpAndSettle();
        expect(find.text('Visit Baltit Fort'), findsOneWidget);
        expect(find.text('Navigate'), findsOneWidget);

        // Switching to Day 2 (zero verified GPS) shows friendly empty fallback.
        await tester.tap(find.text('Day 2'));
        await tester.pumpAndSettle();
        expect(
          find.text('No verified GPS pins for Day 2'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ItineraryScreen opens SlotEditorSheet for notes, AI regenerate, and delete',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
        dio.httpClientAdapter = _FakeAdapter((_) {
          return _json({
            'activity_id': 'act_01',
            'time_slot': 'Morning',
            'title': 'Duikar Sunrise Point',
            'description': 'Morning valley panorama.',
            'category': 'Nature',
            'estimated_cost': 5.0,
            'latitude': 36.3202,
            'longitude': 74.6897,
            'verified': true,
          });
        });

        final provider = TripProvider(apiService: ApiService(dio: dio));
        final trip = _sampleTrip();
        provider.selectTrip(trip);

        await tester.pumpWidget(
          ChangeNotifierProvider<TripProvider>.value(
            value: provider,
            child: MaterialApp(home: ItineraryScreen(trip: trip)),
          ),
        );

        // Map icon button is visible in AppBar.
        expect(find.byTooltip('Open Map View'), findsOneWidget);

        // Tap first activity card -> opens SlotEditorSheet -> save notes.
        await tester.tap(find.text('Visit Baltit Fort'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Personal Notes'),
          'Carry cash for tickets',
        );
        await tester.tap(find.text('Save Notes'));
        await tester.pumpAndSettle();
        expect(find.text('Carry cash for tickets'), findsOneWidget);

        // Reopen sheet and tap Regenerate Slot -> swaps card title in place!
        await tester.tap(find.text('Visit Baltit Fort'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Regenerate Slot'));
        await tester.pumpAndSettle();
        expect(find.text('Duikar Sunrise Point'), findsOneWidget);
        expect(find.text('Visit Baltit Fort'), findsNothing);

        // Reopen sheet and delete activity.
        await tester.tap(find.text('Duikar Sunrise Point'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete Activity'));
        await tester.pumpAndSettle();
        expect(find.text('Duikar Sunrise Point'), findsNothing);
      },
    );
  });
}
