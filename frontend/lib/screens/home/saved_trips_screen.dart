import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/glass_container.dart';
import '../itinerary/itinerary_screen.dart';

/// Saved Trips offline dashboard powered by Hive CE (MFR-10, FM4).
class SavedTripsScreen extends StatelessWidget {
  const SavedTripsScreen({
    super.key,
    required this.onCreateTripTap,
  });

  final VoidCallback onCreateTripTap;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final trips = provider.trips;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('My Trips'),
        actions: [
          if (trips.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: MintStatusPill(
                icon: Icons.offline_pin_outlined,
                label: 'Offline Ready',
              ),
            ),
        ],
      ),
      body: GlassScaffoldBackground(
        child: SafeArea(
          bottom: false,
          child: GlassContentConstraint(
            maxWidth: 620,
            child: trips.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
                      child: GlassContainer(
                        borderRadius: 26,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: AppTheme.coralPrimary
                                    .withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.luggage_outlined,
                                size: 36,
                                color: AppTheme.coralPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No trips planned yet',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your first AI-powered itinerary to view it offline anytime.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 22),
                            CustomButton(
                              onPressed: onCreateTripTap,
                              icon: Icons.add_location_alt_outlined,
                              label: 'Plan a Trip',
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 118),
                    itemCount: trips.length,
                    itemBuilder: (context, index) {
                      final trip = trips[index];
                      final dateLabel =
                          (trip.startDate != null && trip.endDate != null)
                              ? AppFormatters.toDateRange(
                                  trip.startDate!,
                                  trip.endDate!,
                                )
                              : '${trip.durationDays} days';

                      return GlassContainer(
                        margin: const EdgeInsets.only(bottom: 12),
                        borderRadius: 20,
                        padding: const EdgeInsets.all(16),
                        onTap: () {
                          provider.selectTrip(trip);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ItineraryScreen(trip: trip),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const MintStatusPill(
                                  icon: Icons.offline_pin_outlined,
                                  label: 'Saved Offline',
                                ),
                                const Spacer(),
                                Text(
                                  dateLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.coralGradient,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.flight_takeoff_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trip.destination,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${trip.durationDays}d • ${trip.travelStyle}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  AppFormatters.formatCurrency(
                                    trip.totalEstimatedCost,
                                    trip.currency,
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppTheme.coralPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: colors.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete saved trip',
                                  onPressed: () =>
                                      provider.deleteTrip(trip.tripId),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
