import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/trip_provider.dart';
import 'screens/home/main_shell.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/currency_service.dart';
import 'services/export_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safely initialize Firebase + Crashlytics when platform config files
  // (google-services.json / GoogleService-Info.plist) are present.
  // Guest Mode and offline usage continue normally if Firebase is not linked yet.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = Firebase.apps.isNotEmpty;
  } catch (e) {
    debugPrint('Firebase not configured for this build; running in Guest-safe mode: $e');
  }

  if (firebaseReady && !kIsWeb) {
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  final storage = HiveStorageService();
  await storage.init();

  runApp(AITravelPlannerApp(storageService: storage));
}

/// Root widget wiring Material 3 themes, offline storage, Auth, Export, and Providers.
class AITravelPlannerApp extends StatelessWidget {
  const AITravelPlannerApp({
    super.key,
    this.apiService,
    this.storageService,
    this.currencyService,
    this.authService,
    this.exportService,
  });

  final ApiService? apiService;
  final StorageService? storageService;
  final CurrencyService? currencyService;
  final AuthService? authService;
  final ExportService? exportService;

  @override
  Widget build(BuildContext context) {
    final storage = storageService ?? InMemoryStorageService();
    final exporter = exportService ?? const ExportService();

    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        Provider<ExportService>.value(value: exporter),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            storage: storage,
            authService: authService,
          )..loadPreferences(),
        ),
        ChangeNotifierProvider<TripProvider>(
          create: (_) => TripProvider(
            apiService: apiService,
            storage: storage,
          )..loadSavedTrips(),
        ),
        ChangeNotifierProvider<ExpenseProvider>(
          create: (_) => ExpenseProvider(
            storage: storage,
            currencyService:
                currencyService ?? CurrencyService(storage: storage),
          ),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) => MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: auth.themeMode,
          home: auth.isAuthenticated
              ? const MainShell(initialIndex: 0)
              : const WelcomeScreen(),
        ),
      ),
    );
  }
}
