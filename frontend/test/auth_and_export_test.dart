import 'dart:async';
import 'dart:convert';

import 'package:ai_travel_planner/main.dart';
import 'package:ai_travel_planner/models/activity_model.dart';
import 'package:ai_travel_planner/models/day_plan_model.dart';
import 'package:ai_travel_planner/models/expense_model.dart';
import 'package:ai_travel_planner/models/packing_item_model.dart';
import 'package:ai_travel_planner/models/trip_model.dart';
import 'package:ai_travel_planner/providers/auth_provider.dart';
import 'package:ai_travel_planner/providers/expense_provider.dart';
import 'package:ai_travel_planner/providers/trip_provider.dart';
import 'package:ai_travel_planner/screens/auth/auth_screen.dart';
import 'package:ai_travel_planner/screens/itinerary/itinerary_screen.dart';
import 'package:ai_travel_planner/screens/profile/profile_screen.dart';
import 'package:ai_travel_planner/services/auth_service.dart';
import 'package:ai_travel_planner/services/export_service.dart';
import 'package:ai_travel_planner/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class _FakeAuthService implements AuthService {
  _FakeAuthService({
    this.requireRecentLoginOnDelete = false,
  });

  static const String _validReauthPassword = 'secret123';
  final bool requireRecentLoginOnDelete;

  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  bool _recentlyReauthenticated = false;
  bool deleteCalled = false;
  bool googleSignInCalled = false;
  bool appleSignInCalled = false;

  @override
  bool get isFirebaseReady => true;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void _setUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final user = AuthUser(
      uid: 'uid_email_1',
      email: email,
      displayName: 'Zubair Traveler',
      providerType: AuthProviderType.emailPassword,
    );
    _setUser(user);
    return user;
  }

  @override
  Future<AuthUser> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final user = AuthUser(
      uid: 'uid_reg_1',
      email: email,
      displayName: displayName ?? 'New Traveler',
      providerType: AuthProviderType.emailPassword,
    );
    _setUser(user);
    return user;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    googleSignInCalled = true;
    const user = AuthUser(
      uid: 'uid_google_1',
      email: 'google@example.com',
      displayName: 'Google Traveler',
      providerType: AuthProviderType.google,
    );
    _setUser(user);
    return user;
  }

  @override
  Future<AuthUser> signInWithApple() async {
    appleSignInCalled = true;
    const user = AuthUser(
      uid: 'uid_apple_1',
      email: 'apple@privaterelay.appleid.com',
      displayName: 'Apple Traveler',
      providerType: AuthProviderType.apple,
    );
    _setUser(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _setUser(null);
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    if (password != _validReauthPassword) {
      throw const AuthException(
        code: 'invalid-credential',
        message: 'Incorrect password.',
      );
    }
    _recentlyReauthenticated = true;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    _recentlyReauthenticated = true;
  }

  @override
  Future<void> reauthenticateWithApple() async {
    _recentlyReauthenticated = true;
  }

  @override
  Future<void> deleteAccount() async {
    if (requireRecentLoginOnDelete && !_recentlyReauthenticated) {
      throw const AuthException(
        code: 'requires-recent-login',
        message: 'Please re-authenticate before deleting your account.',
      );
    }
    deleteCalled = true;
    _setUser(null);
  }
}

