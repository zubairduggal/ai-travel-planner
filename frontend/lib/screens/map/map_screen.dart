import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/utils/error_dialogs.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/map_launcher.dart';
import '../../models/activity_model.dart';
import '../../models/day_plan_model.dart';
import '../../models/trip_model.dart';

/// Interactive OpenStreetMap view showing numbered activity markers,
/// sequential daily route polylines, and native Google/Apple Maps handoff (MFR-08, MFR-09).
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.trip,
    this.initialDayNumber = 1,
    this.showTileLayer = true,
  });

  final TripModel trip;
  final int initialDayNumber;

  /// Can be disabled in offline widget tests to avoid live OSM tile requests.
  final bool showTileLayer;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late int _selectedDayNumber;
  ActivityModel? _selectedActivity;

  @override
  void initState() {
    super.initState();
    final hasInitial = widget.trip.days.any(
      (d) => d.dayNumber == widget.initialDayNumber,
    );
    _selectedDayNumber = hasInitial
        ? widget.initialDayNumber
        : (widget.trip.days.isNotEmpty ? widget.trip.days.first.dayNumber : 1);
  }

  DayPlanModel? get _currentDay {
    for (final day in widget.trip.days) {
      if (day.dayNumber == _selectedDayNumber) return day;
    }
    return widget.trip.days.isNotEmpty ? widget.trip.days.first : null;
  }

  List<ActivityModel> get _locatedActivities {
    final day = _currentDay;
    if (day == null) return const [];
    return day.activities.where((a) => a.hasCoordinates).toList();
  }

  LatLng _computeCenter(List<ActivityModel> located) {
    if (located.isEmpty) {
      return const LatLng(33.6844, 73.0479); // Fallback default
    }
    final avgLat =
        located.fold<double>(0, (s, a) => s + a.latitude!) / located.length;
    final avgLon =
        located.fold<double>(0, (s, a) => s + a.longitude!) / located.length;
    return LatLng(avgLat, avgLon);
  }

  void _selectDay(int dayNumber) {
    setState(() {
      _selectedDayNumber = dayNumber;
      _selectedActivity = null;
    });
    final located = _locatedActivities;
    if (located.isNotEmpty) {
      _mapController.move(_computeCenter(located), 12.5);
    }
  }

  Color _markerColor(String slot, ColorScheme colors) {
    final lower = slot.toLowerCase();
    if (lower.contains('morning')) return colors.primary;
    if (lower.contains('afternoon')) return colors.tertiary;
    return colors.secondary;
  }

  Future<void> _navigateToActivity(ActivityModel activity) async {
    if (!activity.hasCoordinates) return;
    final launched = await MapLauncher.openExternalMaps(
      latitude: activity.latitude!,
      longitude: activity.longitude!,
      label: activity.title,
    );
    if (!launched && mounted) {
      ErrorDialogs.showSnackBar(
        context,
        'Could not open an external Maps app on this device.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final located = _locatedActivities;
    final points = located
        .map((a) => LatLng(a.latitude!, a.longitude!))
        .toList();
    final center = _computeCenter(located);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.trip.destination} Map'),
      ),
      body: Column(
        children: [
          if (widget.trip.days.length > 1)
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: widget.trip.days.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = widget.trip.days[index];
                  return ChoiceChip(
                    label: Text('Day ${day.dayNumber}'),
                    selected: day.dayNumber == _selectedDayNumber,
                    onSelected: (_) => _selectDay(day.dayNumber),
                  );
                },
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (located.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 56,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No verified GPS pins for Day $_selectedDayNumber',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
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
                  )
                else
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: located.length == 1 ? 14.0 : 12.5,
                      onTap: (_, _) =>
                          setState(() => _selectedActivity = null),
                    ),
                    children: [
                      if (widget.showTileLayer)
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          // Mandatory OSM tile policy: unique real package ID.
                          userAgentPackageName: 'com.numl.aitravelplanner',
                        ),
                      if (points.length >= 2)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: points,
                              strokeWidth: 4.0,
                              color: colors.primary,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          for (var i = 0; i < located.length; i++)
                            Marker(
                              point: points[i],
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                onTap: () => setState(
                                  () => _selectedActivity = located[i],
                                ),
                                child: _NumberedMarker(
                                  number: i + 1,
                                  color: _markerColor(
                                    located[i].timeSlot,
                                    colors,
                                  ),
                                  selected: _selectedActivity?.activityId ==
                                      located[i].activityId,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            '© OpenStreetMap contributors',
                          ),
                        ],
                      ),
                    ],
                  ),
                if (_selectedActivity != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedActivity!.timeSlot,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedActivity!.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_selectedActivity!.category} • '
                                    '${AppFormatters.formatCurrency(_selectedActivity!.estimatedCost, widget.trip.currency)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: () =>
                                  _navigateToActivity(_selectedActivity!),
                              icon: const Icon(Icons.directions_rounded, size: 18),
                              label: const Text('Navigate'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
      scale: selected ? 1.2 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
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
