import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/glass_container.dart';
import '../auth/auth_screen.dart';
import '../home/main_shell.dart';

/// Light-first Coral-Orange Glassmorphism onboarding screen (MFR-01).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _continueAsGuest(BuildContext context) {
    context.read<AuthProvider>().enterAsGuest();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const MainShell(initialIndex: 0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: GlassContentConstraint(
            maxWidth: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.vertical -
                      48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand badge row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            gradient: AppTheme.coralGradient,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.travel_explore_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AppStrings.appName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Top Frosted-Glass Travel Preview Card
                    GlassContainer(
                      borderRadius: 26,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 148,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF1E3A5F),
                                  Color(0xFF2B6CB0),
                                  Color(0xFFF05A3E),
                                ],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -18,
                                  top: -22,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 18,
                                  bottom: 18,
                                  child: Icon(
                                    Icons.terrain_rounded,
                                    size: 74,
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                const Positioned(
                                  left: 14,
                                  top: 14,
                                  child: MintStatusPill(
                                    icon: Icons.verified_outlined,
                                    label: 'Verified GPS Routes',
                                  ),
                                ),
                                Positioned(
                                  left: 14,
                                  bottom: 14,
                                  right: 14,
                                  child: GlassContainer(
                                    borderRadius: 16,
                                    opacity: isDark ? 0.78 : 0.86,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Hunza Valley Escape',
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                '5 days • Nature & Local Food',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          'Rs 45,000',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            color: AppTheme.coralPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Wrap(
                            alignment: WrapAlignment.spaceAround,
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _MiniPreviewTag(
                                icon: Icons.auto_awesome_rounded,
                                label: 'AI Schedules',
                              ),
                              _MiniPreviewTag(
                                icon: Icons.map_rounded,
                                label: 'Live Maps',
                              ),
                              _MiniPreviewTag(
                                icon: Icons.offline_pin_rounded,
                                label: 'Offline Ready',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Bold Centered Headline + Subtitle + Coral Dots
                    Column(
                      children: [
                        Text(
                          'One app for all your travel planning needs',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Craft personalized day-by-day itineraries, verify real-world GPS pins, and track multi-currency budgets offline.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Coral pagination dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 24,
                              height: 7,
                              decoration: BoxDecoration(
                                gradient: AppTheme.coralGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppTheme.coralPrimary
                                    .withValues(alpha: 0.28),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppTheme.coralPrimary
                                    .withValues(alpha: 0.28),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Full-Width Coral Pill CTAs
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CustomButton(
                          label: AppStrings.exploreAsGuest,
                          icon: Icons.explore_rounded,
                          onPressed: () => _continueAsGuest(context),
                        ),
                        const SizedBox(height: 12),
                        CustomButton(
                          label: 'Sign In / Create Account',
                          icon: Icons.login_rounded,
                          isOutlined: true,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AuthScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPreviewTag extends StatelessWidget {
  const _MiniPreviewTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppTheme.coralPrimary),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
