# Frontend & Mobile App Execution Reports

## Milestone Summary

| Milestone | Status | Test Results | GitHub Commit Hash | Date Completed |
| :--- | :--- | :--- | :--- | :--- |
| **FM1: Infrastructure & M3 Setup** | Completed | `flutter analyze`: 0 issues; `flutter test`: 7/7 passed | `9a7fcd0` | 2026-11-23 |
| **FM2: Form & Backend API Integration** | Completed | `flutter analyze`: 0 issues; 17 unit/widget + 1 live E2E passed | _pending commit_ | 2026-11-23 |
| **FM3: Maps & Slot Customization** | Pending | - | - | - |
| **FM4: Offline Caching & Expense Tracker** | Pending | - | - | - |
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
