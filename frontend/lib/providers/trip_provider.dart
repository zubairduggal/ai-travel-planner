import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/activity_model.dart';
import '../models/day_plan_model.dart';
import '../models/packing_item_model.dart';
import '../models/trip_model.dart';
import '../models/weather_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Manages trips, offline persistence, weather cache, packing checklists, and slot edits.
class TripProvider extends ChangeNotifier {
  TripProvider({
    ApiService? apiService,
    StorageService? storage,
  })  : _apiService = apiService ?? ApiService(),
        _storage = storage ?? InMemoryStorageService();

  final ApiService _apiService;
  final StorageService _storage;
  final List<TripModel> _trips = [];
  final Map<String, WeatherForecastModel> _weatherByTrip = {};
  final Map<String, bool> _weatherLoading = {};
  final Map<String, List<PackingItemModel>> _packingByTrip = {};

  TripModel? _activeTrip;
  bool _isGenerating = false;
  String? _regeneratingActivityId;
  String? _errorMessage;
  String? _errorCode;
  String? _lastCacheStatus;
  TripRequestModel? _lastRequest;
  CancelToken? _cancelToken;

  List<TripModel> get trips => List.unmodifiable(_trips);
  TripModel? get activeTrip => _activeTrip;
  bool get isGenerating => _isGenerating;
  String? get regeneratingActivityId => _regeneratingActivityId;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  String? get lastCacheStatus => _lastCacheStatus;
  TripRequestModel? get lastRequest => _lastRequest;

  WeatherForecastModel? weatherForTrip(String tripId) => _weatherByTrip[tripId];
  bool isWeatherLoading(String tripId) => _weatherLoading[tripId] ?? false;

  List<PackingItemModel> packingListForTrip(String tripId) =>
      List.unmodifiable(_packingByTrip[tripId] ?? const []);

  /// Loads previously saved trips from local offline storage on startup.
  Future<void> loadSavedTrips() async {
    final saved = await _storage.loadTrips();
    _trips
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  Future<TripModel?> generateTrip(TripRequestModel request) async {
    _cancelToken?.cancel('Superseded by new trip request');
    _cancelToken = CancelToken();

    _lastRequest = request;
    _isGenerating = true;
    _errorMessage = null;
    _errorCode = null;
    _lastCacheStatus = null;
    notifyListeners();

    try {
      final result = await _apiService.generateItinerary(
        request,
        cancelToken: _cancelToken,
      );
      _upsertTrip(result.trip);
      await _storage.saveTrip(result.trip);
      _lastCacheStatus = result.cacheStatus;
      _isGenerating = false;
      notifyListeners();
      return result.trip;
    } on ApiException catch (e) {
      _isGenerating = false;
      if (!e.isCancelled) {
        _errorCode = e.code;
        _errorMessage = e.message;
      }
      notifyListeners();
      return null;
    } catch (_) {
      _isGenerating = false;
      _errorCode = 'UNKNOWN';
      _errorMessage = 'Something went wrong while generating your trip.';
      notifyListeners();
      return null;
    }
  }

  /// Deletes a saved trip and its local expenses/checklists/weather cache.
  Future<void> deleteTrip(String tripId) async {
    await _storage.deleteTrip(tripId);
    _trips.removeWhere((t) => t.tripId == tripId);
    _weatherByTrip.remove(tripId);
    _packingByTrip.remove(tripId);
    if (_activeTrip?.tripId == tripId) {
      _activeTrip = _trips.isNotEmpty ? _trips.first : null;
    }
    notifyListeners();
  }

  /// Updates or clears local user notes on a single activity (MFR-07).
  void updateActivityNotes({
    required String tripId,
    required int dayNumber,
    required String activityId,
    required String? notes,
  }) {
    final trimmed = notes?.trim();
    _mutateDayActivities(tripId, dayNumber, (activities) {
      return activities.map((act) {
        if (act.activityId != activityId) return act;
        return act.copyWith(
          notes: trimmed,
          clearNotes: trimmed == null || trimmed.isEmpty,
        );
      }).toList();
    });
  }

  /// Deletes an activity from a day and recalculates total trip cost (MFR-07).
  void deleteActivity({
    required String tripId,
    required int dayNumber,
    required String activityId,
  }) {
    _mutateDayActivities(tripId, dayNumber, (activities) {
      return activities.where((act) => act.activityId != activityId).toList();
    });
  }

  /// Calls backend `/api/v1/itinerary/regenerate-slot` and swaps the activity.
  Future<ActivityModel?> regenerateActivitySlot({
    required TripModel trip,
    required int dayNumber,
    required ActivityModel activity,
    String? userNote,
  }) async {
    _regeneratingActivityId = activity.activityId;
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();

    final otherCosts = trip.totalEstimatedCost - activity.estimatedCost;
    final budgetRemaining = (trip.effectiveBudget - otherCosts).clamp(
      0.0,
      1000000.0,
    );

    final req = RegenerateSlotRequestModel(
      destination: trip.destination,
      dayNumber: dayNumber,
      timeSlot: activity.timeSlot,
      budgetRemaining: budgetRemaining,
      currency: trip.currency,
      interests: trip.interests.isEmpty
          ? const ['Sightseeing', 'Local Food']
          : trip.interests,
      travelStyle: trip.travelStyle,
      existingActivityTitles: trip.allActivityTitles,
      activityId: activity.activityId,
      userNote: userNote,
    );

    try {
      final replacement = await _apiService.regenerateSlot(req);
      _mutateDayActivities(trip.tripId, dayNumber, (activities) {
        return activities
            .map((a) => a.activityId == activity.activityId ? replacement : a)
            .toList();
      });
      _regeneratingActivityId = null;
      notifyListeners();
      return replacement;
    } on ApiException catch (e) {
      _regeneratingActivityId = null;
      _errorCode = e.code;
      _errorMessage = e.message;
      notifyListeners();
      return null;
    } catch (_) {
      _regeneratingActivityId = null;
      _errorCode = 'UNKNOWN';
      _errorMessage = 'Could not regenerate this activity right now.';
      notifyListeners();
      return null;
    }
  }

  /// Loads cached weather first, then refreshes live from backend `/api/v1/weather`.
  Future<void> loadWeatherForTrip(TripModel trip) async {
    final cached = await _storage.loadWeather(trip.tripId);
    if (cached != null) {
      _weatherByTrip[trip.tripId] = cached;
      notifyListeners();
    }

    // Find first verified coordinate in the trip.
    ActivityModel? located;
    for (final day in trip.days) {
      for (final act in day.activities) {
        if (act.hasCoordinates) {
          located = act;
          break;
        }
      }
      if (located != null) break;
    }
    if (located == null) return;

    _weatherLoading[trip.tripId] = true;
    notifyListeners();

    try {
      final forecast = await _apiService.getWeather(
        latitude: located.latitude!,
        longitude: located.longitude!,
        days: trip.durationDays.clamp(1, 16),
      );
      _weatherByTrip[trip.tripId] = forecast;
      await _storage.saveWeather(trip.tripId, forecast);
    } catch (_) {
      // Offline / Airplane Mode: gracefully retain cached weather if present.
    } finally {
      _weatherLoading[trip.tripId] = false;
      notifyListeners();
    }
  }

  /// Loads or initializes the editable packing checklist for a trip.
  Future<void> loadPackingList(String tripId) async {
    final existing = await _storage.loadPackingList(tripId);
    final items = existing ?? PackingItemModel.defaultItems();
    _packingByTrip[tripId] = items;
    if (existing == null) {
      await _storage.savePackingList(tripId, items);
    }
    notifyListeners();
  }

  Future<void> togglePackingItem(String tripId, String itemId) async {
    final current = List<PackingItemModel>.from(
      _packingByTrip[tripId] ?? PackingItemModel.defaultItems(),
    );
    final updated = current
        .map(
          (item) => item.id == itemId
              ? item.copyWith(isPacked: !item.isPacked)
              : item,
        )
        .toList();
    _packingByTrip[tripId] = updated;
    await _storage.savePackingList(tripId, updated);
    notifyListeners();
  }

  Future<void> addPackingItem(
    String tripId,
    String title, {
    String category = 'Essentials',
  }) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    final current = List<PackingItemModel>.from(
      _packingByTrip[tripId] ?? PackingItemModel.defaultItems(),
    );
    current.add(
      PackingItemModel(
        id: 'pack_${DateTime.now().microsecondsSinceEpoch}',
        title: clean,
        category: category,
      ),
    );
    _packingByTrip[tripId] = current;
    await _storage.savePackingList(tripId, current);
    notifyListeners();
  }

