import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/trip_model.dart';
import '../services/api_service.dart';

/// Manages trip generation, active trip state, and saved trips list.
class TripProvider extends ChangeNotifier {
  TripProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  final ApiService _apiService;
  final List<TripModel> _trips = [];

  TripModel? _activeTrip;
  bool _isGenerating = false;
  String? _errorMessage;
  String? _errorCode;
  String? _lastCacheStatus;
  TripRequestModel? _lastRequest;
  CancelToken? _cancelToken;

  List<TripModel> get trips => List.unmodifiable(_trips);
  TripModel? get activeTrip => _activeTrip;
  bool get isGenerating => _isGenerating;
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
      _activeTrip = result.trip;
      _lastCacheStatus = result.cacheStatus;

      // Insert or replace existing trip with the same ID at the top.
      _trips.removeWhere((t) => t.tripId == result.trip.tripId);
      _trips.insert(0, result.trip);

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
