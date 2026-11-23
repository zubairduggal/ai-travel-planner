import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/expense_model.dart';
import '../models/packing_item_model.dart';
import '../models/trip_model.dart';
import '../models/weather_model.dart';

/// Local offline persistence contract (MFR-10, FM4, and FM5 Account Purge).
abstract class StorageService {
  Future<void> init({String? testPath});

  // Trips
  Future<void> saveTrip(TripModel trip);
  Future<List<TripModel>> loadTrips();
  Future<void> deleteTrip(String tripId);

  // Expenses
  Future<void> saveExpense(ExpenseModel expense);
  Future<List<ExpenseModel>> loadExpenses(String tripId);
  Future<void> deleteExpense(String expenseId);

  // Packing checklist
  Future<void> savePackingList(String tripId, List<PackingItemModel> items);
  Future<List<PackingItemModel>?> loadPackingList(String tripId);

  // Cached weather
  Future<void> saveWeather(String tripId, WeatherForecastModel forecast);
  Future<WeatherForecastModel?> loadWeather(String tripId);

  // Cached currency exchange rates (base = USD)
  Future<void> saveExchangeRates(Map<String, double> rates);
  Future<Map<String, double>?> loadExchangeRates();

  // Preferences (theme mode, guest flag)
  Future<void> saveStringPref(String key, String value);
  Future<String?> loadStringPref(String key);

  /// Permanently wipes all local trips, expenses, checklists, caches, and prefs.
  Future<void> purgeAllData();

  Future<void> close();
}

/// Production Hive CE implementation (Android, iOS, and Chrome Web).
class HiveStorageService implements StorageService {
  static const String _tripsBoxName = 'trips_box';
  static const String _expensesBoxName = 'expenses_box';
  static const String _packingBoxName = 'packing_box';
  static const String _weatherBoxName = 'weather_box';
  static const String _ratesBoxName = 'rates_box';
  static const String _prefsBoxName = 'prefs_box';

  bool _initialized = false;
  late Box<String> _tripsBox;
  late Box<String> _expensesBox;
  late Box<String> _packingBox;
  late Box<String> _weatherBox;
  late Box<String> _ratesBox;
  late Box<String> _prefsBox;

  @override
  Future<void> init({String? testPath}) async {
    if (_initialized) return;
    if (testPath != null) {
      Hive.init(testPath);
    } else if (kIsWeb) {
      Hive.init(null);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
    }

    _tripsBox = await Hive.openBox<String>(_tripsBoxName);
    _expensesBox = await Hive.openBox<String>(_expensesBoxName);
    _packingBox = await Hive.openBox<String>(_packingBoxName);
    _weatherBox = await Hive.openBox<String>(_weatherBoxName);
    _ratesBox = await Hive.openBox<String>(_ratesBoxName);
    _prefsBox = await Hive.openBox<String>(_prefsBoxName);
    _initialized = true;
  }

  @override
  Future<void> saveTrip(TripModel trip) async {
    await _tripsBox.put(trip.tripId, jsonEncode(trip.toJson()));
  }

