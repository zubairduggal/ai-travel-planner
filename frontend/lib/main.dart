import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/trip_provider.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AITravelPlannerApp());
}

/// Root widget wiring Material 3 themes and top-level Provider state.
class AITravelPlannerApp extends StatelessWidget {
  const AITravelPlannerApp({
    super.key,
    this.apiService,
  });

  final ApiService? apiService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProvider<TripProvider>(
          create: (_) => TripProvider(apiService: apiService),
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
