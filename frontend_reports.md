# Frontend & Mobile App Execution Reports

## Milestone Summary

| Milestone | Status | Test Results | GitHub Commit Hash | Date Completed |
| :--- | :--- | :--- | :--- | :--- |
| **FM1: Infrastructure & M3 Setup** | Completed | `flutter analyze`: 0 issues; `flutter test`: 7/7 passed | `9a7fcd0` | 2026-11-23 |
| **FM2: Form & Backend API Integration** | Completed | `flutter analyze`: 0 issues; 17 unit/widget + 1 live E2E passed | `3833239` | 2026-11-23 |
| **FM3: Maps & Slot Customization** | Completed | `flutter analyze`: 0 issues; `flutter test`: 22/22 passed | `5645f38` | 2026-11-23 |
| **FM4: Offline Caching & Expense Tracker** | Completed | `flutter analyze`: 0 issues; `flutter test`: 28/28 passed | `740dfee` | 2026-11-23 |
| **FM5: Firebase Auth & Store Release** | Pending | - | - | - |

---

## Milestone FM1 Report
- **Date:** 2026-11-23
- **Environment:** Windows 11, Flutter 3.50.1 (stable), Dart 3.14.0 (`material_ui: ^1.1.0`, `provider: ^6.1.5+1`, `intl: ^0.20.3`)
- **Features Completed:**
  - Initialized Flutter project in `frontend/` (`com.numl.ai_travel_planner`) with PRD Section 3 directory structure (`core/`, `models/`, `providers/`, `screens/`, `widgets/`).
  - `lib/core/theme/app_theme.dart`: Material 3 light & dark themes (`ColorScheme.fromSeed`) with live Dark Mode switch in Profile.
  - `lib/core/constants/` & `lib/core/utils/`: Platform-aware `ApiConstants` (`10.0.2.2:8000` on Android emulator, `127.0.0.1:8000` on Web/iOS, overridable via `--dart-define`), `AppStrings`, `AppFormatters`, and `ErrorDialogs`.
  - `lib/models/`: `TripModel`, `TripRequestModel`, `DayPlanModel`, `ActivityModel`, `ExpenseModel` aligned 1:1 with our FastAPI v1.0.1 backend schemas (including nullable GPS coordinates and `distance_warnings`).
  - `lib/screens/` & `lib/widgets/`: `WelcomeScreen` (Guest Mode entry per MFR-01), `MainShell` (Material 3 3-tab bottom `NavigationBar`: My Trips, Create Trip, Profile), `CustomButton`, `CustomTextField`, `LoadingIndicator`.
  - `test/models_test.dart`: 7 unit & widget tests verifying JSON roundtrips, request formatting, currency/distance formatting, Guest Mode navigation, Dark Mode toggling, and base widgets.
- **Flutter Analyze & Test Output:**
  ```text
  Analyzing frontend...
  No issues found!
  00:05 +7: All tests passed!
  ```
- **Notes / Observations:**
  - Updated all Material imports to `package:material_ui/material_ui.dart` for Flutter 3.50.1 compatibility (zero deprecation warnings).
  - Ready for FM2 (Trip Creation form & FastAPI backend integration).

---

## Milestone FM2 Report
- **Date:** 2026-11-23
- **Pre-FM2 Audit Fixes (from FM1 Review):**
  - Fixed DST off-by-one bug in `TripRequestModel.durationDays` by calculating inclusive days in UTC (`DateTime.utc`).
  - Fixed negative currency formatting in `AppFormatters.formatCurrency` (`-$50.5` instead of `$-50.5`).
  - Caught and fixed a real Flutter form bug in `TripCreationScreen` (switched lazy `ListView` to `SingleChildScrollView` + `Column` so scrolled-off `TextFormField` widgets stay mounted and always validate).
