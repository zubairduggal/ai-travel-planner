import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../providers/trip_provider.dart';
import '../itinerary/itinerary_screen.dart';

/// Home / Saved Trips offline dashboard powered by Hive CE (MFR-10, FM4).
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
      appBar: AppBar(
        title: const Text('My Trips'),
        actions: [
          if (trips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: const Icon(Icons.offline_pin_outlined, size: 16),
                label: const Text('Offline Ready'),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
      body: trips.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.luggage_outlined,
                      size: 64,
                      color: colors.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No trips planned yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
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
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onCreateTripTap,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Plan a Trip'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];
                final subtitle =
                    (trip.startDate != null && trip.endDate != null)
                        ? '${AppFormatters.toDateRange(trip.startDate!, trip.endDate!)} • ${trip.travelStyle}'
                        : '${trip.durationDays} days • ${trip.travelStyle}';

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      foregroundColor: colors.onPrimaryContainer,
                      child: const Icon(Icons.flight_takeoff_rounded),
                    ),
                    title: Text(
                      trip.destination,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              AppFormatters.formatCurrency(
                                trip.totalEstimatedCost,
                                trip.currency,
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${trip.durationDays}d',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: colors.error,
                            size: 20,
                          ),
                          tooltip: 'Delete saved trip',
                          onPressed: () => provider.deleteTrip(trip.tripId),
                        ),
                      ],
                    ),
                    onTap: () {
                      provider.selectTrip(trip);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItineraryScreen(trip: trip),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
