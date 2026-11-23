import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../models/activity_model.dart';
import '../../models/day_plan_model.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/activity_card.dart';
import '../map/map_screen.dart';
import 'slot_editor_sheet.dart';

/// Day-by-day tabbed itinerary viewer with Map view & Slot customization (MFR-06–09).
class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({
    super.key,
    required this.trip,
  });

  final TripModel trip;

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final length = widget.trip.days.isEmpty ? 1 : widget.trip.days.length;
    _tabController = TabController(length: length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openMap(TripModel currentTrip) {
    final dayIdx = _tabController.index.clamp(0, currentTrip.days.length - 1);
    final dayNumber = currentTrip.days[dayIdx].dayNumber;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapScreen(
          trip: currentTrip,
          initialDayNumber: dayNumber,
        ),
      ),
    );
  }

  void _openSlotEditor(
    TripModel currentTrip,
    int dayNumber,
    ActivityModel activity,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SlotEditorSheet(
        trip: currentTrip,
        dayNumber: dayNumber,
        activity: activity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final currentTrip = provider.activeTrip?.tripId == widget.trip.tripId
        ? provider.activeTrip!
        : widget.trip;
    final days = currentTrip.days;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (days.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(currentTrip.destination)),
        body: const Center(child: Text('No daily activities found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTrip.destination),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Open Map View',
            onPressed: () => _openMap(currentTrip),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: days.length > 3,
          tabAlignment:
              days.length > 3 ? TabAlignment.start : TabAlignment.fill,
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
              controller: _tabController,
              children: [
                for (final day in days)
                  _DayPlanView(
                    day: day,
                    currency: currentTrip.currency,
                    colors: colors,
                    theme: theme,
                    onCustomizeActivity: (act) =>
                        _openSlotEditor(currentTrip, day.dayNumber, act),
                  ),
              ],
            ),
          ),
        ],
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
    required this.onCustomizeActivity,
  });

  final DayPlanModel day;
  final String currency;
  final ColorScheme colors;
  final ThemeData theme;
  final ValueChanged<ActivityModel> onCustomizeActivity;

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
        if (day.activities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'All activities removed for Day ${day.dayNumber}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < day.activities.length; i++)
            ActivityCard(
              activity: day.activities[i],
              currency: currency,
              indexNumber: i + 1,
              onTap: () => onCustomizeActivity(day.activities[i]),
              onCustomizeTap: () => onCustomizeActivity(day.activities[i]),
            ),
      ],
    );
  }
}
