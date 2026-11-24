import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/custom_button.dart';
import '../auth/auth_screen.dart';
import '../home/main_shell.dart';

/// Entry onboarding screen supporting Guest Mode (MFR-01) and Sign In (FM5).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _continueAsGuest(BuildContext context) {
    context.read<AuthProvider>().enterAsGuest();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // Per PRD Section 5 workflow, Guest Mode opens directly on Create Trip.
        builder: (_) => const MainShell(initialIndex: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.travel_explore_rounded,
                    size: 52,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.appTagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 36),
              const _FeatureBullet(
                icon: Icons.auto_awesome_rounded,
                text: 'Personalized AI day-by-day schedules',
              ),
              const SizedBox(height: 12),
              const _FeatureBullet(
                icon: Icons.map_outlined,
                text: 'Verified GPS coordinates & daily map routes',
              ),
              const SizedBox(height: 12),
              const _FeatureBullet(
                icon: Icons.offline_pin_outlined,
                text: 'Offline trip access & multi-currency expense tracker',
              ),
              const Spacer(),
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
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
