import 'package:material_ui/material_ui.dart';

/// Home / Saved Trips dashboard (offline trips populated in FM2–FM4).
class SavedTripsScreen extends StatelessWidget {
  const SavedTripsScreen({
    super.key,
    required this.onCreateTripTap,
  });

  final VoidCallback onCreateTripTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Trips')),
      body: Center(
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
                'Create your first AI-powered itinerary to see it saved here.',
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
      ),
    );
  }
}
