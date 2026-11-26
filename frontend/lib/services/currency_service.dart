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
  Set<String> _liveCurrencies = const {'USD'};

  Map<String, double> get currentUsdRates => Map.unmodifiable(_usdRates);
  bool get usingLiveRates => _usingLiveRates;
  Set<String> get liveCurrencies => Set.unmodifiable(_liveCurrencies);

  /// Returns true when [currencyCode] is backed by a live Frankfurter ECB rate
  /// (or is the USD pivot). Currencies omitted by Frankfurter (e.g. PKR, AED)
  /// return false so the UI shows an honest fallback notice.
  bool isCurrencyLive(String currencyCode) {
    final code = currencyCode.toUpperCase();
    if (code == 'USD') return _usingLiveRates;
    return _usingLiveRates && _liveCurrencies.contains(code);
  }

  /// Human-readable FX source notice for a specific currency or pair.
  String rateSourceLabel({
    required String tripCurrency,
    Iterable<String> expenseCurrencies = const [],
  }) {
    final involved = <String>{
      tripCurrency.toUpperCase(),
      ...expenseCurrencies.map((c) => c.toUpperCase()),
    };
    if (!_usingLiveRates) {
      return 'Estimated rate (Offline fallback)';
    }
    final fallbackUsed = involved
        .where((code) => code != 'USD' && !_liveCurrencies.contains(code))
        .toList()
      ..sort();
    if (fallbackUsed.isEmpty) {
      return 'Exchange rates: Live (Frankfurter ECB)';
    }
    if (involved.every((code) => code == 'USD' || !_liveCurrencies.contains(code))) {
      return 'Estimated rate (Offline fallback) for ${fallbackUsed.join(', ')}';
    }
    final liveUsed = involved
        .where((code) => code != 'USD' && _liveCurrencies.contains(code))
        .toList()
      ..sort();
    return 'Live (Frankfurter ECB): ${liveUsed.join(', ')} • '
        'Estimated rate (Offline fallback): ${fallbackUsed.join(', ')}';
  }

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
        final liveSet = <String>{'USD'};
        for (final entry in rawRates.entries) {
          if (entry.value is num) {
            final code = entry.key.toUpperCase();
            parsed[code] = (entry.value as num).toDouble();
            liveSet.add(code);
          }
        }
        _usdRates = {...fallbackUsdRates, ...parsed};
        _liveCurrencies = liveSet;
        _usingLiveRates = liveSet.length > 1;
        await storage?.saveExchangeRates(_usdRates);
      }
    } catch (_) {
      // Offline / Airplane Mode: silently keep cached or bundled fallback rates.
      _usingLiveRates = false;
      _liveCurrencies = const {'USD'};
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
