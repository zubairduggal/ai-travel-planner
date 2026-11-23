import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/trip_provider.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'services/api_service.dart';
import 'services/currency_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = HiveStorageService();
  await storage.init();
  runApp(AITravelPlannerApp(storageService: storage));
}

/// Root widget wiring Material 3 themes, offline storage, and Provider state.
class AITravelPlannerApp extends StatelessWidget {
  const AITravelPlannerApp({
    super.key,
    this.apiService,
    this.storageService,
    this.currencyService,
  });

  final ApiService? apiService;
  final StorageService? storageService;
  final CurrencyService? currencyService;

  @override
  Widget build(BuildContext context) {
    final storage = storageService ?? InMemoryStorageService();
    return MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(storage: storage)..loadPreferences(),
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
          home: const WelcomeScreen(),
        ),
      ),
    );
  }
}
