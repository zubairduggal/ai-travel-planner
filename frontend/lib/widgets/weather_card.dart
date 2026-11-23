import 'package:material_ui/material_ui.dart';

import '../core/utils/formatters.dart';
import '../models/weather_model.dart';

/// Destination weather forecast widget powered by backend `/api/v1/weather` (FM4).
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    required this.forecast,
    this.isLoading = false,
    this.onRefresh,
  });

  final WeatherForecastModel? forecast;
  final bool isLoading;
  final VoidCallback? onRefresh;

  IconData _weatherIcon(int? code) {
    if (code == null) return Icons.cloud_outlined;
    if (code == 0 || code == 1) return Icons.wb_sunny_rounded;
    if (code == 2 || code == 3) return Icons.cloud_rounded;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return Icons.ac_unit_rounded;
    }
    if (code >= 51 && code <= 82) return Icons.water_drop_rounded;
    if (code >= 95) return Icons.thunderstorm_rounded;
    return Icons.foggy;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Destination Weather Forecast',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (onRefresh != null)
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'Refresh weather',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRefresh,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (forecast == null || forecast!.daily.isEmpty)
              Text(
                isLoading
                    ? 'Fetching forecast...'
                    : 'Weather unavailable offline or no verified GPS coordinates.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: forecast!.daily.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final day = forecast!.daily[index];
                    return Container(
                      width: 128,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppFormatters.toReadableDate(day.date)
                                .split(',')
                                .first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                _weatherIcon(day.weatherCode),
                                size: 18,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${day.tempMaxC?.round() ?? "--"}°/${day.tempMinC?.round() ?? "--"}°',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            day.condition,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
