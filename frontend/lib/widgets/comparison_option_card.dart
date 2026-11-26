import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/place_option_model.dart';
import 'glass_container.dart';

/// Reusable frosted-glass comparison card for real-world hotel and dining
/// options with honest price provenance badges (`Web Rate` vs `AI Est.`),
/// verified GPS indicator, live Google price check, and map navigation.
class ComparisonOptionCard extends StatelessWidget {
  const ComparisonOptionCard({
    super.key,
    required this.option,
    required this.currency,
    required this.destination,
    required this.isHotel,
    required this.onToggleSelect,
    required this.onShowOnMap,
    this.onCheckLive,
  });

  final PlaceOptionModel option;
  final String currency;
  final String destination;
  final bool isHotel;
  final VoidCallback onToggleSelect;
  final VoidCallback onShowOnMap;
  final VoidCallback? onCheckLive;

  Uri get liveSearchUri => Uri.https(
        'www.google.com',
        '/search',
        {'q': '${option.name} $destination price'},
      );

  Future<void> _launchLiveSearch(BuildContext context) async {
    if (onCheckLive != null) {
      onCheckLive!();
      return;
    }
    try {
      final launched = await launchUrl(
        liveSearchUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser for live price.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser for live price.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final primaryActionLabel = isHotel
        ? (option.selected ? 'Selected ✓' : 'Choose Hotel')
        : (option.selected ? 'Included ✓' : 'Include');

    return GlassContainer(
      borderRadius: 20,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderColor: option.selected
          ? AppTheme.coralPrimary.withValues(alpha: 0.78)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Name + Verified icon + Price
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        option.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (option.verified) ...[
                      const SizedBox(width: 5),
                      Tooltip(
                        message: 'Verified GPS',
                        child: Icon(
                          Icons.verified_rounded,
                          size: 17,
                          color: isDark
                              ? const Color(0xFF5EEAD4)
                              : AppTheme.mintText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${AppFormatters.formatCurrency(option.estimatedPrice, currency)}'
                    '${isHotel ? '/night' : '/meal'}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppTheme.coralPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (isHotel) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Total ${AppFormatters.formatCurrency(option.totalEstimatedCost, currency)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TierPill(label: option.tierLabel, tier: option.tier),
              if (option.isWebFound)
                const MintStatusPill(
                  icon: Icons.public_rounded,
                  label: 'Web Rate',
                )
              else
                const _AmberEstimatePill(label: 'AI Est.'),
              if (option.distanceToCenterKm != null)
                _SubtleInfoPill(
                  icon: Icons.near_me_outlined,
                  label:
                      '${option.distanceToCenterKm!.toStringAsFixed(1)} km from center',
                ),
            ],
          ),

          if (option.priceNote.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              option.priceNote.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (option.highlights.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: option.highlights.take(4).map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : colors.surfaceContainerHighest.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 12),

          // Overflow-safe Action Row (Wrap guarantees zero RenderFlex overflow at 390px)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _CoralSelectButton(
                label: primaryActionLabel,
                selected: option.selected,
                onPressed: onToggleSelect,
              ),
              _GlassOutlineAction(
                icon: Icons.open_in_new_rounded,
                label: 'Check Live',
                onPressed: () => _launchLiveSearch(context),
              ),
              _GlassOutlineAction(
                icon: Icons.map_outlined,
                label: 'Show on Map',
                onPressed: onShowOnMap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierPill extends StatelessWidget {
  const _TierPill({required this.label, required this.tier});

  final String label;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color accent;
    switch (tier.toLowerCase()) {
      case 'budget':
        accent = isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB);
        break;
      case 'comfort':
        accent = isDark ? const Color(0xFFD8B4FE) : const Color(0xFF7C3AED);
        break;
      default:
        accent = AppTheme.coralPrimary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.2 : 0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AmberEstimatePill extends StatelessWidget {
  const _AmberEstimatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppTheme.warmGold.withValues(alpha: 0.22)
        : const Color(0xFFFEF3C7);
    final fg = isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtleInfoPill extends StatelessWidget {
  const _SubtleInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: colors.onSurfaceVariant),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _CoralSelectButton extends StatelessWidget {
  const _CoralSelectButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);

    if (selected) {
      return Container(
        decoration: BoxDecoration(
          gradient: AppTheme.coralGradient,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppTheme.coralPrimary.withValues(alpha: 0.28),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: radius),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.coralPrimary,
        backgroundColor: AppTheme.coralPrimary.withValues(alpha: 0.09),
        side: BorderSide(color: AppTheme.coralPrimary.withValues(alpha: 0.55)),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: radius),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _GlassOutlineAction extends StatelessWidget {
  const _GlassOutlineAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.65),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.16)
              : const Color(0xFFD6DCE5),
        ),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: AppTheme.coralPrimary),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
