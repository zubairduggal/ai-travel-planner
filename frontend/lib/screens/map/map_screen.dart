import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_dialogs.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/map_launcher.dart';
import '../../models/activity_model.dart';
import '../../models/day_plan_model.dart';
import '../../models/place_option_model.dart';
import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/glass_container.dart';

/// Interactive OpenStreetMap screen usable both as a dedicated top-level Map tab
/// (with optional [trip]) and pushed from ItineraryScreen (MFR-08, MFR-09),
/// with interactive Hotel & Food price-tag pins and live TripProvider sync.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.trip,
    this.initialDayNumber = 1,
    this.initialOptionId,
    this.initialCategory,
    this.showTileLayer = true,
    this.isTab = false,
    this.onStartTrip,
  });

  /// When null, displays the active/latest saved trip or an Explore map.
  final TripModel? trip;
  final int initialDayNumber;

  /// Optional hotel/dining option ID to pre-focus and open on mount.
  final String? initialOptionId;

  /// Optional initial category filter: `'all'`, `'spots'`, `'hotels'`, or `'food'`.
  final String? initialCategory;

  /// Disabled in offline widget tests to avoid live OSM tile requests.
  final bool showTileLayer;

  /// True when hosted inside MainShell's bottom tab bar.
  final bool isTab;

  /// Invoked when tapping "Start a Trip" from the Explore Map view.
  final void Function({String? destination, double? budget})? onStartTrip;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

const _validCategories = {'all', 'spots', 'hotels', 'food'};

class _MapScreenState extends State<MapScreen> {
  static const Color _hotelPinColor = Color(0xFF3730A3); // Deep Indigo
  static const Color _foodPinColor = Color(0xFF0F766E); // Emerald / Teal

  final MapController _mapController = MapController();
  late int _selectedDayNumber;
  late String _selectedCategory;
  String? _selectedTripId;
  ActivityModel? _selectedActivity;
  String? _selectedOptionId;
  bool _selectedOptionIsHotel = false;

  @override
  void initState() {
    super.initState();
    _selectedDayNumber = widget.initialDayNumber;
    _selectedTripId = widget.trip?.tripId;
    final rawCat = widget.initialCategory?.toLowerCase() ?? 'all';
    _selectedCategory = _validCategories.contains(rawCat) ? rawCat : 'all';
    _selectedOptionId = widget.initialOptionId;

    final initialTrip = widget.trip;
    if (_selectedOptionId != null && initialTrip != null) {
      if (initialTrip.hotelOptions.any((h) => h.optionId == _selectedOptionId)) {
        _selectedOptionIsHotel = true;
      } else if (initialTrip.diningOptions
          .any((d) => d.optionId == _selectedOptionId)) {
        _selectedOptionIsHotel = false;
      }
    }
  }

  TripProvider? _maybeReadTripProvider(BuildContext context) {
    try {
      return context.watch<TripProvider>();
    } catch (_) {
      return null;
    }
  }

  TripModel? _resolveTrip(TripProvider? provider) {
    if (widget.trip != null) {
      if (provider != null) {
        if (provider.activeTrip?.tripId == widget.trip!.tripId) {
          return provider.activeTrip;
        }
        for (final t in provider.trips) {
          if (t.tripId == widget.trip!.tripId) return t;
        }
      }
      return widget.trip;
    }
    if (provider == null) return null;
    if (_selectedTripId != null) {
      for (final t in provider.trips) {
        if (t.tripId == _selectedTripId) return t;
      }
    }
    return provider.activeTrip ??
        (provider.trips.isNotEmpty ? provider.trips.first : null);
  }

  DayPlanModel? _resolveDay(TripModel trip) {
    for (final day in trip.days) {
      if (day.dayNumber == _selectedDayNumber) return day;
    }
    return trip.days.isNotEmpty ? trip.days.first : null;
  }

  List<ActivityModel> _locatedActivitiesFor(DayPlanModel? day) {
    if (day == null) return const [];
    return day.activities.where((a) => a.hasCoordinates).toList();
  }

