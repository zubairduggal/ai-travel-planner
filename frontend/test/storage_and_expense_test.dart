import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_travel_planner/models/activity_model.dart';
import 'package:ai_travel_planner/models/day_plan_model.dart';
import 'package:ai_travel_planner/models/expense_model.dart';
import 'package:ai_travel_planner/models/packing_item_model.dart';
import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/models/weather_model.dart';
import 'package:ai_travel_planner/providers/expense_provider.dart';
import 'package:ai_travel_planner/screens/expense/expense_screen.dart';
import 'package:ai_travel_planner/services/currency_service.dart';
import 'package:ai_travel_planner/services/storage_service.dart';
import 'package:ai_travel_planner/widgets/budget_progress_bar.dart';
import 'package:ai_travel_planner/widgets/packing_checklist.dart';
import 'package:ai_travel_planner/widgets/weather_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);

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

TripModel _sampleTrip() {
  return TripModel(
    tripId: 'itinerary_offline1',
    destination: 'Hunza Valley, Pakistan',
    durationDays: 2,
    totalEstimatedCost: 80.0,
    currency: 'USD',
    targetBudget: 200.0,
    travelStyle: 'Moderate',
    interests: const ['Nature', 'Hiking'],
    createdAt: DateTime.utc(2026, 6, 1),
    days: const [
      DayPlanModel(
        dayNumber: 1,
        title: 'Karimabad',
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
        ],
      ),
    ],
  );
}

