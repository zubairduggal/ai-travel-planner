import 'package:intl/intl.dart';

import '../constants/app_strings.dart';

/// Currency, date, and distance formatting helpers.
class AppFormatters {
  AppFormatters._();

  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _shortDate = DateFormat('MMM d, yyyy');
  static final DateFormat _dayMonth = DateFormat('MMM d');

  static String toIsoDate(DateTime date) => _isoDate.format(date);

  static String toReadableDate(DateTime date) => _shortDate.format(date);

  static String toDateRange(DateTime start, DateTime end) {
    if (start.year == end.year) {
      return '${_dayMonth.format(start)} – ${_shortDate.format(end)}';
    }
    return '${_shortDate.format(start)} – ${_shortDate.format(end)}';
  }

  static String formatCurrency(double amount, String currencyCode) {
    final code = currencyCode.toUpperCase();
    final symbol = AppStrings.currencySymbols[code] ?? '$code ';
    final sign = amount < 0 ? '-' : '';
    final formatted = NumberFormat(
      code == 'PKR' ? '#,##0' : '#,##0.##',
    ).format(amount.abs());
    return '$sign$symbol$formatted';
  }

  /// Compact price label for map price-tag pins (e.g. `Rs 12k`, `Rs 1.5k`, `$45`).
  static String formatCompactPrice(double amount, String currencyCode) {
    final code = currencyCode.toUpperCase();
    final symbol = AppStrings.currencySymbols[code] ?? '$code ';
    final absVal = amount.abs();
    final sign = amount < 0 ? '-' : '';
    if (absVal >= 1000000) {
      final m = absVal / 1000000;
      final rounded = (m * 10).round() / 10;
      final str = rounded % 1 == 0
          ? rounded.toStringAsFixed(0)
          : rounded.toStringAsFixed(1);
      return '$sign$symbol${str}M';
    }
    if (absVal >= 1000) {
      final k = absVal / 1000;
      final rounded = (k * 10).round() / 10;
      final str = rounded % 1 == 0
          ? rounded.toStringAsFixed(0)
          : rounded.toStringAsFixed(1);
      return '$sign$symbol${str}k';
    }
    final formatted = NumberFormat('#,##0').format(absVal);
    return '$sign$symbol$formatted';
  }

  static String formatDistance(double? km) {
    if (km == null) return 'Distance unavailable';
    return '${km.toStringAsFixed(1)} km';
  }
}
