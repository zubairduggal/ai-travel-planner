import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/api_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/trip_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/glass_container.dart';
import '../auth/auth_screen.dart';
import '../onboarding/welcome_screen.dart';

/// User Profile & Settings screen with Theme toggle, Sign Out, and
/// Store-compliant Account Deletion & Local Data Purge (MFR-03, FM5).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _providerLabel(AuthProvider auth) {
    if (auth.isGuest) return 'Guest Mode • Data stored locally on device';
    final method = switch (auth.providerType) {
      AuthProviderType.google => 'Google Account',
      AuthProviderType.apple => 'Apple Account',
      AuthProviderType.emailPassword => 'Email Account',
      AuthProviderType.guest => 'Guest Mode',
    };
    return auth.userEmail != null ? '${auth.userEmail} • $method' : method;
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  Future<void> _confirmAndDeleteAccount(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          auth.isAuthenticated
              ? 'Delete Account & Purge Data?'
              : 'Purge All Local Data?',
        ),
        content: Text(
          auth.isAuthenticated
              ? 'This permanently deletes your account and wipes all saved '
                  'trips, expenses, packing lists, weather caches, and settings '
                  'from this device. This action cannot be undone.'
              : 'This permanently wipes all saved trips, expenses, packing '
                  'lists, weather caches, and settings from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    var status = await auth.deleteAccountAndPurgeData();
    if (!context.mounted) return;

    if (status == DeleteAccountStatus.requiresRecentLogin) {
      status = await _promptReauthenticationAndDelete(context, auth);
      if (!context.mounted) return;
    }

    if (status == DeleteAccountStatus.deleted) {
      context.read<TripProvider>().clearInMemory();
      context.read<ExpenseProvider>().clearInMemory();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account and all local data have been deleted.'),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    } else if (auth.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage!)),
      );
    }
  }

  Future<DeleteAccountStatus> _promptReauthenticationAndDelete(
    BuildContext context,
    AuthProvider auth,
  ) async {
    if (auth.providerType == AuthProviderType.emailPassword) {
      final password = await showDialog<String>(
        context: context,
        builder: (_) => const _PasswordReauthDialog(),
      );
      if (password == null || password.isEmpty) {
        return DeleteAccountStatus.failed;
      }
      return auth.reauthenticateAndDeleteAccount(password: password);
    }

    final providerName =
        auth.providerType == AuthProviderType.apple ? 'Apple' : 'Google';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Verify with $providerName'),
        content: Text(
          'Your session requires recent verification before deleting your '
          'account. Continue with $providerName to confirm?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('Verify with $providerName'),
          ),
        ],
      ),
    );
    if (proceed != true) return DeleteAccountStatus.failed;
    return auth.reauthenticateAndDeleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final savedTripsCount = context.watch<TripProvider>().trips.length;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: GlassScaffoldBackground(
        child: SafeArea(
          bottom: false,
          child: GlassContentConstraint(
            maxWidth: 600,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 118),
              children: [
                GlassContainer(
                  borderRadius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.coralGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        auth.isAuthenticated
                            ? Icons.verified_user_outlined
                            : Icons.person_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(
                      auth.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(_providerLabel(auth)),
                  ),
                ),
                if (auth.isGuest) ...[
                  const SizedBox(height: 10),
                  GlassContainer(
                    borderRadius: 20,
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(
                        Icons.login_rounded,
                        color: AppTheme.coralPrimary,
                      ),
                      title: const Text(
                        'Sign In / Create Account',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Sync with Email, Google, or Apple'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AuthScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                GlassContainer(
                  borderRadius: 20,
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    secondary: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: AppTheme.coralPrimary,
                    ),
                    title: const Text(
                      'Dark Mode',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Switch between Glassmorphism light & dark themes',
                    ),
                    value: isDark,
                    onChanged: (value) => auth.toggleDarkMode(value),
                  ),
                ),
                const SizedBox(height: 10),
                GlassContainer(
                  borderRadius: 20,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(
                      Icons.luggage_outlined,
                      color: AppTheme.coralPrimary,
                    ),
                    title: const Text(
                      'Offline Saved Trips',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '$savedTripsCount ${savedTripsCount == 1 ? "trip" : "trips"} '
                      'cached locally on this device',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GlassContainer(
                  borderRadius: 20,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(
                      Icons.cloud_outlined,
                      color: AppTheme.coralPrimary,
                    ),
                    title: const Text(
                      'Backend API URL',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(ApiConstants.baseUrl),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: auth.isBusy ? null : () => _handleSignOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(auth.isGuest ? 'Exit Guest Mode' : 'Sign Out'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(color: colors.error),
                  ),
                  onPressed: auth.isBusy
                      ? null
                      : () => _confirmAndDeleteAccount(context),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    auth.isAuthenticated
                        ? 'Delete Account & Purge Data'
                        : 'Purge All Local Data',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordReauthDialog extends StatefulWidget {
  const _PasswordReauthDialog();

  @override
  State<_PasswordReauthDialog> createState() => _PasswordReauthDialogState();
}

class _PasswordReauthDialogState extends State<_PasswordReauthDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify Your Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For security, please re-enter your password to permanently '
            'delete your account.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Current Password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Verify & Delete'),
        ),
      ],
    );
  }
}
