import 'package:material_ui/material_ui.dart';

import '../core/utils/formatters.dart';
import '../models/activity_model.dart';

/// Visual Material 3 card for a single activity inside a day plan (MFR-06).
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.activity,
    required this.currency,
    this.indexNumber,
    this.onTap,
    this.onCustomizeTap,
  });

  final ActivityModel activity;
  final String currency;
  final int? indexNumber;
  final VoidCallback? onTap;
  final VoidCallback? onCustomizeTap;

  IconData _slotIcon(String slot) {
    final lower = slot.toLowerCase();
    if (lower.contains('morning')) return Icons.wb_sunny_outlined;
    if (lower.contains('afternoon')) return Icons.light_mode_outlined;
    if (lower.contains('evening') || lower.contains('night')) {
      return Icons.nights_stay_outlined;
    }
    return Icons.schedule_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (indexNumber != null) ...[
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      child: Text(
                        '$indexNumber',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _slotIcon(activity.timeSlot),
                          size: 14,
                          color: colors.onPrimaryContainer,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          activity.timeSlot,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    activity.estimatedCost == 0
                        ? 'Free'
                        : AppFormatters.formatCurrency(
                            activity.estimatedCost,
                            currency,
                          ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (onCustomizeTap != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      tooltip: 'Edit or regenerate slot',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCustomizeTap,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                activity.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                activity.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (activity.notes != null && activity.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activity.notes!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Badge(
                    icon: Icons.category_outlined,
                    label: activity.category,
                    bg: colors.secondaryContainer,
                    fg: colors.onSecondaryContainer,
                  ),
                  _Badge(
                    icon: activity.verified
                        ? Icons.verified_outlined
                        : Icons.location_off_outlined,
                    label: activity.verified
                        ? 'Verified GPS'
                        : 'Location unverified',
                    bg: activity.verified
                        ? colors.tertiaryContainer
                        : colors.surfaceContainerHighest,
                    fg: activity.verified
                        ? colors.onTertiaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  if (activity.duration != null)
                    _Badge(
                      icon: Icons.timer_outlined,
                      label: activity.duration!,
                      bg: colors.surfaceContainerHighest,
                      fg: colors.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
