import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';

/// Full-width pill CTA button: vibrant Coral-Orange gradient primary button
/// or frosted outlined pill secondary button (height: 52, radius: 28).
class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isOutlined = false,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isOutlined;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = !isLoading && onPressed != null;

    final child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: isOutlined ? AppTheme.coralPrimary : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    if (isOutlined) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: isDark
                ? const Color(0xFF1E2433).withValues(alpha: 0.62)
                : Colors.white.withValues(alpha: 0.72),
            foregroundColor: isDark ? Colors.white : AppTheme.charcoalText,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.95),
            ),
          ),
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: enabled ? AppTheme.coralGradient : null,
        color: enabled ? null : AppTheme.coralPrimary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(28),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppTheme.coralPrimary.withValues(alpha: 0.34),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: child,
      ),
    );
  }
}
