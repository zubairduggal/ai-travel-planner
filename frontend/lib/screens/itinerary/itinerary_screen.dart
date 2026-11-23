import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../models/day_plan_model.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/activity_card.dart';

/// Day-by-day tabbed itinerary viewer (MFR-06; Maps & Slot editing added in FM3).
class ItineraryScreen extends StatelessWidget {
  const ItineraryScreen({
    super.key,
    required this.trip,
  });

  final TripModel trip;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    // Prefer updated copy from provider if available (for FM3 slot edits).
    final currentTrip =
        provider.activeTrip?.tripId == trip.tripId ? provider.activeTrip! : trip;
    final days = currentTrip.days;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (days.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(currentTrip.destination)),
        body: const Center(child: Text('No daily activities found.')),
      );
    }

    return DefaultTabController(
      length: days.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(currentTrip.destination),
          bottom: TabBar(
            isScrollable: days.length > 3,
            tabAlignment: days.length > 3 ? TabAlignment.start : TabAlignment.fill,
            tabs: [
              for (final day in days) Tab(text: 'Day ${day.dayNumber}'),
            ],
          ),
        ),
        body: Column(
          children: [
            _TripSummaryHeader(
              trip: currentTrip,
              cacheStatus: provider.lastCacheStatus,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final day in days)
                    _DayPlanView(
                      day: day,
                      currency: currentTrip.currency,
                      colors: colors,
                      theme: theme,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripSummaryHeader extends StatelessWidget {
  const _TripSummaryHeader({
    required this.trip,
    this.cacheStatus,
  });

  final TripModel trip;
  final String? cacheStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dateText = (trip.startDate != null && trip.endDate != null)
        ? AppFormatters.toDateRange(trip.startDate!, trip.endDate!)
        : '${trip.durationDays} days';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _HeaderMetric(
            icon: Icons.calendar_today_outlined,
            label: dateText,
          ),
          _HeaderMetric(
            icon: Icons.account_balance_wallet_outlined,
            label:
                'Est. ${AppFormatters.formatCurrency(trip.totalEstimatedCost, trip.currency)}'
                '${trip.targetBudget != null ? " / ${AppFormatters.formatCurrency(trip.targetBudget!, trip.currency)}" : ""}',
          ),
          _HeaderMetric(
            icon: Icons.style_outlined,
            label: trip.travelStyle,
          ),
          if (cacheStatus?.toUpperCase() == 'HIT')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Instant Cache',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colors.primary),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _DayPlanView extends StatelessWidget {
  const _DayPlanView({
    required this.day,
    required this.currency,
    required this.colors,
    required this.theme,
  });

  final DayPlanModel day;
  final String currency;
  final ColorScheme colors;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                day.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (day.totalDistanceKm != null)
              Chip(
                avatar: const Icon(Icons.route_outlined, size: 16),
                label: Text(AppFormatters.formatDistance(day.totalDistanceKm)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (!day.feasible && day.distanceWarnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colors.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Long travel distance detected',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final warning in day.distanceWarnings)
                        Text(
                          warning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < day.activities.length; i++)
          ActivityCard(
            activity: day.activities[i],
            currency: currency,
            indexNumber: i + 1,
          ),
      ],
    );
  }
}