  Future<void> removePackingItem(String tripId, String itemId) async {
    final current = List<PackingItemModel>.from(_packingByTrip[tripId] ?? []);
    current.removeWhere((item) => item.id == itemId);
    _packingByTrip[tripId] = current;
    await _storage.savePackingList(tripId, current);
    notifyListeners();
  }

  void _mutateDayActivities(
    String tripId,
    int dayNumber,
    List<ActivityModel> Function(List<ActivityModel> current) transform,
  ) {
    final existing = _findTrip(tripId);
    if (existing == null) return;

    final updatedDays = <DayPlanModel>[];
    for (final day in existing.days) {
      if (day.dayNumber == dayNumber) {
        updatedDays.add(day.copyWith(activities: transform(day.activities)));
      } else {
        updatedDays.add(day);
      }
    }

    final recalculatedTotal = double.parse(
      updatedDays
          .fold<double>(0.0, (sum, d) => sum + d.dayEstimatedCost)
          .toStringAsFixed(2),
    );

    final updatedTrip = existing.copyWith(
      days: updatedDays,
      totalEstimatedCost: recalculatedTotal,
    );
    _upsertTrip(updatedTrip);
    unawaited(_storage.saveTrip(updatedTrip));
    notifyListeners();
  }

  TripModel? _findTrip(String tripId) {
    if (_activeTrip?.tripId == tripId) return _activeTrip;
    for (final trip in _trips) {
      if (trip.tripId == tripId) return trip;
    }
    return null;
  }

  void _upsertTrip(TripModel trip) {
    _activeTrip = trip;
    final idx = _trips.indexWhere((t) => t.tripId == trip.tripId);
    if (idx >= 0) {
      _trips[idx] = trip;
    } else {
      _trips.insert(0, trip);
    }
  }

  void cancelGeneration() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('Cancelled by user');
    }
    _isGenerating = false;
    notifyListeners();
  }

  void selectTrip(TripModel trip) {
    _activeTrip = trip;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    _errorCode = null;
    notifyListeners();
  }

  void clearInMemory() {
    _trips.clear();
    _weatherByTrip.clear();
    _packingByTrip.clear();
    _activeTrip = null;
    notifyListeners();
  }
}
