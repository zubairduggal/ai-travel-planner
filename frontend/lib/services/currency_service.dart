import 'package:dio/dio.dart';

import 'storage_service.dart';

/// Multi-currency converter powered by free Frankfurter API (no API key)
/// with local Hive CE caching and bundled offline fallback rates (MFR-11, FM4).
class CurrencyService {
  CurrencyService({
    Dio? dio,
    this.storage,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  static const String frankfurterEndpoint =
      'https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR,PKR,AED,GBP';

  /// Bundled offline fallback rates relative to 1 USD (used in Airplane Mode).
  static const Map<String, double> fallbackUsdRates = {
    'USD': 1.0,
    'EUR': 0.95,
    'GBP': 0.79,
    'AED': 3.673,
    'PKR': 278.5,
  };

  final Dio _dio;
  final StorageService? storage;

  Map<String, double> _usdRates = Map<String, double>.from(fallbackUsdRates);
  bool _usingLiveRates = false;

  Map<String, double> get currentUsdRates => Map.unmodifiable(_usdRates);
  bool get usingLiveRates => _usingLiveRates;

  /// Loads cached rates first, then refreshes from Frankfurter if online.
  Future<void> refreshRates() async {
    final cached = await storage?.loadExchangeRates();
    if (cached != null && cached.isNotEmpty) {
      _usdRates = {...fallbackUsdRates, ...cached, 'USD': 1.0};
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(frankfurterEndpoint);
      final rawRates = response.data?['rates'];
      if (response.statusCode == 200 && rawRates is Map<String, dynamic>) {
        final parsed = <String, double>{'USD': 1.0};
        for (final entry in rawRates.entries) {
          if (entry.value is num) {
            parsed[entry.key.toUpperCase()] = (entry.value as num).toDouble();
          }
        }
        _usdRates = {...fallbackUsdRates, ...parsed};
        _usingLiveRates = true;
        await storage?.saveExchangeRates(_usdRates);
      }
    } catch (_) {
      // Offline / Airplane Mode: silently keep cached or bundled fallback rates.
      _usingLiveRates = false;
    }
  }

  /// Converts [amount] from [fromCurrency] to [toCurrency] via USD pivot.
  double convert({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) return amount;

    final fromRate = _usdRates[from];
    final toRate = _usdRates[to];
    if (fromRate == null || toRate == null || fromRate <= 0) {
      return amount;
    }

    final inUsd = amount / fromRate;
    final converted = inUsd * toRate;
    return double.parse(converted.toStringAsFixed(2));
  }
}