  List<PlaceOptionModel> _locatedHotelsFor(TripModel trip) {
    return trip.hotelOptions.where((h) => h.hasCoordinates).toList();
  }

  List<PlaceOptionModel> _locatedDiningFor(TripModel trip) {
    return trip.diningOptions.where((d) => d.hasCoordinates).toList();
  }

  PlaceOptionModel? _resolveSelectedOption(TripModel trip) {
    if (_selectedOptionId == null) return null;
    for (final h in trip.hotelOptions) {
      if (h.optionId == _selectedOptionId) {
        _selectedOptionIsHotel = true;
        return h;
      }
    }
    for (final d in trip.diningOptions) {
      if (d.optionId == _selectedOptionId) {
        _selectedOptionIsHotel = false;
        return d;
      }
    }
    return null;
  }

  LatLng _computeCenterPoints(List<LatLng> pts) {
    if (pts.isEmpty) {
      return const LatLng(33.6844, 73.0479);
    }
    final avgLat = pts.fold<double>(0, (s, p) => s + p.latitude) / pts.length;
    final avgLon = pts.fold<double>(0, (s, p) => s + p.longitude) / pts.length;
    return LatLng(avgLat, avgLon);
  }

  void _safeMove(LatLng center, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(center, zoom);
      } catch (_) {
        // Ignore if FlutterMap was not yet mounted during transition.
      }
    });
  }

  void _selectDay(TripModel trip, int dayNumber) {
    setState(() {
      _selectedDayNumber = dayNumber;
      _selectedActivity = null;
      _selectedOptionId = null;
    });
    final pts = _visiblePoints(trip);
    if (pts.isNotEmpty) {
      _safeMove(_computeCenterPoints(pts), pts.length == 1 ? 14.5 : 12.5);
    }
  }

  void _selectCategory(TripModel trip, String category) {
    setState(() {
      _selectedCategory = category;
      if (category == 'hotels' || category == 'food') {
        _selectedActivity = null;
      }
      if (category == 'spots') {
        _selectedOptionId = null;
      } else if (category == 'hotels' && !_selectedOptionIsHotel) {
        _selectedOptionId = null;
      } else if (category == 'food' && _selectedOptionIsHotel) {
        _selectedOptionId = null;
      }
    });
    final pts = _visiblePoints(trip);
    if (pts.isNotEmpty) {
      _safeMove(_computeCenterPoints(pts), pts.length == 1 ? 14.5 : 12.8);
    }
  }

  List<LatLng> _visiblePoints(TripModel trip) {
    final pts = <LatLng>[];
    if (_selectedCategory == 'all' || _selectedCategory == 'spots') {
      for (final a in _locatedActivitiesFor(_resolveDay(trip))) {
        pts.add(LatLng(a.latitude!, a.longitude!));
      }
    }
    if (_selectedCategory == 'all' || _selectedCategory == 'hotels') {
      for (final h in _locatedHotelsFor(trip)) {
        pts.add(LatLng(h.latitude!, h.longitude!));
      }
    }
    if (_selectedCategory == 'all' || _selectedCategory == 'food') {
      for (final d in _locatedDiningFor(trip)) {
        pts.add(LatLng(d.latitude!, d.longitude!));
      }
    }
    return pts;
  }

  void _selectTrip(TripModel trip) {
    final firstDay = trip.days.isNotEmpty ? trip.days.first.dayNumber : 1;
    setState(() {
      _selectedTripId = trip.tripId;
      _selectedDayNumber = firstDay;
      _selectedActivity = null;
      _selectedOptionId = null;
    });
    final pts = _visiblePoints(trip);
    if (pts.isNotEmpty) {
      _safeMove(_computeCenterPoints(pts), pts.length == 1 ? 14.0 : 12.5);
    }
  }

  Color _markerColor(String slot) {
    final lower = slot.toLowerCase();
    if (lower.contains('morning')) return AppTheme.coralPrimary;
    if (lower.contains('afternoon')) return AppTheme.warmGold;
    return AppTheme.mintText;
  }

  Future<void> _navigateToCoords({
    required double latitude,
    required double longitude,
    required String label,
  }) async {
    final launched = await MapLauncher.openExternalMaps(
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
    if (!launched && mounted) {
      ErrorDialogs.showSnackBar(
        context,
        'Could not open an external Maps app on this device.',
        isError: true,
      );
    }
  }

  Future<void> _launchLiveRateSearch(
    String placeName,
    String destination,
  ) async {
    final uri = Uri.https(
      'www.google.com',
      '/search',
      {'q': '$placeName $destination price'},
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ErrorDialogs.showSnackBar(
          context,
          'Could not open browser for live rate.',
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        ErrorDialogs.showSnackBar(
          context,
          'Could not open browser for live rate.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = _maybeReadTripProvider(context);
    final trip = _resolveTrip(provider);
    final allTrips = provider?.trips ?? const <TripModel>[];
    final bottomInset = widget.isTab ? 104.0 : 18.0;

    if (trip == null) {
      return _buildEmptyMap(context, bottomInset: bottomInset);
    }
    return _buildTripMap(
      context,
      trip: trip,
      provider: provider,
      allTrips: allTrips,
      bottomInset: bottomInset,
    );
  }

  Widget _buildEmptyMap(
    BuildContext context, {
    required double bottomInset,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.isTab ? null : AppBar(title: const Text('Trip Map')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(30.3753, 69.3451),
              initialZoom: 5.5,
            ),
            children: [
              if (widget.showTileLayer)
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.numl.ai_travel_planner',
                ),
              const MarkerLayer(markers: []),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          // Floating Glass Header Pill
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GlassContainer(
                  borderRadius: 24,
                  opacity: 0.84,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.map_rounded,
                        color: AppTheme.coralPrimary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Trip Map',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const MintStatusPill(label: '0 Pins'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom Floating Glass Prompt Card
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomInset,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GlassContainer(
                  borderRadius: 24,
                  opacity: 0.90,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'No Trip Pins Yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Generate a trip to see your verified spots, hotels, and food prices pinned on the map.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CustomButton(
                        label: 'Create a Trip',
                        icon: Icons.add_location_alt_rounded,
                        onPressed: () => widget.onStartTrip?.call(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripMap(
    BuildContext context, {
    required TripModel trip,
    required TripProvider? provider,
    required List<TripModel> allTrips,
    required double bottomInset,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentDay = _resolveDay(trip);
    final activeDayNumber = currentDay?.dayNumber ?? 1;

    final showSpots =
        _selectedCategory == 'all' || _selectedCategory == 'spots';
    final showHotels =
        _selectedCategory == 'all' || _selectedCategory == 'hotels';
    final showFood =
        _selectedCategory == 'all' || _selectedCategory == 'food';

    final locatedSpots = showSpots
        ? _locatedActivitiesFor(currentDay)
        : const <ActivityModel>[];
    final locatedHotels = showHotels
        ? _locatedHotelsFor(trip)
        : const <PlaceOptionModel>[];
    final locatedFood = showFood
        ? _locatedDiningFor(trip)
        : const <PlaceOptionModel>[];

    final spotPoints =
        locatedSpots.map((a) => LatLng(a.latitude!, a.longitude!)).toList();
    final allVisiblePoints = <LatLng>[
      ...spotPoints,
      for (final h in locatedHotels) LatLng(h.latitude!, h.longitude!),
      for (final d in locatedFood) LatLng(d.latitude!, d.longitude!),
    ];

    final selectedOption = _resolveSelectedOption(trip);
    final initialCenter =
        (selectedOption != null && selectedOption.hasCoordinates)
            ? LatLng(selectedOption.latitude!, selectedOption.longitude!)
            : _computeCenterPoints(allVisiblePoints);
    final initialZoom =
        (selectedOption != null && selectedOption.hasCoordinates)
            ? 15.0
            : (allVisiblePoints.length == 1 ? 14.0 : 12.5);
    final topSafe = MediaQuery.of(context).padding.top;
    final totalVisiblePins =
        locatedSpots.length + locatedHotels.length + locatedFood.length;

    return Scaffold(
      appBar: widget.isTab
          ? null
          : AppBar(title: Text('${trip.destination} Map')),
      body: Stack(
        children: [
          if (allVisiblePoints.isEmpty)
            GlassScaffoldBackground(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GlassContainer(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_off_outlined,
                          size: 52,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedCategory == 'hotels'
                              ? 'No verified hotel pins available'
                              : _selectedCategory == 'food'
                                  ? 'No verified food pins available'
                                  : 'No verified GPS pins for Day $activeDayNumber',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Activities without map coordinates are safely skipped.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: initialZoom,
                onTap: (_, _) => setState(() {
                  _selectedActivity = null;
                  _selectedOptionId = null;
                }),
              ),
              children: [
                if (widget.showTileLayer)
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.numl.ai_travel_planner',
                  ),
                if (showSpots && spotPoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: spotPoints,
                        strokeWidth: 4.5,
                        color: AppTheme.coralPrimary,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    // Attraction / Spot Coral numbered pins
                    for (var i = 0; i < locatedSpots.length; i++)
                      Marker(
                        point: spotPoints[i],
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedActivity = locatedSpots[i];
                            _selectedOptionId = null;
                          }),
                          child: _NumberedMarker(
                            number: i + 1,
                            color: _markerColor(locatedSpots[i].timeSlot),
                            selected: _selectedActivity?.activityId ==
                                locatedSpots[i].activityId,
                          ),
                        ),
                      ),
                    // Hotel Deep Indigo price-tag pins
                    for (final hotel in locatedHotels)
                      Marker(
                        point: LatLng(hotel.latitude!, hotel.longitude!),
                        width: 112,
                        height: 36,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedActivity = null;
                              _selectedOptionId = hotel.optionId;
                              _selectedOptionIsHotel = true;
                            });
                            _safeMove(
                              LatLng(hotel.latitude!, hotel.longitude!),
                              14.8,
                            );
                          },
                          child: _PriceTagMarker(
                            icon: Icons.hotel_rounded,
                            priceLabel: AppFormatters.formatCompactPrice(
                              hotel.estimatedPrice,
                              trip.currency,
                            ),
                            backgroundColor: _hotelPinColor,
                            isTripSelected: hotel.selected,
                            isFocused: _selectedOptionId == hotel.optionId,
                          ),
                        ),
                      ),
                    // Food Emerald/Teal price-tag pins
                    for (final dining in locatedFood)
                      Marker(
                        point: LatLng(dining.latitude!, dining.longitude!),
                        width: 112,
                        height: 36,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedActivity = null;
                              _selectedOptionId = dining.optionId;
                              _selectedOptionIsHotel = false;
                            });
                            _safeMove(
                              LatLng(dining.latitude!, dining.longitude!),
                              14.8,
                            );
                          },
                          child: _PriceTagMarker(
                            icon: Icons.restaurant_rounded,
                            priceLabel: AppFormatters.formatCompactPrice(
                              dining.estimatedPrice,
                              trip.currency,
                            ),
                            backgroundColor: _foodPinColor,
                            isTripSelected: dining.selected,
                            isFocused: _selectedOptionId == dining.optionId,
                          ),
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),

          // Floating Glass Trip + Day + Category Filter Chips Overlay
          Positioned(
            top: widget.isTab ? topSafe + 10 : 10,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isTab)
                  GlassContainer(
                    borderRadius: 22,
                    opacity: 0.86,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.map_rounded,
                          color: AppTheme.coralPrimary,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${trip.destination} Map',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (allTrips.length > 1 && widget.trip == null)
                          PopupMenuButton<TripModel>(
                            tooltip: 'Switch trip',
                            onSelected: _selectTrip,
                            itemBuilder: (_) => [
                              for (final t in allTrips)
                                PopupMenuItem(
                                  value: t,
                                  child: Text(t.destination),
                                ),
                            ],
                            child: const MintStatusPill(
                              icon: Icons.swap_horiz_rounded,
                              label: 'Switch',
                            ),
                          )
                        else
                          MintStatusPill(
                            label: '$totalVisiblePins pins',
                          ),
                      ],
                    ),
                  ),
                if (trip.days.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: trip.days.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final day = trip.days[index];
                        final selected = day.dayNumber == activeDayNumber;
                        return _FloatingGlassChip(
                          label: 'Day ${day.dayNumber}',
                          selected: selected,
                          onTap: () => _selectDay(trip, day.dayNumber),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FloatingGlassChip(
                        icon: Icons.layers_rounded,
                        label: 'All',
                        selected: _selectedCategory == 'all',
                        onTap: () => _selectCategory(trip, 'all'),
                      ),
                      const SizedBox(width: 6),
                      _FloatingGlassChip(
                        icon: Icons.place_rounded,
                        label: 'Spots',
                        selected: _selectedCategory == 'spots',
                        onTap: () => _selectCategory(trip, 'spots'),
                      ),
                      const SizedBox(width: 6),
                      _FloatingGlassChip(
                        icon: Icons.hotel_rounded,
                        label: 'Hotels',
                        selected: _selectedCategory == 'hotels',
                        onTap: () => _selectCategory(trip, 'hotels'),
                      ),
                      const SizedBox(width: 6),
                      _FloatingGlassChip(
                        icon: Icons.restaurant_rounded,
                        label: 'Food',
                        selected: _selectedCategory == 'food',
                        onTap: () => _selectCategory(trip, 'food'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Frosted-Glass Selected Activity Pin Detail Card
          if (_selectedActivity != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomInset,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GlassContainer(
                    borderRadius: 24,
                    opacity: 0.90,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedActivity!.timeSlot,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: AppTheme.coralPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedActivity!.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const MintStatusPill(
                              icon: Icons.verified_outlined,
                              label: 'Verified',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedActivity!.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CompactInfoPair(
                                icon: Icons.place_rounded,
                                label: 'Location',
                                value: _selectedActivity!.category,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CompactInfoPair(
                                icon: Icons.payments_rounded,
                                label: 'Est. Cost',
                                value: _selectedActivity!.estimatedCost == 0
                                    ? 'Free'
                                    : AppFormatters.formatCurrency(
                                        _selectedActivity!.estimatedCost,
                                        trip.currency,
                                      ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        CustomButton(
                          label: 'Navigate',
                          icon: Icons.directions_rounded,
                          onPressed: () {
                            if (!_selectedActivity!.hasCoordinates) return;
                            _navigateToCoords(
                              latitude: _selectedActivity!.latitude!,
                              longitude: _selectedActivity!.longitude!,
                              label: _selectedActivity!.title,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Frosted-Glass Selected Hotel / Food Comparison Bottom Card
          if (selectedOption != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomInset,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _MapOptionComparisonCard(
                    option: selectedOption,
                    isHotel: _selectedOptionIsHotel,
                    currency: trip.currency,
                    liveTripTotal: trip.effectiveTotalCost,
                    onClose: () => setState(() => _selectedOptionId = null),
                    onToggleSelect: () {
                      if (provider == null) return;
                      if (_selectedOptionIsHotel) {
                        provider.selectHotelOption(
                          trip.tripId,
                          selectedOption.optionId,
                        );
                      } else {
                        provider.toggleDiningOption(
                          trip.tripId,
                          selectedOption.optionId,
                        );
                      }
                    },
                    onCheckLiveRate: () => _launchLiveRateSearch(
                      selectedOption.name,
                      trip.destination,
                    ),
                    onNavigate: () {
                      if (!selectedOption.hasCoordinates) return;
                      _navigateToCoords(
                        latitude: selectedOption.latitude!,
                        longitude: selectedOption.longitude!,
                        label: selectedOption.name,
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactInfoPair extends StatelessWidget {
  const _CompactInfoPair({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.coralPrimary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: AppTheme.coralPrimary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NumberedMarker extends StatelessWidget {
  const _NumberedMarker({
    required this.number,
    required this.color,
    required this.selected,
  });

  final int number;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.22 : 1.0,
      duration: const Duration(milliseconds: 160),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.42),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _FloatingGlassChip extends StatelessWidget {
  const _FloatingGlassChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (selected) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: AppTheme.coralGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppTheme.coralPrimary.withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13.5, color: Colors.white),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GlassContainer(
      borderRadius: 22,
      opacity: 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13.5, color: AppTheme.coralPrimary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceTagMarker extends StatelessWidget {
  const _PriceTagMarker({
    required this.icon,
    required this.priceLabel,
    required this.backgroundColor,
    required this.isTripSelected,
    required this.isFocused,
  });

  final IconData icon;
  final String priceLabel;
  final Color backgroundColor;
  final bool isTripSelected;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isFocused ? 1.12 : 1.0,
      duration: const Duration(milliseconds: 160),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isTripSelected ? AppTheme.coralPrimary : Colors.white,
              width: isTripSelected ? 2.5 : 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: (isTripSelected ? AppTheme.coralPrimary : backgroundColor)
                    .withValues(alpha: 0.42),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  priceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              if (isTripSelected) ...[
                const SizedBox(width: 3),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: Color(0xFFFFD8CC),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MapOptionComparisonCard extends StatelessWidget {
  const _MapOptionComparisonCard({
    required this.option,
    required this.isHotel,
    required this.currency,
    required this.liveTripTotal,
    required this.onClose,
    required this.onToggleSelect,
    required this.onCheckLiveRate,
    required this.onNavigate,
  });

  final PlaceOptionModel option;
  final bool isHotel;
  final String currency;
  final double liveTripTotal;
  final VoidCallback onClose;
  final VoidCallback onToggleSelect;
  final VoidCallback onCheckLiveRate;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final selectLabel = isHotel
        ? (option.selected ? 'Selected ✓' : 'Select for My Trip')
        : (option.selected ? 'Included ✓' : 'Include');

    return GlassContainer(
      borderRadius: 24,
      opacity: 0.92,
      padding: const EdgeInsets.all(14),
      borderColor: option.selected
          ? AppTheme.coralPrimary.withValues(alpha: 0.78)
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            option.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                        ),
                        if (option.verified) ...[
                          const SizedBox(width: 5),
                          Tooltip(
                            message: 'Verified Place',
                            child: Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: isDark
                                  ? const Color(0xFF5EEAD4)
                                  : AppTheme.mintText,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isHotel
                          ? '${AppFormatters.formatCurrency(option.estimatedPrice, currency)}/night • Total ${AppFormatters.formatCurrency(option.totalEstimatedCost, currency)}'
                          : '${AppFormatters.formatCurrency(option.estimatedPrice, currency)}/meal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.coralPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (option.verified)
                const MintStatusPill(
                  icon: Icons.verified_rounded,
                  label: 'Verified Place',
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.coralPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  option.tierLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.coralPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (option.isWebFound)
                const MintStatusPill(
                  icon: Icons.public_rounded,
                  label: 'Web Rate',
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.warmGold.withValues(alpha: 0.22)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 12,
                        color: isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFFB45309),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'AI Est.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFB45309),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (option.distanceToCenterKm != null)
                Text(
                  '${option.distanceToCenterKm!.toStringAsFixed(1)} km from center',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                'Trip Est. ${AppFormatters.formatCurrency(liveTripTotal, currency)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                decoration: option.selected
                    ? BoxDecoration(
                        gradient: AppTheme.coralGradient,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.coralPrimary.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      )
                    : null,
                child: option.selected
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onToggleSelect,
                        child: Text(
                          selectLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.coralPrimary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onToggleSelect,
                        child: Text(
                          selectLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onCheckLiveRate,
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: AppTheme.coralPrimary,
                ),
                label: const Text(
                  'Check Live Rate',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.onSurface,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onNavigate,
                icon: const Icon(
                  Icons.directions_rounded,
                  size: 14,
                  color: AppTheme.coralPrimary,
                ),
                label: const Text(
                  'Navigate',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
