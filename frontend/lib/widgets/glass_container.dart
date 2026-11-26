import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';

/// Frosted-glass surface card with real BackdropFilter blur, 1px translucent
/// light border, and soft diffused elevation shadow.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 20,
    this.blurSigma = 14,
    this.opacity,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurSigma;
  final double? opacity;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = backgroundColor ??
        (isDark
            ? const Color(0xFF1E2433).withValues(alpha: opacity ?? 0.74)
            : Colors.white.withValues(alpha: opacity ?? 0.72));
    final stroke = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.85));
    final radius = BorderRadius.circular(borderRadius);

    Widget content = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: stroke, width: 1),
          ),
          child: Material(
            color: Colors.transparent,
            child: onTap != null
                ? InkWell(
                    borderRadius: radius,
                    onTap: onTap,
                    child: Padding(padding: padding, child: child),
                  )
                : Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// Ambient pastel / midnight gradient backdrop so frosted glass translucency
/// is clearly visible across every screen in both Light and Dark themes.
class GlassScaffoldBackground extends StatelessWidget {
  const GlassScaffoldBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      AppTheme.darkBgTop,
                      AppTheme.darkBgMid,
                      AppTheme.darkBgBottom,
                    ]
                  : const [
                      AppTheme.lightBgTop,
                      AppTheme.lightBgMid,
                      AppTheme.lightBgBottom,
                    ],
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
        // Subtle top-right peach/coral ambient orb
        Positioned(
          top: -90,
          right: -70,
          child: IgnorePointer(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.coralPrimary.withValues(alpha: isDark ? 0.18 : 0.22),
                    AppTheme.coralPrimary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Subtle bottom-left sky/indigo ambient orb
        Positioned(
          bottom: -110,
          left: -80,
          child: IgnorePointer(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? const Color(0xFF4F46E5) : const Color(0xFF93C5FD))
                        .withValues(alpha: isDark ? 0.22 : 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Constrains desktop/laptop web layouts to a clean, well-proportioned width
/// while keeping mobile viewports edge-to-edge.
class GlassContentConstraint extends StatelessWidget {
  const GlassContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = 600,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Frosted Mint pill badge (verified GPS, trip status, instant cache).
class MintStatusPill extends StatelessWidget {
  const MintStatusPill({
    super.key,
    required this.label,
    this.icon,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? AppTheme.mintText.withValues(alpha: 0.22)
        : AppTheme.mintBg;
    final fg = isDark ? const Color(0xFF5EEAD4) : AppTheme.mintText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: fg.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
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
