import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/api_constants.dart';
import '../../providers/auth_provider.dart';
import '../onboarding/welcome_screen.dart';

/// User Profile & Settings screen (Material 3 theme toggle; Auth & Delete in FM5).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                auth.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                auth.isGuest
                    ? 'Guest Mode • Data stays on this device'
                    : (auth.userEmail ?? 'Signed in'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              ),
              title: const Text('Dark Mode'),
              subtitle: const Text('Switch between Material 3 light & dark themes'),
              value: isDark,
              onChanged: (value) => auth.toggleDarkMode(value),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Backend API URL'),
              subtitle: Text(ApiConstants.baseUrl),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              auth.signOut();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => const WelcomeScreen(),
                ),
              );
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(auth.isGuest ? 'Exit Guest Mode' : 'Sign Out'),
          ),
        ],
      ),
    );
  }
}
