import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/glass_container.dart';
import '../home/main_shell.dart';

/// Email/Password, Google Sign-In (v7+), and Sign in with Apple screen (MFR-02).
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.showAppleSignInOverride,
  });

  /// Optional test hook to force-show or hide Sign in with Apple.
  final bool? showAppleSignInOverride;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;

  bool get _shouldShowAppleSignIn {
    if (widget.showAppleSignInOverride != null) {
      return widget.showAppleSignInOverride!;
    }
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _navigateIntoApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const MainShell(initialIndex: 0),
      ),
      (_) => false,
    );
  }

  Future<void> _submitEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthProvider>();
    final ok = _isRegisterMode
        ? await auth.registerWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
          )
        : await auth.signInWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    if (!mounted) return;
    if (ok) _navigateIntoApp();
  }

  Future<void> _signInGoogle() async {
    final ok = await context.read<AuthProvider>().signInWithGoogle();
    if (!mounted) return;
    if (ok) _navigateIntoApp();
  }

  Future<void> _signInApple() async {
    final ok = await context.read<AuthProvider>().signInWithApple();
    if (!mounted) return;
    if (ok) _navigateIntoApp();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'Create Account' : 'Sign In'),
      ),
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: GlassContentConstraint(
            maxWidth: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: GlassContainer(
                borderRadius: 26,
                padding: const EdgeInsets.all(20),
                child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!auth.isFirebaseReady) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: colors.onSecondaryContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Firebase config is not linked in this build yet. '
                            'You can still explore all trip features in Guest Mode.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (auth.errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      auth.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Sign In'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Create Account'),
                    ),
                  ],
                  selected: {_isRegisterMode},
                  onSelectionChanged: (selection) {
                    context.read<AuthProvider>().clearError();
                    setState(() => _isRegisterMode = selection.first);
                  },
                ),
                const SizedBox(height: 20),
                if (_isRegisterMode) ...[
                  CustomTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    hintText: 'e.g. Muhammad Zubair',
                    prefixIcon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                ],
                CustomTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hintText: 'traveler@example.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    final text = (val ?? '').trim();
                    if (text.isEmpty || !text.contains('@')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submitEmail(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (val) {
                    if ((val ?? '').length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                CustomButton(
                  label: _isRegisterMode ? 'Create Account' : 'Sign In',
                  icon: Icons.login_rounded,
                  isLoading: auth.isBusy,
                  onPressed: auth.isBusy ? null : _submitEmail,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                CustomButton(
                  label: 'Continue with Google',
                  icon: Icons.g_mobiledata_rounded,
                  isOutlined: true,
                  onPressed: auth.isBusy ? null : _signInGoogle,
                ),
                if (_shouldShowAppleSignIn) ...[
                  const SizedBox(height: 12),
                  CustomButton(
                    label: 'Sign in with Apple',
                    icon: Icons.apple_rounded,
                    isOutlined: true,
                    onPressed: auth.isBusy ? null : _signInApple,
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: auth.isBusy
                      ? null
                      : () {
                          context.read<AuthProvider>().enterAsGuest();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute<void>(
                              builder: (_) => const MainShell(initialIndex: 0),
                            ),
                            (_) => false,
                          );
                        },
                  child: const Text('Continue as Guest instead'),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
      ),
    );
  }
}