- **Features Completed:**
  - Added `dio: ^5.11.1` to `frontend/pubspec.yaml`.
  - `lib/services/api_service.dart`: Dio REST client (`GET /api/v1/health`, `POST /api/v1/itinerary/generate`), `X-API-Key` header support, `90s` receive timeout (covers cold Gemini + Nominatim runs), `CancelToken`, `X-Cache` parsing, and friendly mapping for `401`, `422`, `429`, `502`, `503`, `504`, and network errors.
  - `lib/providers/trip_provider.dart`: Manages active trip, trips list, generation loading state, cancellation, cache header, and error recovery.
  - `lib/screens/trip_creation/trip_creation_screen.dart`: Validated form with Destination, Date Range picker (`1–14 days`) + quick duration chips, Budget + Currency (`USD`/`EUR`/`PKR`/`AED`/`GBP`), Travel Style `SegmentedButton` (`Budget`/`Moderate`/`Luxury`), and multi-select Interest chips.
  - `lib/screens/itinerary/loading_screen.dart`: Animated step-progress loader with Cancel and Retry fallback on errors.
  - `lib/screens/itinerary/itinerary_screen.dart` & `lib/widgets/activity_card.dart`: Tabbed Day-by-Day view with time-slot badges, cost estimates, category & Verified GPS badges, `Instant Cache` pill, and Haversine `distance_warnings` alert banners.
  - `lib/screens/home/saved_trips_screen.dart`: Displays generated trips and reopens `ItineraryScreen` on tap.
  - `test/trip_creation_and_api_test.dart` & `test/live_backend_e2e_test.dart`: 10 new unit/widget tests + 1 opt-in live E2E test (`--dart-define=RUN_LIVE_E2E=true`).
- **Flutter Analyze, Test & Live E2E Output:**
  ```text
  Analyzing frontend...
  No issues found!
  00:12 +17 ~1: All tests passed! (17 unit/widget passed; live E2E skipped unless enabled)
  LIVE_E2E_OK trip_id=itinerary_82a40af6 first_cache=MISS second_cache=HIT days=1 acts=3 verified=2/3 cost=45.0 USD
  00:13 +1: All tests passed! (live Flutter -> FastAPI -> Gemini + Nominatim + DiskCache)
  ```
- **Notes / Observations:**
  - End-to-end verification confirmed zero schema mismatches between Flutter (`dio`) and FastAPI (`v1.0.1`), including live `X-Cache: MISS` → `X-Cache: HIT` caching.
  - Ready for FM3 (Interactive Maps, external navigation, and Slot Editing / Regeneration).

---

## Milestone FM3 Report
- **Date:** 2026-11-23
- **Features Completed:**
  - Added `flutter_map: ^8.3.2`, `latlong2: ^0.10.1`, and `url_launcher: ^6.3.3` to `frontend/pubspec.yaml`.
  - Configured platform URL-launch manifests: `INTERNET` + `<queries>` (`https`, `geo`) in `android/app/src/main/AndroidManifest.xml`, and `LSApplicationQueriesSchemes` (`https`, `comgooglemaps`, `maps`) in `ios/Runner/Info.plist`.
  - `lib/core/utils/map_launcher.dart`: Cross-platform external maps URI builder (Google Maps on Android/Web, Apple Maps on iOS/macOS) + `openExternalMaps`.
  - `lib/screens/map/map_screen.dart`: Interactive OpenStreetMap view (`userAgentPackageName: 'com.numl.aitravelplanner'` + `© OpenStreetMap contributors` attribution), day switcher chips, sequential `PolylineLayer`, color-coded numbered `MarkerLayer` pins, bottom preview card with "Navigate" button, and safe skipping of unverified (`null`) GPS pins.
  - `lib/screens/itinerary/slot_editor_sheet.dart`, `ApiService.regenerateSlot`, `TripProvider` (`updateActivityNotes`, `deleteActivity`, `regenerateActivitySlot`), and `ItineraryScreen` Map action button + slot editor integration.
  - `test/map_and_slot_test.dart`: 5 new test suites verifying external Maps URIs, `/api/v1/itinerary/regenerate-slot` swap + cost recalculation, note editing, activity deletion, `MapScreen` numbered pins/polylines/empty-GPS fallback, and full `SlotEditorSheet` UI flow.
