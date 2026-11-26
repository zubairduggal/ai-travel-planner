import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/activity_model.dart';
import 'glass_container.dart';

/// Frosted-glass card for a single activity inside a day plan (MFR-06).
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
    final isDark = theme.brightness == Brightness.dark;

    return GlassContainer(
      margin: const EdgeInsets.symmetric(vertical: 6),
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (indexNumber != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.coralGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$indexNumber',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.coralPrimary.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _slotIcon(activity.timeSlot),
                      size: 14,
                      color: AppTheme.coralPrimary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      activity.timeSlot,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.coralPrimary,
                        fontWeight: FontWeight.w700,
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
                  color: AppTheme.coralPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (onCustomizeTap != null) ...[
                const SizedBox(width: 2),
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
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            activity.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (activity.notes != null && activity.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : AppTheme.lightBgMid.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    size: 16,
                    color: AppTheme.coralPrimary,
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
              _CategoryBadge(
                icon: Icons.category_outlined,
                label: activity.category,
              ),
              if (activity.verified)
                const MintStatusPill(
                  icon: Icons.verified_outlined,
                  label: 'Verified GPS',
                )
              else
                _MutedBadge(
                  icon: Icons.location_off_outlined,
                  label: 'Location unverified',
                ),
              if (activity.duration != null)
                _MutedBadge(
                  icon: Icons.timer_outlined,
                  label: activity.duration!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.warmGold.withValues(alpha: isDark ? 0.2 : 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDark
                      ? const Color(0xFFFCD34D)
                      : const Color(0xFFB45309),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _MutedBadge extends StatelessWidget {
  const _MutedBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
