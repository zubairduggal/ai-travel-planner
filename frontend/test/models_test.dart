import 'package:ai_travel_planner/core/utils/formatters.dart';
import 'package:ai_travel_planner/main.dart';
import 'package:ai_travel_planner/models/activity_model.dart';
import 'package:ai_travel_planner/models/day_plan_model.dart';
import 'package:ai_travel_planner/models/expense_model.dart';
import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/widgets/custom_button.dart';
import 'package:ai_travel_planner/widgets/custom_text_field.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Core Data Models (FastAPI v1.0.1 contract)', () {
    test('TripModel parses FastAPI PRD JSON and roundtrips cleanly', () {
      final apiJson = <String, dynamic>{
        'trip_id': 'itinerary_9f8a2b1c',
        'destination': 'Hunza Valley, Pakistan',
        'duration_days': 5,
        'total_estimated_cost': 420.0,
        'currency': 'USD',
        'days': [
          {
            'day_number': 1,
            'title': 'Arrival & Karimabad Exploration',
            'total_distance_km': 15.8,
            'feasible': true,
            'distance_warnings': <String>[],
            'activities': [
              {
                'activity_id': 'act_01',
                'time_slot': 'Morning',
                'title': 'Visit Baltit Fort',
                'description': 'Explore the 700-year-old historic fort.',
                'category': 'Historical',
                'estimated_cost': 15.0,
                'latitude': 36.3256,
                'longitude': 74.6678,
                'verified': true,
              },
              {
                'activity_id': 'act_02',
                'time_slot': 'Evening',
                'title': 'Local Cafe Dinner',
                'description': 'Unverified cozy local spot.',
                'category': 'Food',
                'estimated_cost': 12.0,
                'latitude': null,
                'longitude': null,
                'verified': false,
              },
            ],
          },
        ],
      };

      final trip = TripModel.fromJson(apiJson);
      expect(trip.tripId, 'itinerary_9f8a2b1c');
      expect(trip.destination, 'Hunza Valley, Pakistan');
      expect(trip.durationDays, 5);
      expect(trip.totalEstimatedCost, 420.0);
      expect(trip.days.length, 1);

      final day1 = trip.days.first;
      expect(day1.totalDistanceKm, 15.8);
      expect(day1.feasible, isTrue);
      expect(day1.dayEstimatedCost, 27.0);

      final verifiedAct = day1.activities[0];
      expect(verifiedAct.hasCoordinates, isTrue);
      expect(verifiedAct.verified, isTrue);
      expect(verifiedAct.latitude, 36.3256);

      final unverifiedAct = day1.activities[1];
      expect(unverifiedAct.hasCoordinates, isFalse);
      expect(unverifiedAct.verified, isFalse);

      // Roundtrip JSON serialization preserves fields.
      final roundtrip = TripModel.fromJson(trip.toJson());
      expect(roundtrip.tripId, trip.tripId);
      expect(roundtrip.allActivityTitles, ['Visit Baltit Fort', 'Local Cafe Dinner']);
    });

    test('ActivityModel copyWith updates and clears local notes', () {
      const act = ActivityModel(
        activityId: 'act_01',
        timeSlot: 'Morning',
        title: 'Visit Baltit Fort',
        description: 'Historic fort',
        category: 'Historical',
        estimatedCost: 15.0,
      );

      final withNotes = act.copyWith(notes: 'Bring camera lens');
      expect(withNotes.notes, 'Bring camera lens');

      final cleared = withNotes.copyWith(clearNotes: true);
      expect(cleared.notes, isNull);
    });

    test('TripRequestModel serializes ISO dates and inclusive duration', () {
      final req = TripRequestModel(
        destination: '  Hunza Valley, Pakistan  ',
        startDate: DateTime(2026, 6, 10),
        endDate: DateTime(2026, 6, 14),
        budget: 500.0,
        currency: 'usd',
        interests: const ['Nature', 'Hiking'],
        travelStyle: 'Moderate',
      );

      expect(req.durationDays, 5);
      final json = req.toJson();
      expect(json['destination'], 'Hunza Valley, Pakistan');
      expect(json['start_date'], '2026-06-10');
      expect(json['end_date'], '2026-06-14');
      expect(json['currency'], 'USD');
      expect(json['travel_style'], 'Moderate');
    });

    test('ExpenseModel and formatters work accurately', () {
      final expense = ExpenseModel(
        expenseId: 'exp_1',
        tripId: 'itinerary_9f8a2b1c',
        title: 'Apricot Soup Lunch',
        amount: 14.5,
        currency: 'USD',
        category: 'Food',
        date: DateTime(2026, 6, 10),
      );
      final decoded = ExpenseModel.fromJson(expense.toJson());
      expect(decoded.expenseId, 'exp_1');
      expect(decoded.amount, 14.5);

      expect(AppFormatters.formatCurrency(420, 'USD'), r'$420');
      expect(AppFormatters.formatCurrency(1500, 'PKR'), 'Rs 1,500');
      expect(AppFormatters.formatDistance(15.84), '15.8 km');
      expect(AppFormatters.formatDistance(null), 'Distance unavailable');
    });

    test('DayPlanModel defaults gracefully on minimal JSON', () {
      final day = DayPlanModel.fromJson({'day_number': 2});
      expect(day.dayNumber, 2);
      expect(day.activities, isEmpty);
      expect(day.feasible, isTrue);
    });
  });

  group('FM1 UI Shell & Reusable Widgets', () {
    testWidgets('Guest Mode onboarding navigates into 3-tab bottom shell', (
      tester,
    ) async {
      await tester.pumpWidget(const AITravelPlannerApp());

      expect(find.text('AI Travel Planner'), findsOneWidget);
      expect(find.text('Explore as Guest'), findsOneWidget);

      await tester.tap(find.text('Explore as Guest'));
      await tester.pumpAndSettle();

      // Opens on Create Trip tab with all 3 NavigationBar destinations visible.
      expect(find.text('My Trips'), findsOneWidget);
      expect(find.text('Create Trip'), findsWidgets);
      expect(find.text('Profile'), findsOneWidget);

      // Switch to Profile tab and toggle Dark Mode.
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Guest Traveler'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);

      // Switch to My Trips tab.
      await tester.tap(find.text('My Trips'));
      await tester.pumpAndSettle();
      expect(find.text('No trips planned yet'), findsOneWidget);
    });

    testWidgets('CustomButton and CustomTextField render and validate', (
      tester,
    ) async {
      final controller = TextEditingController();
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CustomTextField(
                  controller: controller,
                  label: 'Destination',
                  prefixIcon: Icons.place_outlined,
                ),
                CustomButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward,
                  onPressed: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'Skardu');
      expect(controller.text, 'Skardu');

      await tester.tap(find.text('Continue'));
      expect(tapped, isTrue);

      controller.dispose();
    });
  });
}
