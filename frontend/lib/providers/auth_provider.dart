import 'package:material_ui/material_ui.dart';

/// Holds authentication session state, Guest Mode flag, and app ThemeMode.
///
/// Firebase Auth integration is wired into this provider in Milestone FM5.
class AuthProvider extends ChangeNotifier {
  bool _isGuest = false;
  bool _isAuthenticated = false;
  String? _userEmail;
  String? _displayName;
  ThemeMode _themeMode = ThemeMode.system;

  bool get isGuest => _isGuest;
  bool get isAuthenticated => _isAuthenticated;
  bool get hasEnteredApp => _isGuest || _isAuthenticated;
  String? get userEmail => _userEmail;
  String get displayName => _displayName ?? (_isGuest ? 'Guest Traveler' : 'Traveler');
  ThemeMode get themeMode => _themeMode;

  void enterAsGuest() {
    _isGuest = true;
    _isAuthenticated = false;
    _userEmail = null;
    _displayName = 'Guest Traveler';
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void toggleDarkMode(bool enableDark) {
    setThemeMode(enableDark ? ThemeMode.dark : ThemeMode.light);
  }

  void signOut() {
    _isGuest = false;
    _isAuthenticated = false;
    _userEmail = null;
    _displayName = null;
    notifyListeners();
  }
}
