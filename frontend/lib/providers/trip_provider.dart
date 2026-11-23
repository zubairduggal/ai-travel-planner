import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/activity_model.dart';
import '../models/day_plan_model.dart';
import '../models/trip_model.dart';
import '../services/api_service.dart';

/// Manages trip generation, active trip state, saved trips, and slot edits.
class TripProvider extends ChangeNotifier {
  TripProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  final ApiService _apiService;
  final List<TripModel> _trips = [];

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
}