void main() {
  group('HiveStorageService Real Offline Disk Persistence (MFR-10)', () {
    test('persists trips, expenses, packing, weather across restart and purges cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('hive_fm4_test_');
      try {
        final storage1 = HiveStorageService();
        await storage1.init(testPath: tempDir.path);

        final trip = _sampleTrip();
        await storage1.saveTrip(trip);
        await storage1.saveExpense(
          ExpenseModel(
            expenseId: 'exp_1',
            tripId: trip.tripId,
            title: 'Fort Ticket',
            amount: 15.0,
            currency: 'USD',
            category: 'Activities',
            date: DateTime.utc(2026, 6, 10),
          ),
        );
        await storage1.savePackingList(trip.tripId, [
          const PackingItemModel(id: 'p1', title: 'Camera', isPacked: true),
        ]);
        await storage1.saveWeather(
          trip.tripId,
          WeatherForecastModel(
            latitude: 36.32,
            longitude: 74.67,
            timezone: 'Asia/Karachi',
            daily: [
              DailyWeatherModel(
                date: DateTime(2026, 6, 10),
                tempMaxC: 24.0,
                tempMinC: 11.0,
                weatherCode: 0,
                condition: 'Clear sky',
              ),
            ],
          ),
        );
        await storage1.saveStringPref('theme_mode', 'dark');
        await storage1.close();

        // Reopen from disk (simulating app restart in Airplane Mode).
        final storage2 = HiveStorageService();
        await storage2.init(testPath: tempDir.path);

        final loadedTrips = await storage2.loadTrips();
        expect(loadedTrips.length, 1);
        expect(loadedTrips.first.destination, 'Hunza Valley, Pakistan');

        final loadedExpenses = await storage2.loadExpenses(trip.tripId);
        expect(loadedExpenses.length, 1);
        expect(loadedExpenses.first.title, 'Fort Ticket');

        final loadedPacking = await storage2.loadPackingList(trip.tripId);
        expect(loadedPacking?.first.title, 'Camera');
        expect(loadedPacking?.first.isPacked, isTrue);

        final loadedWeather = await storage2.loadWeather(trip.tripId);
        expect(loadedWeather?.daily.first.condition, 'Clear sky');
        expect(await storage2.loadStringPref('theme_mode'), 'dark');

        // Cascade delete removes trip + its expenses/packing/weather.
        await storage2.deleteTrip(trip.tripId);
        expect(await storage2.loadTrips(), isEmpty);
        expect(await storage2.loadExpenses(trip.tripId), isEmpty);
        expect(await storage2.loadPackingList(trip.tripId), isNull);

        // Re-add preference then test purgeAllData().
        await storage2.saveStringPref('theme_mode', 'light');
        await storage2.purgeAllData();
        expect(await storage2.loadStringPref('theme_mode'), isNull);
        await storage2.close();
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('CurrencyService & ExpenseProvider Multi-Currency Math (MFR-11)', () {
    test('refreshes live Frankfurter rates, caches them, and converts accurately', () async {
      final storage = InMemoryStorageService();
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter((options) {
        return ResponseBody.fromString(
          jsonEncode({
            'base': 'USD',
            'date': '2026-11-20',
            'rates': {'PKR': 280.0, 'EUR': 0.90, 'GBP': 0.80, 'AED': 3.67},
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final currency = CurrencyService(dio: dio, storage: storage);
      await currency.refreshRates();

      expect(currency.usingLiveRates, isTrue);
      // 2800 PKR / 280 = 10.00 USD
      expect(
        currency.convert(amount: 2800, fromCurrency: 'PKR', toCurrency: 'USD'),
        10.0,
      );
      // 90 EUR -> 100 USD
      expect(
        currency.convert(amount: 90, fromCurrency: 'EUR', toCurrency: 'USD'),
        100.0,
      );
      // Cached in storage for offline mode.
      final cached = await storage.loadExchangeRates();
      expect(cached?['PKR'], 280.0);
    });

    test('falls back to bundled offline rates when network fails', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) => handler.reject(
            DioException.connectionError(
              requestOptions: opts,
              reason: 'Airplane mode',
            ),
          ),
        ),
      );
      final currency = CurrencyService(dio: dio);
      await currency.refreshRates();

      expect(currency.usingLiveRates, isFalse);
      final converted = currency.convert(
        amount: 278.5,
        fromCurrency: 'PKR',
        toCurrency: 'USD',
      );
      expect(converted, 1.0);
    });
  });

  group('FM4 UI Widgets (ExpenseScreen, BudgetProgressBar, WeatherCard, PackingChecklist)', () {
    testWidgets('BudgetProgressBar shows Remaining and Over Budget states', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BudgetProgressBar(spent: 120, budget: 200, currency: 'USD'),
                BudgetProgressBar(spent: 250, budget: 200, currency: 'USD'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text(r'$80'), findsOneWidget);
      expect(find.text('Over Budget'), findsOneWidget);
      expect(find.text(r'$50'), findsOneWidget);
    });

    testWidgets('ExpenseScreen logs and deletes an expense via modal sheet', (
      tester,
    ) async {
      final storage = InMemoryStorageService();
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (opts, handler) => handler.reject(
            DioException.connectionError(
              requestOptions: opts,
              reason: 'Offline test',
            ),
          ),
        ),
      );
      final provider = ExpenseProvider(
        storage: storage,
        currencyService: CurrencyService(dio: dio, storage: storage),
      );
      final trip = _sampleTrip();

      await tester.pumpWidget(
        ChangeNotifierProvider<ExpenseProvider>.value(
          value: provider,
          child: MaterialApp(home: ExpenseScreen(trip: trip)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No expenses logged yet'), findsOneWidget);

      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Mountain Coffee',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '15',
      );
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(find.text('Mountain Coffee'), findsOneWidget);
      expect(provider.totalSpentForTrip(trip), 15.0);

      await tester.tap(find.byTooltip('Delete expense'));
      await tester.pumpAndSettle();
      expect(find.text('No expenses logged yet'), findsOneWidget);
    });

    testWidgets('WeatherCard and PackingChecklist render and mutate items', (
      tester,
    ) async {
      final forecast = WeatherForecastModel(
        latitude: 36.32,
        longitude: 74.67,
        timezone: 'Asia/Karachi',
        daily: [
          DailyWeatherModel(
            date: DateTime(2026, 6, 10),
            tempMaxC: 24.4,
            tempMinC: 11.2,
            weatherCode: 0,
            condition: 'Clear sky',
          ),
        ],
      );

      var items = [
        const PackingItemModel(id: '1', title: 'Passport'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: ListView(
                children: [
                  WeatherCard(forecast: forecast),
                  PackingChecklist(
                    items: items,
                    onToggle: (id) => setState(() {
                      items = items
                          .map((i) => i.id == id ? i.copyWith(isPacked: !i.isPacked) : i)
                          .toList();
                    }),
                    onAdd: (title) => setState(() {
                      items = [
                        ...items,
                        PackingItemModel(id: '2', title: title),
                      ];
                    }),
                    onRemove: (id) => setState(() {
                      items = items.where((i) => i.id != id).toList();
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Clear sky'), findsOneWidget);
      expect(find.text('24°/11°'), findsOneWidget);
      expect(find.text('0/1 packed'), findsOneWidget);

      await tester.tap(find.text('Passport'));
      await tester.pumpAndSettle();
      expect(find.text('1/1 packed'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Raincoat');
      await tester.tap(find.byTooltip('Add packing item'));
      await tester.pumpAndSettle();
      expect(find.text('Raincoat'), findsOneWidget);
      expect(find.text('1/2 packed'), findsOneWidget);
    });
  });
}
