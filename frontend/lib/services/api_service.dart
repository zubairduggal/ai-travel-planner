import 'package:dio/dio.dart';

import '../core/constants/api_constants.dart';
import '../models/trip_model.dart';

/// Structured error thrown by [ApiService] matching our FastAPI error envelope.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.isCancelled = false,
  });

  final String code;
  final String message;
  final int? statusCode;
  final bool isCancelled;

  @override
  String toString() => 'ApiException($code, status=$statusCode): $message';
}

/// Result wrapper carrying the parsed [TripModel] and `X-Cache` header status.
class GenerateItineraryResult {
  const GenerateItineraryResult({
    required this.trip,
    this.cacheStatus,
  });

  final TripModel trip;
  final String? cacheStatus;

  bool get wasCached => cacheStatus?.toUpperCase() == 'HIT';
}

/// REST client communicating with the Python FastAPI backend via Dio.
class ApiService {
  ApiService({
    Dio? dio,
    String? baseUrl,
    String? apiKey,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? ApiConstants.baseUrl,
                connectTimeout: ApiConstants.connectTimeout,
                receiveTimeout: ApiConstants.receiveTimeout,
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  if ((apiKey ?? ApiConstants.apiKey).isNotEmpty)
                    'X-API-Key': apiKey ?? ApiConstants.apiKey,
                },
              ),
            );

  final Dio _dio;

  /// Checks `GET /api/v1/health` and returns true when server status is "ok".
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConstants.healthEndpoint,
      );
      return response.statusCode == 200 && response.data?['status'] == 'ok';
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Calls `POST /api/v1/itinerary/generate` and enriches the returned
  /// [TripModel] with client request metadata for budget/offline views.
  Future<GenerateItineraryResult> generateItinerary(
    TripRequestModel request, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.generateItineraryEndpoint,
        data: request.toJson(),
        cancelToken: cancelToken,
      );
      final data = response.data;
      if (data == null) {
        throw const ApiException(
          code: 'EMPTY_RESPONSE',
          message: 'Server returned an empty itinerary response.',
        );
      }
      final parsed = TripModel.fromJson(data).copyWith(
        startDate: request.startDate,
        endDate: request.endDate,
        targetBudget: request.budget,
        travelStyle: request.travelStyle,
        interests: request.interests,
        createdAt: DateTime.now().toUtc(),
      );
      final cacheHeader = response.headers.value('x-cache');
      return GenerateItineraryResult(trip: parsed, cacheStatus: cacheHeader);
    } on DioException catch (e) {
      throw _mapDioError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        code: 'PARSE_ERROR',
        message: 'Could not read the itinerary returned by the server: $e',
      );
    }
  }

  ApiException _mapDioError(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return const ApiException(
        code: 'CANCELLED',
        message: 'Itinerary generation was cancelled.',
        isCancelled: true,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        code: 'AI_TIMEOUT',
        message: 'The AI planner took too long to respond. Please tap Retry.',
        statusCode: 504,
      );
    }

    if (e.type == DioExceptionType.connectionError) {
      return const ApiException(
        code: 'NETWORK_ERROR',
        message:
            'Cannot reach the travel server. Check your internet connection '
            'or make sure the backend is running.',
      );
    }

    final statusCode = e.response?.statusCode;
    final body = e.response?.data;

    if (body is Map<String, dynamic>) {
      final errObj = body['error'];
      if (errObj is Map<String, dynamic>) {
        final code = errObj['code'] as String? ?? 'API_ERROR';
        final rawMessage =
            errObj['message'] as String? ?? 'Request failed.';
        return ApiException(
          code: code,
          message: _friendlyMessage(code, rawMessage, statusCode),
          statusCode: statusCode,
        );
      }

      // FastAPI 422 validation errors return {"detail": [...]}.
      if (statusCode == 422 && body['detail'] is List) {
        final details = body['detail'] as List;
        final first = details.isNotEmpty && details.first is Map
            ? (details.first as Map)['msg']?.toString()
            : null;
        return ApiException(
          code: 'VALIDATION_ERROR',
          message: first ?? 'Please check your trip details and try again.',
          statusCode: 422,
        );
      }
    }

    return ApiException(
      code: 'HTTP_${statusCode ?? "ERROR"}',
      message: 'Unexpected server error (${statusCode ?? "unknown"}). '
          'Please try again.',
      statusCode: statusCode,
    );
  }

  String _friendlyMessage(String code, String fallback, int? statusCode) {
    switch (code) {
      case 'RATE_LIMIT_EXCEEDED':
        return 'You reached the daily limit of 5 generated trips. '
            'Try again tomorrow or explore your saved trips.';
      case 'UNAUTHORIZED':
        return 'API authentication failed. Check your API key settings.';
      case 'AI_TIMEOUT':
        return 'The AI planner timed out. Please tap Retry.';
      case 'AI_NOT_CONFIGURED':
      case 'AI_AUTH_FAILED':
        return 'AI service is temporarily unavailable on the server.';
      default:
        return statusCode == 429
            ? 'Too many requests. Please try again later.'
            : fallback;
    }
  }
}
