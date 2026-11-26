import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';
import 'home_screen.dart';
import 'saved_trips_screen.dart';

/// Root Coral-Orange Glassmorphism shell with floating frosted-glass bottom
/// navigation (Home, My Trips, Center Coral '+' FAB, dedicated Map tab, Profile).
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.initialIndex = 0,
    this.showMapTiles = true,
  });

  /// 0 = Home, 1 = My Trips, 2 = Map, 3 = Profile.
  final int initialIndex;

  /// Disabled in offline widget tests to avoid live OSM tile HTTP requests.
  final bool showMapTiles;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, 3);
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
  }

  void _launchCreateTrip({
    String? destination,
    double? budget,
    String? interest,
  }) {
    openTripCreation(
      context,
      destination: destination,
      budget: budget,
      interest: interest,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        onSeeAllTripsTap: () => _selectTab(1),
        onProfileTap: () => _selectTab(3),
        onCreateTripTap: _launchCreateTrip,
      ),
      SavedTripsScreen(
        onCreateTripTap: () => _launchCreateTrip(),
      ),
      _selectedIndex == 2
          ? MapScreen(
              isTab: true,
              showTileLayer: widget.showMapTiles,
              onStartTrip: ({String? destination, double? budget}) =>
                  _launchCreateTrip(destination: destination, budget: budget),
            )
          : const SizedBox.shrink(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: screens,
          ),
          // Floating Frosted-Glass Bottom Navigation Bar with Center Coral '+' FAB
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SizedBox(
                    height: 76,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        GlassContainer(
                          borderRadius: 28,
                          opacity: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? 0.84
                              : 0.84,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _NavBarItem(
                                icon: Icons.explore_outlined,
                                selectedIcon: Icons.explore_rounded,
                                label: 'Home',
                                selected: _selectedIndex == 0,
                                onTap: () => _selectTab(0),
                              ),
                              _NavBarItem(
                                icon: Icons.luggage_outlined,
                                selectedIcon: Icons.luggage_rounded,
                                label: 'My Trips',
                                selected: _selectedIndex == 1,
                                onTap: () => _selectTab(1),
                              ),
                              const SizedBox(width: 60),
                              _NavBarItem(
                                icon: Icons.map_outlined,
                                selectedIcon: Icons.map_rounded,
                                label: 'Map',
                                selected: _selectedIndex == 2,
                                onTap: () => _selectTab(2),
                              ),
                              _NavBarItem(
                                icon: Icons.person_outline_rounded,
                                selectedIcon: Icons.person_rounded,
                                label: 'Profile',
                                selected: _selectedIndex == 3,
                                onTap: () => _selectTab(3),
                              ),
                            ],
                          ),
                        ),
                        // Prominent Center Circular Coral '+' FAB
                        Positioned(
                          top: -4,
                          child: Tooltip(
                            message: 'Create Trip',
                            child: Semantics(
                              button: true,
                              label: 'Create Trip',
                              child: GestureDetector(
                                onTap: () => _launchCreateTrip(),
                                child: Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.coralGradient,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.coralPrimary
                                            .withValues(alpha: 0.42),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeColor = AppTheme.coralPrimary;
    final inactiveColor = colors.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 22,
                color: selected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? activeColor : inactiveColor,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
