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
    final formatted = NumberFormat('#,##0.##').format(amount);
    return '$symbol$formatted';
  }

  static String formatDistance(double? km) {
    if (km == null) return 'Distance unavailable';
    return '${km.toStringAsFixed(1)} km';
  }
}
