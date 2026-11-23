import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/utils/error_dialogs.dart';
import '../../core/utils/map_launcher.dart';
import '../../models/activity_model.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

/// Bottom sheet allowing the user to edit notes, navigate externally,
/// regenerate a single slot with AI, or delete an activity (MFR-07, MFR-09).
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
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.activity.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            const Divider(height: 28),
            Text(
              'Swap with AI',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
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
              OutlinedButton.icon(
                onPressed: isRegenerating
                    ? null
                    : () => MapLauncher.openExternalMaps(
                          latitude: widget.activity.latitude!,
                          longitude: widget.activity.longitude!,
                          label: widget.activity.title,
                        ),
                icon: const Icon(Icons.directions_rounded),
                label: const Text('Navigate in Maps'),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: isRegenerating ? null : _deleteActivity,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete Activity'),
            ),
          ],
        ),
      ),
    );
  }
}