TripModel _sampleTrip({String currency = 'PKR'}) {
  return TripModel(
    tripId: 'trip_fm5',
    destination: 'Hunza Valley, Pakistan',
    durationDays: 2,
    totalEstimatedCost: 15000,
    currency: currency,
    travelStyle: 'Moderate',
    startDate: DateTime(2026, 7, 10),
    endDate: DateTime(2026, 7, 11),
    targetBudget: 25000,
    days: const [
      DayPlanModel(
        dayNumber: 1,
        title: 'Karimabad Heritage — Day One',
        totalDistanceKm: 12.4,
        feasible: true,
        activities: [
          ActivityModel(
            activityId: 'a1',
            timeSlot: 'Morning',
            title: 'Baltit Fort Tour',
            description: 'Historic 700-year-old fort overlooking the valley.',
            category: 'Historical',
            estimatedCost: 5000,
            notes: 'Bring warm jacket & camera',
            latitude: 36.3256,
            longitude: 74.6678,
            verified: true,
          ),
          ActivityModel(
            activityId: 'a2',
            timeSlot: 'Evening',
            title: 'Eagle Nest Sunset',
            description: 'Golden hour viewpoint over Rakaposhi.',
            category: 'Nature',
            estimatedCost: 10000,
            latitude: 36.3210,
            longitude: 74.6820,
            verified: true,
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('ExportService (Offline PDF & WhatsApp Text Summary - MFR-12)', () {
    const exporter = ExportService();

    test('safePdfFilename sanitizes destination cleanly', () {
      expect(
        exporter.safePdfFilename(_sampleTrip()),
        'hunza_valley_pakistan_itinerary.pdf',
      );
    });

    test('formatTextSummary includes schedule, notes, expenses, and packing', () {
      final trip = _sampleTrip(currency: 'USD');
      final expenses = [
        ExpenseModel(
          expenseId: 'e1',
          tripId: trip.tripId,
          title: 'Apricot Soup Lunch',
          amount: 12.5,
          currency: 'USD',
          category: 'Food',
          date: DateTime(2026, 7, 10),
        ),
      ];
      final packing = [
        const PackingItemModel(
          id: 'p1',
          title: 'Passport',
          category: 'Documents',
          isPacked: true,
        ),
        const PackingItemModel(
          id: 'p2',
          title: 'Rain Jacket',
          category: 'Clothing',
          isPacked: false,
        ),
      ];

      final summary = exporter.formatTextSummary(
        trip,
        expenses: expenses,
        packingList: packing,
      );

      expect(summary, contains('Hunza Valley, Pakistan'));
      expect(summary, contains('Day 1: Karimabad Heritage'));
      expect(summary, contains('[Morning] Baltit Fort Tour'));
      expect(summary, contains('Note: Bring warm jacket & camera'));
      expect(summary, contains('Apricot Soup Lunch (Food)'));
      expect(summary, contains('Packing Checklist (1/2 packed)'));
      expect(summary, contains('[x] Passport'));
      expect(summary, contains('[ ] Rain Jacket'));
    });

    test('buildItineraryPdfBytes generates valid offline PDF with PKR/Unicode', () async {
      final trip = _sampleTrip(currency: 'PKR');
      final bytes = await exporter.buildItineraryPdfBytes(
        trip,
        expenses: [
          ExpenseModel(
            expenseId: 'e1',
            tripId: trip.tripId,
            title: 'Chai & Samosa',
            amount: 500,
            currency: 'PKR',
            category: 'Food',
            date: DateTime(2026, 7, 10),
          ),
        ],
        packingList: PackingItemModel.defaultItems(),
      );

      expect(bytes.length, greaterThan(1000));
      // Valid PDF magic header "%PDF-".
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('AuthProvider & Account Deletion / Local Purge (MFR-01..MFR-03)', () {
    test('unconfigured FirebaseAuthService fails gracefully without crashing', () async {
      final service = FirebaseAuthService();
      expect(service.isFirebaseReady, isFalse);
      expect(service.currentUser, isNull);

      final provider = AuthProvider(
        storage: InMemoryStorageService(),
        authService: service,
      );
      final ok = await provider.signInWithEmail(
        email: 'a@b.com',
        password: 'password123',
      );
      expect(ok, isFalse);
      expect(provider.errorMessage, contains('Firebase is not configured'));
    });

    test('transitions Guest -> Email Auth -> Google -> Apple -> Sign Out', () async {
      final fakeAuth = _FakeAuthService();
      final storage = InMemoryStorageService();
      final provider = AuthProvider(storage: storage, authService: fakeAuth);

      provider.enterAsGuest();
      expect(provider.isGuest, isTrue);
      expect(provider.isAuthenticated, isFalse);

      expect(
        await provider.signInWithEmail(
          email: 'zubair@numl.edu.pk',
          password: 'password123',
        ),
        isTrue,
      );
      expect(provider.isAuthenticated, isTrue);
      expect(provider.isGuest, isFalse);
      expect(provider.providerType, AuthProviderType.emailPassword);
      expect(provider.userEmail, 'zubair@numl.edu.pk');

      expect(await provider.signInWithGoogle(), isTrue);
      expect(fakeAuth.googleSignInCalled, isTrue);
      expect(provider.providerType, AuthProviderType.google);

      expect(await provider.signInWithApple(), isTrue);
      expect(fakeAuth.appleSignInCalled, isTrue);
      expect(provider.providerType, AuthProviderType.apple);

      await provider.signOut();
      expect(provider.isAuthenticated, isFalse);
      expect(provider.isGuest, isFalse);
    });

    test('requires-recent-login triggers re-auth then deletes account & purges storage', () async {
      final fakeAuth = _FakeAuthService(requireRecentLoginOnDelete: true);
      final storage = InMemoryStorageService();
      await storage.saveTrip(_sampleTrip());
      await storage.saveStringPref('theme_mode', 'dark');

      final provider = AuthProvider(storage: storage, authService: fakeAuth);
      await provider.signInWithEmail(
        email: 'zubair@numl.edu.pk',
        password: 'secret123',
      );

      // First delete attempt detects stale session and preserves local data.
      final firstAttempt = await provider.deleteAccountAndPurgeData();
      expect(firstAttempt, DeleteAccountStatus.requiresRecentLogin);
      expect(fakeAuth.deleteCalled, isFalse);
      expect((await storage.loadTrips()).length, 1);

      // Re-authenticate with wrong password fails safely.
      final wrongPass = await provider.reauthenticateAndDeleteAccount(
        password: 'wrong',
      );
      expect(wrongPass, DeleteAccountStatus.failed);
      expect((await storage.loadTrips()).length, 1);

      // Re-authenticate with valid password deletes account & wipes Hive data.
      final secondAttempt = await provider.reauthenticateAndDeleteAccount(
        password: 'secret123',
      );
      expect(secondAttempt, DeleteAccountStatus.deleted);
      expect(fakeAuth.deleteCalled, isTrue);
      expect(provider.isAuthenticated, isFalse);
      expect(await storage.loadTrips(), isEmpty);
      expect(await storage.loadStringPref('theme_mode'), isNull);
    });
  });

  group('FM5 Widget Flows (AuthScreen, Profile Deletion, Itinerary Export)', () {
    testWidgets('AuthScreen validates email/password and signs in via Google & Apple', (
      tester,
    ) async {
      final fakeAuth = _FakeAuthService();
      final storage = InMemoryStorageService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            ChangeNotifierProvider(
              create: (_) => AuthProvider(
                storage: storage,
                authService: fakeAuth,
              ),
            ),
            ChangeNotifierProvider(create: (_) => TripProvider(storage: storage)),
            ChangeNotifierProvider(
              create: (_) => ExpenseProvider(storage: storage),
            ),
          ],
          child: const MaterialApp(
            home: AuthScreen(showAppleSignInOverride: true),
          ),
        ),
      );

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsOneWidget);

      // Tap Sign In button with empty fields -> validation errors shown.
      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters'), findsOneWidget);

      // Tap Continue with Google -> authenticates and navigates into MainShell.
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(fakeAuth.googleSignInCalled, isTrue);
      expect(find.text('My Trips'), findsWidgets);
    });

    testWidgets('ProfileScreen handles requires-recent-login password dialog & purges data', (
      tester,
    ) async {
      final fakeAuth = _FakeAuthService(requireRecentLoginOnDelete: true);
      final storage = InMemoryStorageService();
      final trip = _sampleTrip();
      await storage.saveTrip(trip);

      final authProvider = AuthProvider(storage: storage, authService: fakeAuth);
      await authProvider.signInWithEmail(
        email: 'zubair@numl.edu.pk',
        password: 'secret123',
      );
      final tripProvider = TripProvider(storage: storage);
      await tripProvider.loadSavedTrips();
      final expenseProvider = ExpenseProvider(storage: storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StorageService>.value(value: storage),
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: tripProvider),
            ChangeNotifierProvider.value(value: expenseProvider),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );

      expect(find.text('Delete Account & Purge Data'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Delete Account & Purge Data'),
        200,
      );
      await tester.tap(find.text('Delete Account & Purge Data'));
      await tester.pumpAndSettle();

      // Confirm permanent deletion.
      await tester.tap(find.text('Delete Permanently'));
      await tester.pumpAndSettle();

      // Password re-authentication dialog appears.
      expect(find.text('Verify Your Password'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.tap(find.text('Verify & Delete'));
      await tester.pumpAndSettle();

      expect(fakeAuth.deleteCalled, isTrue);
      expect(tripProvider.trips, isEmpty);
      expect(await storage.loadTrips(), isEmpty);
      // Returned to WelcomeScreen.
      expect(find.text('Explore as Guest'), findsOneWidget);
    });

    testWidgets('ItineraryScreen opens Export & Share bottom sheet', (
      tester,
    ) async {
      final trip = _sampleTrip();
      final storage = InMemoryStorageService();
      final tripProvider = TripProvider(storage: storage)..selectTrip(trip);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ExportService>.value(value: const ExportService()),
            ChangeNotifierProvider.value(value: tripProvider),
            ChangeNotifierProvider(
              create: (_) => ExpenseProvider(storage: storage),
            ),
          ],
          child: MaterialApp(home: ItineraryScreen(trip: trip)),
        ),
      );

      await tester.tap(find.byTooltip('Export & Share'));
      await tester.pumpAndSettle();

      expect(find.text('Export & Share Itinerary'), findsOneWidget);
      expect(find.text('Share Offline PDF'), findsOneWidget);
      expect(find.text('Print / Save PDF'), findsOneWidget);
      expect(find.text('Share Text Summary (WhatsApp)'), findsOneWidget);
    });

    testWidgets('AITravelPlannerApp auto-opens MainShell when already signed in', (
      tester,
    ) async {
      final fakeAuth = _FakeAuthService();
      await fakeAuth.signInWithGoogle();

      await tester.pumpWidget(
        AITravelPlannerApp(
          authService: fakeAuth,
          storageService: InMemoryStorageService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Trips'), findsWidgets);
    });
  });
}
