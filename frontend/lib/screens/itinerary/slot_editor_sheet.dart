import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_dialogs.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/map_launcher.dart';
import '../../models/activity_model.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/glass_container.dart';

/// Frosted-glass bottom sheet for activity details, notes, external navigation,
/// AI slot regeneration, and deletion (MFR-07, MFR-09).
class SlotEditorSheet extends StatefulWidget {
  const SlotEditorSheet({
    super.key,
    required this.trip,
    required this.dayNumber,
    required this.activity,
  });

  final TripModel trip;
  final int dayNumber;
  final ActivityModel activity;

  @override
  State<SlotEditorSheet> createState() => _SlotEditorSheetState();
}

class _SlotEditorSheetState extends State<SlotEditorSheet> {
  late final TextEditingController _notesController;
  final _regenPreferenceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.activity.notes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    _regenPreferenceController.dispose();
    super.dispose();
  }

  void _saveNotes() {
    context.read<TripProvider>().updateActivityNotes(
          tripId: widget.trip.tripId,
          dayNumber: widget.dayNumber,
          activityId: widget.activity.activityId,
          notes: _notesController.text,
        );
    Navigator.of(context).pop();
    ErrorDialogs.showSnackBar(context, 'Activity notes saved.');
  }

  Future<void> _regenerateSlot() async {
    final provider = context.read<TripProvider>();
    final replacement = await provider.regenerateActivitySlot(
      trip: widget.trip,
      dayNumber: widget.dayNumber,
      activity: widget.activity,
      userNote: _regenPreferenceController.text,
    );
    if (!mounted) return;
    if (replacement != null) {
      Navigator.of(context).pop();
      ErrorDialogs.showSnackBar(
        context,
        'Swapped slot to "${replacement.title}".',
      );
    } else if (provider.errorMessage != null) {
      ErrorDialogs.showSnackBar(
        context,
        provider.errorMessage!,
        isError: true,
      );
    }
  }

  void _deleteActivity() {
    context.read<TripProvider>().deleteActivity(
          tripId: widget.trip.tripId,
          dayNumber: widget.dayNumber,
          activityId: widget.activity.activityId,
        );
    Navigator.of(context).pop();
    ErrorDialogs.showSnackBar(context, 'Activity removed from itinerary.');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final isRegenerating =
        provider.regeneratingActivityId == widget.activity.activityId;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: GlassContentConstraint(
        maxWidth: 520,
        child: GlassContainer(
          borderRadius: 28,
          opacity: 0.92,
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              MintStatusPill(
                                icon: widget.activity.verified
                                    ? Icons.verified_outlined
                                    : Icons.category_outlined,
                                label: widget.activity.verified
                                    ? 'Verified GPS'
                                    : widget.activity.category,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.activity.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.activity.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                // Two-column coral-icon info row (Location + Est. Cost)
                Row(
                  children: [
                    Expanded(
                      child: _SlotInfoTile(
                        icon: Icons.place_rounded,
                        label: 'Location',
                        value: widget.activity.category,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SlotInfoTile(
                        icon: Icons.payments_rounded,
                        label: 'Est. Cost',
                        value: widget.activity.estimatedCost == 0
                            ? 'Free'
                            : AppFormatters.formatCurrency(
                                widget.activity.estimatedCost,
                                widget.trip.currency,
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _notesController,
                  label: 'Personal Notes',
                  hintText: 'Booking code, tips, or reminders...',
                  prefixIcon: Icons.sticky_note_2_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                CustomButton(
                  label: 'Save Notes',
                  icon: Icons.check_rounded,
                  isOutlined: true,
                  onPressed: isRegenerating ? null : _saveNotes,
                ),
                const Divider(height: 26),
                Text(
                  'Swap with AI',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                CustomTextField(
                  controller: _regenPreferenceController,
                  label: 'Optional preference for replacement',
                  hintText: 'e.g. Indoor museum or quiet café nearby',
                  prefixIcon: Icons.tune_rounded,
                ),
                const SizedBox(height: 10),
                CustomButton(
                  label: 'Regenerate Slot',
                  icon: Icons.auto_awesome_rounded,
                  isLoading: isRegenerating,
                  onPressed: _regenerateSlot,
                ),
                if (widget.activity.hasCoordinates) ...[
                  const SizedBox(height: 10),
                  CustomButton(
                    label: 'Navigate in Maps',
                    icon: Icons.directions_rounded,
                    isOutlined: true,
                    onPressed: isRegenerating
                        ? null
                        : () => MapLauncher.openExternalMaps(
                              latitude: widget.activity.latitude!,
                              longitude: widget.activity.longitude!,
                              label: widget.activity.title,
                            ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: isRegenerating ? null : _deleteActivity,
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete Activity'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotInfoTile extends StatelessWidget {
  const _SlotInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.coralPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppTheme.coralPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