- **Flutter Analyze & Test Output:**
  ```text
  Analyzing frontend...
  No issues found!
  00:22 +22 ~1: All tests passed!
  ```
- **Notes / Observations:**
  - Ready for FM4 (Offline Caching with Hive CE, Multi-Currency Expense Tracker, Weather Card & Packing Checklist).

---

## Milestone FM4 Report
- **Date:** 2026-11-23
- **Features Completed:**
  - Added pure-Dart `hive_ce: ^2.24.0` and `path_provider: ^2.1.6` to `frontend/pubspec.yaml` (deliberately avoided `hive_ce_flutter` 2.6.0 because its `native_toolchain_c` build hook fails on Windows without Visual Studio C++ tools; `Hive.init(dir.path)` on mobile/desktop + `Hive.init(null)` on Web provides identical local persistence with zero C++ toolchain requirement).
  - `lib/services/storage_service.dart`: `StorageService` interface + `HiveStorageService` (and `InMemoryStorageService` for isolated tests) storing Trips, Expenses, Weather Forecasts, Packing Checklists, Exchange Rates, and Dark Mode preferences offline across app restarts, with cascade `deleteTrip` and full `purgeAllData()` (ready for FM5 account deletion).
  - `lib/services/currency_service.dart`: Fetches live ECB rates via Frankfurter API (`https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR,PKR,AED,GBP`), caches rates in Hive, and falls back gracefully to bundled offline rates when disconnected.
  - `lib/providers/expense_provider.dart`, `lib/screens/expense/expense_screen.dart`, `lib/screens/expense/add_expense_sheet.dart`, `lib/widgets/budget_progress_bar.dart`: Multi-currency expense logging, automatic conversion into the trip's base currency, category breakdown chips, and green/amber/red budget progress bar (`<75%`, `75–95%`, `>=95%`).
  - `lib/models/weather_model.dart`, `lib/models/packing_item_model.dart`, `lib/widgets/weather_card.dart`, `lib/widgets/packing_checklist.dart`, `ApiService.getWeather`: Destination weather forecast powered by `/api/v1/weather` (cached offline per trip) and editable per-trip packing checklist with starter defaults, accessible from `ItineraryScreen` bottom sheet; `SavedTripsScreen` updated with `Offline Ready` badge and delete trip action.
  - `lib/main.dart`, `lib/providers/trip_provider.dart`, `lib/providers/auth_provider.dart`: Wired startup Hive initialization, persisted ThemeMode, automatic offline saving/loading of trips, edits, weather, and checklists.
  - `test/storage_and_expense_test.dart`: 6 new test suites verifying real `HiveStorageService` persistence across close/reopen (simulated app restart offline), cascade delete & `purgeAllData()`, `CurrencyService` live mock + offline fallback conversion, `BudgetProgressBar` thresholds, `ExpenseScreen` multi-currency UI flow, and `WeatherCard` + `PackingChecklist` widgets.
- **Bugs Caught & Fixed During Verification:**
  - Fixed a `RenderFlex` 21px horizontal overflow in `WeatherCard`'s compact daily forecast tile (widened card to `128px` and wrapped temperature text in `Expanded` with ellipsis).
  - Fixed WMO snow weather-code icon precedence (`71–77`, `85–86` checked before rain `51–82`).
- **Flutter Analyze & Test Output:**
  ```text
  Analyzing frontend...
  No issues found!
  00:14 +28 ~1: All tests passed!
  ```
- **Notes / Observations:**
  - Ready for FM5 (Firebase Auth, Account Deletion & Local Data Purge, PDF/WhatsApp Export, Crashlytics, App Icons, and Flutter CI).

---
