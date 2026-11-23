import 'package:material_ui/material_ui.dart';

/// Trip creation placeholder tab (full validated form + FastAPI integration in FM2).
class TripCreationScreen extends StatelessWidget {
  const TripCreationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Trip')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 64,
                color: colors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'AI Trip Builder',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Preference capture & FastAPI itinerary generation will be '
                'activated in Milestone FM2.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
