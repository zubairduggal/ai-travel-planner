import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/auth_service.dart';
import '../services/storage_service.dart';

/// Outcome of an Account Deletion & Local Data Purge operation (MFR-03).
enum DeleteAccountStatus {
  deleted,
  requiresRecentLogin,
  failed,
}

/// Holds authentication session state, Guest Mode, persisted ThemeMode,
/// and App Store / Play Store compliant Account Deletion (MFR-01..MFR-03).
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    this.storage,
    AuthService? authService,
  }) : _authService = authService ?? FirebaseAuthService() {
    _restoreCurrentSession();
    _authSubscription = _authService.authStateChanges.listen((user) {
      if (user != null) {
        _applyUser(user);
      } else if (_isAuthenticated) {
        _clearSessionState();
        notifyListeners();
      }
    });
  }

  static const String _themePrefKey = 'theme_mode';

  final StorageService? storage;
  final AuthService _authService;
  StreamSubscription<AuthUser?>? _authSubscription;

  bool _isGuest = false;
  bool _isAuthenticated = false;
  bool _isBusy = false;
  AuthProviderType _providerType = AuthProviderType.guest;
  String? _userId;
  String? _userEmail;
  String? _displayName;
  String? _errorMessage;
  ThemeMode _themeMode = ThemeMode.light;

  bool get isGuest => _isGuest;
  bool get isAuthenticated => _isAuthenticated;
  bool get isBusy => _isBusy;
  bool get hasEnteredApp => _isGuest || _isAuthenticated;
  bool get isFirebaseReady => _authService.isFirebaseReady;
  AuthProviderType get providerType => _providerType;
  String? get userId => _userId;
  String? get userEmail => _userEmail;
  String? get errorMessage => _errorMessage;
  String get displayName =>
      _displayName ?? (_isGuest ? 'Guest Traveler' : 'Traveler');
  ThemeMode get themeMode => _themeMode;

  void _restoreCurrentSession() {
    final existing = _authService.currentUser;
    if (existing != null) {
      _applyUser(existing, notify: false);
    }
  }

  void _applyUser(AuthUser user, {bool notify = true}) {
    _isGuest = false;
    _isAuthenticated = true;
    _providerType = user.providerType;
    _userId = user.uid;
    _userEmail = user.email;
    _displayName = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName
        : (user.email?.split('@').first ?? 'Traveler');
    _errorMessage = null;
    if (notify) notifyListeners();
  }

  void _clearSessionState() {
    _isGuest = false;
    _isAuthenticated = false;
    _providerType = AuthProviderType.guest;
    _userId = null;
    _userEmail = null;
    _displayName = null;
  }

  Future<void> loadPreferences() async {
    final savedTheme = await storage?.loadStringPref(_themePrefKey);
    if (savedTheme == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (savedTheme == 'light') {
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  void enterAsGuest() {
    _isGuest = true;
    _isAuthenticated = false;
    _providerType = AuthProviderType.guest;
    _userId = null;
    _userEmail = null;
    _displayName = 'Guest Traveler';
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return _runAuthAction(
      () => _authService.signInWithEmail(email: email, password: password),
    );
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return _runAuthAction(
      () => _authService.registerWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      ),
    );
  }

  Future<bool> signInWithGoogle() async {
    return _runAuthAction(_authService.signInWithGoogle);
  }

  Future<bool> signInWithApple() async {
    return _runAuthAction(_authService.signInWithApple);
  }

  Future<bool> _runAuthAction(Future<AuthUser> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await action();
      _isBusy = false;
      _applyUser(user);
      return true;
    } on AuthException catch (e) {
      _isBusy = false;
      if (!e.isCancelled) {
        _errorMessage = e.message;
      }
      notifyListeners();
      return false;
    } catch (_) {
      _isBusy = false;
      _errorMessage = 'Authentication failed unexpectedly. Please try again.';
      notifyListeners();
      return false;
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    if (storage != null) {
      final serialized = mode == ThemeMode.dark
          ? 'dark'
          : (mode == ThemeMode.light ? 'light' : 'system');
      unawaited(storage!.saveStringPref(_themePrefKey, serialized));
    }
    notifyListeners();
  }

  void toggleDarkMode(bool enableDark) {
    setThemeMode(enableDark ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> signOut() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      if (_isAuthenticated) {
        await _authService.signOut();
      }
    } catch (_) {
      // Always clear local session state even if remote sign-out fails offline.
    } finally {
      _isBusy = false;
      _clearSessionState();
      notifyListeners();
    }
  }

  /// Permanently deletes the user's account (if authenticated) and purges all
  /// locally cached Hive CE data (trips, expenses, packing lists, weather, prefs).
  ///
  /// Returns [DeleteAccountStatus.requiresRecentLogin] when Firebase requires
  /// fresh credentials; callers should prompt the user and call
  /// [reauthenticateAndDeleteAccount].
  Future<DeleteAccountStatus> deleteAccountAndPurgeData() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (_isAuthenticated) {
        await _authService.deleteAccount();
      }
      await storage?.purgeAllData();
      _clearSessionState();
      _themeMode = ThemeMode.system;
      _isBusy = false;
      notifyListeners();
      return DeleteAccountStatus.deleted;
    } on AuthException catch (e) {
      _isBusy = false;
      _errorMessage = e.message;
      notifyListeners();
      if (e.requiresRecentLogin) {
        return DeleteAccountStatus.requiresRecentLogin;
      }
      return DeleteAccountStatus.failed;
    } catch (_) {
      _isBusy = false;
      _errorMessage = 'Could not complete account deletion. Please try again.';
      notifyListeners();
      return DeleteAccountStatus.failed;
    }
  }

  /// Re-authenticates the active session according to its provider, then
  /// completes permanent account deletion and local Hive CE data purge.
  Future<DeleteAccountStatus> reauthenticateAndDeleteAccount({
    String? password,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      switch (_providerType) {
        case AuthProviderType.emailPassword:
          if (password == null || password.isEmpty) {
            throw const AuthException(
              code: 'missing-password',
              message: 'Please enter your password to confirm deletion.',
            );
          }
          await _authService.reauthenticateWithPassword(password);
        case AuthProviderType.google:
          await _authService.reauthenticateWithGoogle();
        case AuthProviderType.apple:
          await _authService.reauthenticateWithApple();
        case AuthProviderType.guest:
          break;
      }

      if (_isAuthenticated) {
        await _authService.deleteAccount();
      }
      await storage?.purgeAllData();
      _clearSessionState();
      _themeMode = ThemeMode.system;
      _isBusy = false;
      notifyListeners();
      return DeleteAccountStatus.deleted;
    } on AuthException catch (e) {
      _isBusy = false;
      if (!e.isCancelled) {
        _errorMessage = e.message;
      }
      notifyListeners();
      return DeleteAccountStatus.failed;
    } catch (_) {
      _isBusy = false;
      _errorMessage = 'Re-authentication failed. Please try again.';
      notifyListeners();
      return DeleteAccountStatus.failed;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
