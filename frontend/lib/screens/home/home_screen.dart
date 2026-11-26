import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/auth_provider.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/glass_container.dart';
import '../itinerary/itinerary_screen.dart';
import '../trip_creation/trip_creation_screen.dart';

/// Curated featured destination item for the Home Explore hero carousel.
class FeaturedDestination {
  const FeaturedDestination({
    required this.name,
    required this.location,
    required this.category,
    required this.rating,
    required this.estimatedBudgetPkr,
    required this.durationDays,
    required this.tagline,
    required this.description,
    required this.highlights,
    required this.gradientColors,
    required this.icon,
  });

  final String name;
  final String location;
  final String category;
  final double rating;
  final double estimatedBudgetPkr;
  final int durationDays;
  final String tagline;
  final String description;
  final List<String> highlights;
  final List<Color> gradientColors;
  final IconData icon;
}

const List<String> _exploreCategories = [
  'Adventure',
  'Road Trips',
  'Food & Drink',
  'Nature',
  'Culture',
];

const List<FeaturedDestination> _featuredDestinations = [
  FeaturedDestination(
    name: 'Hunza Valley',
    location: 'Gilgit-Baltistan, Pakistan',
    category: 'Adventure',
    rating: 4.9,
    estimatedBudgetPkr: 65000,
    durationDays: 5,
    tagline: 'Glacier peaks, Baltit Fort & turquoise Attabad Lake',
    description:
        'Experience dramatic 7,000m Karakoram peaks, ancient cliffside forts, '
        'suspension bridges, and golden-hour viewpoints above Karimabad.',
    highlights: ['Baltit Fort', 'Attabad Lake', 'Passu Cones'],
    gradientColors: [Color(0xFF1E3A5F), Color(0xFF2B6CB0), Color(0xFFF05A3E)],
    icon: Icons.terrain_rounded,
  ),
  FeaturedDestination(
    name: 'Naran & Kaghan Valley',
    location: 'Khyber Pakhtunkhwa, Pakistan',
    category: 'Road Trips',
    rating: 4.8,
    estimatedBudgetPkr: 45000,
    durationDays: 3,
    tagline: 'Alpine highway drives, Lake Saif-ul-Malook & Babusar Top',
    description:
        'Wind along the Kunhar River through cedar forests, high-altitude '
        'glacial lakes, and sweeping mountain passes ideal for scenic road trips.',
    highlights: ['Saif-ul-Malook', 'Lulusar Lake', 'Babusar Pass'],
    gradientColors: [Color(0xFF0F4C5C), Color(0xFF1F7A8C), Color(0xFFF59E0B)],
    icon: Icons.directions_car_filled_rounded,
  ),
  FeaturedDestination(
    name: 'Lahore Food & Heritage',
    location: 'Punjab, Pakistan',
    category: 'Food & Drink',
    rating: 4.9,
    estimatedBudgetPkr: 35000,
    durationDays: 2,
    tagline: 'Mughal architecture & iconic street food nights',
    description:
        'Taste sizzling karahi, lassi, and midnight kebabs beside illuminated '
        'Mughal domes, bustling Walled City bazaars, and royal terraced gardens.',
    highlights: ['Badshahi Mosque', 'Gawalmandi Food Street', 'Shalimar Gardens'],
    gradientColors: [Color(0xFF7C2D12), Color(0xFFC2410C), Color(0xFFF59E0B)],
    icon: Icons.restaurant_rounded,
  ),
  FeaturedDestination(
    name: 'Skardu & Deosai Plains',
    location: 'Gilgit-Baltistan, Pakistan',
    category: 'Nature',
    rating: 4.9,
    estimatedBudgetPkr: 75000,
    durationDays: 5,
    tagline: 'Shangrila Resort, cold deserts & wildflower plateaus',
    description:
        'Discover mirror-still alpine lakes, the surreal Katpana Cold Desert, '
        'and vast high-altitude meadows across Deosai National Park.',
    highlights: ['Upper Kachura Lake', 'Deosai Plains', 'Shigar Fort'],
    gradientColors: [Color(0xFF065F46), Color(0xFF0D9488), Color(0xFF38BDF8)],
    icon: Icons.park_rounded,
  ),
  FeaturedDestination(
    name: 'Islamabad & Taxila',
    location: 'Islamabad Capital Territory',
    category: 'Culture',
    rating: 4.7,
    estimatedBudgetPkr: 30000,
    durationDays: 2,
    tagline: 'Margalla Hills trails, Faisal Mosque & ancient Gandhara',
    description:
        'Blend modern architectural landmarks and hillside cafés with 2,000-'
        'year-old UNESCO archaeological heritage just outside the capital.',
    highlights: ['Faisal Mosque', 'Daman-e-Koh', 'Pakistan Monument'],
    gradientColors: [Color(0xFF312E81), Color(0xFF6366F1), Color(0xFFF05A3E)],
    icon: Icons.account_balance_rounded,
  ),
];