  @override
  Future<List<TripModel>> loadTrips() async {
    final trips = <TripModel>[];
    for (final raw in _tripsBox.values) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        trips.add(TripModel.fromJson(decoded));
      } catch (_) {
        // Ignore corrupted entries safely.
      }
    }
    trips.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return trips;
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    await _tripsBox.delete(tripId);
    await _packingBox.delete(tripId);
    await _weatherBox.delete(tripId);

    // Cascade-delete expenses belonging to this trip.
    final expenseKeysToDelete = <dynamic>[];
    for (final key in _expensesBox.keys) {
      final raw = _expensesBox.get(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['trip_id'] == tripId) {
          expenseKeysToDelete.add(key);
        }
      } catch (_) {}
    }
    await _expensesBox.deleteAll(expenseKeysToDelete);
  }

  @override
  Future<void> saveExpense(ExpenseModel expense) async {
    await _expensesBox.put(expense.expenseId, jsonEncode(expense.toJson()));
  }

  @override
  Future<List<ExpenseModel>> loadExpenses(String tripId) async {
    final result = <ExpenseModel>[];
    for (final raw in _expensesBox.values) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final expense = ExpenseModel.fromJson(decoded);
        if (expense.tripId == tripId) {
          result.add(expense);
        }
      } catch (_) {}
    }
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  @override
  Future<void> deleteExpense(String expenseId) async {
    await _expensesBox.delete(expenseId);
  }

  @override
  Future<void> savePackingList(
    String tripId,
    List<PackingItemModel> items,
  ) async {
    await _packingBox.put(
      tripId,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }

  @override
  Future<List<PackingItemModel>?> loadPackingList(String tripId) async {
    final raw = _packingBox.get(tripId);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(PackingItemModel.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveWeather(String tripId, WeatherForecastModel forecast) async {
    await _weatherBox.put(tripId, jsonEncode(forecast.toJson()));
  }

  @override
  Future<WeatherForecastModel?> loadWeather(String tripId) async {
    final raw = _weatherBox.get(tripId);
    if (raw == null) return null;
    try {
      return WeatherForecastModel.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveExchangeRates(Map<String, double> rates) async {
    await _ratesBox.put('usd_rates', jsonEncode(rates));
  }

  @override
  Future<Map<String, double>?> loadExchangeRates() async {
    final raw = _ratesBox.get('usd_rates');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveStringPref(String key, String value) async {
    await _prefsBox.put(key, value);
  }

  @override
  Future<String?> loadStringPref(String key) async {
    return _prefsBox.get(key);
  }

  @override
  Future<void> purgeAllData() async {
    await Future.wait([
      _tripsBox.clear(),
      _expensesBox.clear(),
      _packingBox.clear(),
      _weatherBox.clear(),
      _ratesBox.clear(),
      _prefsBox.clear(),
    ]);
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;
    await Hive.close();
    _initialized = false;
  }
}

/// Fast in-memory implementation for isolated unit & widget tests.
class InMemoryStorageService implements StorageService {
  final Map<String, TripModel> _trips = {};
  final Map<String, ExpenseModel> _expenses = {};
  final Map<String, List<PackingItemModel>> _packing = {};
  final Map<String, WeatherForecastModel> _weather = {};
  Map<String, double>? _rates;
  final Map<String, String> _prefs = {};

  @override
  Future<void> init({String? testPath}) async {}

  @override
  Future<void> saveTrip(TripModel trip) async => _trips[trip.tripId] = trip;

  @override
  Future<List<TripModel>> loadTrips() async => _trips.values.toList();

  @override
  Future<void> deleteTrip(String tripId) async {
    _trips.remove(tripId);
    _packing.remove(tripId);
    _weather.remove(tripId);
    _expenses.removeWhere((_, e) => e.tripId == tripId);
  }

  @override
  Future<void> saveExpense(ExpenseModel expense) async =>
      _expenses[expense.expenseId] = expense;

  @override
  Future<List<ExpenseModel>> loadExpenses(String tripId) async =>
      _expenses.values.where((e) => e.tripId == tripId).toList();

  @override
  Future<void> deleteExpense(String expenseId) async =>
      _expenses.remove(expenseId);

  @override
  Future<void> savePackingList(
    String tripId,
    List<PackingItemModel> items,
  ) async =>
      _packing[tripId] = List.of(items);

  @override
  Future<List<PackingItemModel>?> loadPackingList(String tripId) async =>
      _packing[tripId];

  @override
  Future<void> saveWeather(String tripId, WeatherForecastModel forecast) async =>
      _weather[tripId] = forecast;

  @override
  Future<WeatherForecastModel?> loadWeather(String tripId) async =>
      _weather[tripId];

  @override
  Future<void> saveExchangeRates(Map<String, double> rates) async =>
      _rates = Map.of(rates);

  @override
  Future<Map<String, double>?> loadExchangeRates() async => _rates;

  @override
  Future<void> saveStringPref(String key, String value) async =>
      _prefs[key] = value;

  @override
  Future<String?> loadStringPref(String key) async => _prefs[key];

  @override
  Future<void> purgeAllData() async {
    _trips.clear();
    _expenses.clear();
    _packing.clear();
    _weather.clear();
    _rates = null;
    _prefs.clear();
  }

  @override
  Future<void> close() async {}
}