/// Home / Explore hero screen with frosted-glass search, category pills,
/// featured destination card, and recent saved trips.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onSeeAllTripsTap,
    required this.onProfileTap,
    required this.onCreateTripTap,
  });

  final VoidCallback onSeeAllTripsTap;
  final VoidCallback onProfileTap;
  final void Function({
    String? destination,
    double? budget,
    String? interest,
  }) onCreateTripTap;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = _exploreCategories.first;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  FeaturedDestination get _activeFeatured {
    return _featuredDestinations.firstWhere(
      (d) => d.category == _selectedCategory,
      orElse: () => _featuredDestinations.first,
    );
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    widget.onCreateTripTap(
      destination: query.isEmpty ? null : query,
    );
  }

  void _openDestinationDetail(FeaturedDestination dest) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: GlassContentConstraint(
            maxWidth: 520,
            child: GlassContainer(
              borderRadius: 28,
              opacity: 0.90,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MintStatusPill(
                              icon: Icons.auto_awesome_rounded,
                              label: dest.category,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dest.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warmGold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: AppTheme.warmGold,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dest.rating.toStringAsFixed(1),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.warmGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dest.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _DetailInfoTile(
                          icon: Icons.place_rounded,
                          label: 'Location',
                          value: dest.location,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DetailInfoTile(
                          icon: Icons.payments_rounded,
                          label: 'Est. Budget',
                          value:
                              '${AppFormatters.formatCurrency(dest.estimatedBudgetPkr, 'PKR')} • ${dest.durationDays}d',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final spot in dest.highlights)
                        Chip(
                          avatar: const Icon(
                            Icons.location_on_outlined,
                            size: 15,
                            color: AppTheme.coralPrimary,
                          ),
                          label: Text(spot),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  CustomButton(
                    label: 'Start a Trip',
                    icon: Icons.auto_awesome_rounded,
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      widget.onCreateTripTap(
                        destination: '${dest.name}, Pakistan',
                        budget: dest.estimatedBudgetPkr,
                        interest: dest.category == 'Food & Drink'
                            ? 'Local Food'
                            : (dest.category == 'Road Trips'
                                ? 'Nature'
                                : dest.category),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final trips = context.watch<TripProvider>().trips;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final featured = _activeFeatured;
    final greetingName =
        auth.isAuthenticated ? auth.displayName.split(' ').first : 'Traveler';

    return GlassScaffoldBackground(
      child: SafeArea(
        bottom: false,
        child: GlassContentConstraint(
          maxWidth: 620,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 118),
            children: [
              // Top Greeting Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      gradient: AppTheme.coralGradient,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          isDark ? const Color(0xFF1E2433) : Colors.white,
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppTheme.coralPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $greetingName!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          auth.isAuthenticated
                              ? 'Ready for your next adventure'
                              : 'Guest Explorer • Offline Ready',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GlassContainer(
                    borderRadius: 24,
                    padding: EdgeInsets.zero,
                    width: 46,
                    height: 46,
                    onTap: widget.onProfileTap,
                    child: Center(
                      child: Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Bold Hero Headline
              Text(
                'Where do you want to\nexplore today?',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 18),

              // Frosted-Glass Pill Search Bar
              GlassContainer(
                borderRadius: 26,
                padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      color: AppTheme.coralPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _submitSearch(),
                        decoration: InputDecoration(
                          hintText: 'Explore by destination',
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _submitSearch,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          gradient: AppTheme.coralGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Horizontal Category Chips
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _exploreCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final category = _exploreCategories[index];
                    final isSelected = category == _selectedCategory;
                    if (isSelected) {
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedCategory = category),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppTheme.coralGradient,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.coralPrimary
                                    .withValues(alpha: 0.30),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            category,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }
                    return GlassContainer(
                      borderRadius: 24,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      onTap: () => setState(() => _selectedCategory = category),
                      child: Center(
                        child: Text(
                          category,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),

              // Featured Destination Hero Card
              GestureDetector(
                onTap: () => _openDestinationDetail(featured),
                child: Container(
                  height: 256,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: featured.gradientColors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: featured.gradientColors.last
                            .withValues(alpha: isDark ? 0.35 : 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        // Decorative stylized scenic circles & watermark icon
                        Positioned(
                          top: -36,
                          right: -24,
                          child: Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 26,
                          right: 26,
                          child: Icon(
                            featured.icon,
                            size: 82,
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        // Top rating + featured pills
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Featured • ${featured.durationDays} Days',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 15,
                                      color: AppTheme.warmGold,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      featured.rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: AppTheme.charcoalText,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Overlaid Frosted-Glass Info Card
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: GlassContainer(
                            borderRadius: 20,
                            opacity: isDark ? 0.78 : 0.84,
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        featured.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.place_rounded,
                                            size: 14,
                                            color: AppTheme.coralPrimary,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              featured.location,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        featured.tagline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      AppFormatters.formatCurrency(
                                        featured.estimatedBudgetPkr,
                                        'PKR',
                                      ),
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        color: AppTheme.coralPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'est. trip',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Recent Trips Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Trips',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onSeeAllTripsTap,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.coralPrimary,
                    ),
                    child: const Text(
                      'See All',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (trips.isEmpty)
                GlassContainer(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MintStatusPill(
                        icon: Icons.auto_awesome_rounded,
                        label: 'AI Planner Ready',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Plan your first custom itinerary',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pick a destination or tap the coral + button below for verified GPS pins, routes, and offline access.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CustomButton(
                        label: 'Start a Trip',
                        icon: Icons.add_location_alt_outlined,
                        onPressed: () => widget.onCreateTripTap(),
                      ),
                    ],
                  ),
                )
              else
                for (final trip in trips.take(3))
                  GlassContainer(
                    margin: const EdgeInsets.only(bottom: 12),
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    onTap: () {
                      context.read<TripProvider>().selectTrip(trip);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ItineraryScreen(trip: trip),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const MintStatusPill(
                              icon: Icons.offline_pin_outlined,
                              label: 'Offline Ready',
                            ),
                            const Spacer(),
                            Text(
                              (trip.startDate != null && trip.endDate != null)
                                  ? AppFormatters.toDateRange(
                                      trip.startDate!,
                                      trip.endDate!,
                                    )
                                  : '${trip.durationDays} days',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trip.destination,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${trip.durationDays} ${trip.durationDays == 1 ? "day" : "days"} • ${trip.travelStyle}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              AppFormatters.formatCurrency(
                                trip.totalEstimatedCost,
                                trip.currency,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppTheme.coralPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailInfoTile extends StatelessWidget {
  const _DetailInfoTile({
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.coralPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.coralPrimary),
          ),
          const SizedBox(width: 10),
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
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
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

/// Helper to push TripCreationScreen cleanly from Home/Map/SavedTrips.
void openTripCreation(
  BuildContext context, {
  String? destination,
  double? budget,
  String? interest,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TripCreationScreen(
        initialDestination: destination,
        initialBudget: budget,
        initialInterest: interest,
      ),
    ),
  );
}
