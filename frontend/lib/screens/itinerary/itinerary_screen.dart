import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/activity_model.dart';
import '../../models/day_plan_model.dart';
import '../../models/expense_model.dart';
import '../../models/place_option_model.dart';
import '../../models/transport_summary_model.dart';
import '../../models/trip_model.dart';
import '../../providers/expense_provider.dart';
import '../../providers/trip_provider.dart';
import '../../services/export_service.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/comparison_option_card.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/packing_checklist.dart';
import '../../widgets/weather_card.dart';
import '../expense/expense_screen.dart';
import '../map/map_screen.dart';
import 'slot_editor_sheet.dart';

/// Day-by-day Coral-Orange Glassmorphism itinerary viewer with prominent
/// "View Map" coral pill CTA, Expenses, Weather & Packing, and Export.
class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({
    super.key,
    required this.trip,
  });

  final TripModel trip;

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeSection = 0; // 0 = Itinerary, 1 = Hotels, 2 = Food

  @override
  void initState() {
    super.initState();
    final length = widget.trip.days.isEmpty ? 1 : widget.trip.days.length;
    _tabController = TabController(length: length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<TripProvider>();
      provider.loadPackingList(widget.trip.tripId);
      provider.loadWeatherForTrip(widget.trip);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openMap(
    TripModel currentTrip, {
    String? optionId,
    String? category,
  }) {
    final dayIdx = _tabController.index.clamp(0, currentTrip.days.length - 1);
    final dayNumber = currentTrip.days[dayIdx].dayNumber;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MapScreen(
          trip: currentTrip,
          initialDayNumber: dayNumber,
          initialOptionId: optionId,
          initialCategory: category,
        ),
      ),
    );
  }

  void _openExpenses(TripModel currentTrip) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseScreen(trip: currentTrip),
      ),
    );
  }

  void _openUtilitiesSheet(TripModel currentTrip) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (sheetContext, scrollController) {
          final provider = sheetContext.watch<TripProvider>();
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              WeatherCard(
                forecast: provider.weatherForTrip(currentTrip.tripId),
                isLoading: provider.isWeatherLoading(currentTrip.tripId),
                onRefresh: () => provider.loadWeatherForTrip(currentTrip),
              ),
              const SizedBox(height: 12),
              PackingChecklist(
                items: provider.packingListForTrip(currentTrip.tripId),
                onToggle: (id) =>
                    provider.togglePackingItem(currentTrip.tripId, id),
                onAdd: (title) =>
                    provider.addPackingItem(currentTrip.tripId, title),
                onRemove: (id) =>
                    provider.removePackingItem(currentTrip.tripId, id),
              ),
            ],
          );
        },
      ),
    );
  }

  Rect _shareOrigin(BuildContext ctx) {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return const Rect.fromLTWH(0, 0, 100, 100);
  }

  void _openExportSheet(TripModel currentTrip) {
    final origin = _shareOrigin(context);
    ExportService exportService;
    try {
      exportService = context.read<ExportService>();
    } catch (_) {
      exportService = const ExportService();
    }
    final tripProvider = context.read<TripProvider>();
    final expenses = () {
      try {
        return context.read<ExpenseProvider>().expensesForTrip(
              currentTrip.tripId,
            );
      } catch (_) {
        return const <ExpenseModel>[];
      }
    }();
    final packingList = tripProvider.packingListForTrip(currentTrip.tripId);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: GlassContentConstraint(
          maxWidth: 520,
          child: GlassContainer(
            borderRadius: 28,
            opacity: 0.92,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Text(
                  'Export & Share Itinerary',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: AppTheme.coralPrimary,
                  ),
                  title: const Text('Share Offline PDF'),
                  subtitle: const Text('Multi-page PDF with schedule & notes'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    try {
                      await exportService.sharePdfItinerary(
                        currentTrip,
                        sharePositionOrigin: origin,
                        expenses: expenses,
                        packingList: packingList,
                      );
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not export PDF on this device.'),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.print_outlined,
                    color: AppTheme.coralPrimary,
                  ),
                  title: const Text('Print / Save PDF'),
                  subtitle: const Text('Open native print preview'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    try {
                      await exportService.printPdfItinerary(
                        currentTrip,
                        expenses: expenses,
                        packingList: packingList,
                      );
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Print preview is unavailable here.'),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.share_outlined,
                    color: AppTheme.coralPrimary,
                  ),
                  title: const Text('Share Text Summary (WhatsApp)'),
                  subtitle: const Text('Formatted day-by-day text itinerary'),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    try {
                      await exportService.shareTextSummary(
                        currentTrip,
                        sharePositionOrigin: origin,
                        expenses: expenses,
                        packingList: packingList,
                      );
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open the share sheet.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSlotEditor(
    TripModel currentTrip,
    int dayNumber,
    ActivityModel activity,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SlotEditorSheet(
        trip: currentTrip,
        dayNumber: dayNumber,
        activity: activity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final currentTrip = provider.activeTrip?.tripId == widget.trip.tripId
        ? provider.activeTrip!
        : widget.trip;
    final days = currentTrip.days;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (days.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(currentTrip.destination)),
        body: const GlassScaffoldBackground(
          child: Center(child: Text('No daily activities found.')),
        ),
      );
    }

    return Scaffold(
      body: GlassScaffoldBackground(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              pinned: true,
              floating: true,
              backgroundColor: colors.surface.withValues(alpha: 0.82),
              title: Text(currentTrip.destination),
              actions: [
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  tooltip: 'Open Map View',
                  onPressed: () => _openMap(currentTrip),
                ),
                IconButton(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  tooltip: 'Expense Tracker',
                  onPressed: () => _openExpenses(currentTrip),
                ),
                IconButton(
                  icon: const Icon(Icons.backpack_outlined),
                  tooltip: 'Weather & Packing',
                  onPressed: () => _openUtilitiesSheet(currentTrip),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Export & Share',
                  onPressed: () => _openExportSheet(currentTrip),
                ),
              ],
              bottom: _activeSection == 0
                  ? TabBar(
                      controller: _tabController,
                      indicatorColor: AppTheme.coralPrimary,
                      labelColor: AppTheme.coralPrimary,
                      isScrollable: days.length > 3,
                      tabAlignment: days.length > 3
                          ? TabAlignment.start
                          : TabAlignment.fill,
                      tabs: [
                        for (final day in days) Tab(text: 'Day ${day.dayNumber}'),
                      ],
                    )
                  : null,
            ),
          ],
          body: GlassContentConstraint(
            maxWidth: 640,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: _TripSummaryHeader(
                    trip: currentTrip,
                    cacheStatus: provider.lastCacheStatus,
                    onViewMapTap: () => _openMap(currentTrip),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  child: _SectionSwitcher(
                    activeIndex: _activeSection,
                    hotelCount: currentTrip.hotelOptions.length,
                    foodCount: currentTrip.diningOptions.length,
                    onChanged: (idx) => setState(() => _activeSection = idx),
                  ),
                ),
                Expanded(
                  child: _buildActiveSectionBody(
                    currentTrip: currentTrip,
                    days: days,
                    colors: colors,
                    theme: theme,
                    provider: provider,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSectionBody({
    required TripModel currentTrip,
    required List<DayPlanModel> days,
    required ColorScheme colors,
    required ThemeData theme,
    required TripProvider provider,
  }) {
    if (_activeSection == 1) {
      return _ComparisonOptionsView(
        options: currentTrip.hotelOptions,
        currency: currentTrip.currency,
        destination: currentTrip.destination,
        isHotel: true,
        onToggleSelect: (optionId) =>
            provider.selectHotelOption(currentTrip.tripId, optionId),
        onShowOnMap: (optionId) => _openMap(
          currentTrip,
          optionId: optionId,
          category: 'hotels',
        ),
      );
    }
    if (_activeSection == 2) {
      return _ComparisonOptionsView(
        options: currentTrip.diningOptions,
        currency: currentTrip.currency,
        destination: currentTrip.destination,
        isHotel: false,
        onToggleSelect: (optionId) =>
            provider.toggleDiningOption(currentTrip.tripId, optionId),
        onShowOnMap: (optionId) => _openMap(
          currentTrip,
          optionId: optionId,
          category: 'food',
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        for (final day in days)
          _DayPlanView(
            day: day,
            currency: currentTrip.currency,
            colors: colors,
            theme: theme,
            transportSummary:
                day.dayNumber == days.first.dayNumber
                    ? currentTrip.transportSummary
                    : null,
            departureCity: currentTrip.departureCity,
            onCustomizeActivity: (act) =>
                _openSlotEditor(currentTrip, day.dayNumber, act),
          ),
      ],
    );
  }
}

class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({
    required this.activeIndex,
    required this.hotelCount,
    required this.foodCount,
    required this.onChanged,
  });

  final int activeIndex;
  final int hotelCount;
  final int foodCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (0, 'Itinerary'),
      (1, 'Hotels ($hotelCount)'),
      (2, 'Food ($foodCount)'),
    ];

    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: tabs.map((item) {
          final index = item.$1;
          final label = item.$2;
          final selected = activeIndex == index;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: selected ? AppTheme.coralGradient : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: selected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ComparisonOptionsView extends StatelessWidget {
  const _ComparisonOptionsView({
    required this.options,
    required this.currency,
    required this.destination,
    required this.isHotel,
    required this.onToggleSelect,
    required this.onShowOnMap,
  });

  final List<PlaceOptionModel> options;
  final String currency;
  final String destination;
  final bool isHotel;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (options.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          GlassContainer(
            borderRadius: 22,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  isHotel
                      ? Icons.hotel_outlined
                      : Icons.restaurant_outlined,
                  size: 36,
                  color: AppTheme.coralPrimary,
                ),
                const SizedBox(height: 10),
                Text(
                  isHotel
                      ? 'No hotel comparisons saved'
                      : 'No dining comparisons saved',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Trips created earlier do not include verified comparison cards. '
                  'Generate a fresh trip to compare real places and live budget options.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            isHotel
                ? 'Choose your stay — your live trip budget recalculates instantly.'
                : 'Toggle restaurants to include or exclude from your live trip budget.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final option in options)
          ComparisonOptionCard(
            option: option,
            currency: currency,
            destination: destination,
            isHotel: isHotel,
            onToggleSelect: () => onToggleSelect(option.optionId),
            onShowOnMap: () => onShowOnMap(option.optionId),
          ),
      ],
    );
  }
}

class _TransportSummaryBanner extends StatelessWidget {
  const _TransportSummaryBanner({
    required this.summary,
    required this.currency,
    this.departureCity,
  });

  final TransportSummaryModel summary;
  final String currency;
  final String? departureCity;

  IconData _modeIcon(String mode) {
    switch (mode.toLowerCase()) {
      case 'road':
        return Icons.directions_car_rounded;
      case 'train':
        return Icons.train_rounded;
      case 'bus':
        return Icons.directions_bus_rounded;
      case 'bike':
        return Icons.two_wheeler_rounded;
      case 'air':
      default:
        return Icons.flight_takeoff_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fromText = (departureCity != null && departureCity!.trim().isNotEmpty)
        ? ' from ${departureCity!.trim()}'
        : '';
    final detail = summary.routeTip.trim().isNotEmpty
        ? summary.routeTip.trim()
        : summary.notes.trim();

    return GlassContainer(
      borderRadius: 18,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.coralPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _modeIcon(summary.mode),
              size: 18,
              color: AppTheme.coralPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${summary.modeLabel}$fromText',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      AppFormatters.formatCurrency(
                        summary.estimatedCost,
                        currency,
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppTheme.coralPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSummaryHeader extends StatelessWidget {
  const _TripSummaryHeader({
    required this.trip,
    required this.onViewMapTap,
    this.cacheStatus,
  });

  final TripModel trip;
  final VoidCallback onViewMapTap;
  final String? cacheStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final dateText = (trip.startDate != null && trip.endDate != null)
        ? AppFormatters.toDateRange(trip.startDate!, trip.endDate!)
        : '${trip.durationDays} days';

    final liveTotal = trip.effectiveTotalCost;
    final budgetCap = trip.targetBudget;
    final hasBudgetCap = budgetCap != null && budgetCap > 0;
    final remaining = hasBudgetCap ? budgetCap - liveTotal : 0.0;
    final isOverBudget = hasBudgetCap && remaining < 0;
    final progress = hasBudgetCap ? (liveTotal / budgetCap).clamp(0.0, 1.0) : 0.0;
    final meterColor = isOverBudget
        ? colors.error
        : (progress > 0.85
            ? AppTheme.warmGold
            : (isDark ? const Color(0xFF5EEAD4) : AppTheme.mintText));

    return GlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _HeaderMetric(
                      icon: Icons.calendar_today_outlined,
                      label: dateText,
                    ),
                    _HeaderMetric(
                      icon: Icons.style_outlined,
                      label: trip.travelStyle,
                    ),
                    if (!hasBudgetCap)
                      _HeaderMetric(
                        icon: Icons.account_balance_wallet_outlined,
                        label:
                            'Est. ${AppFormatters.formatCurrency(liveTotal, trip.currency)}',
                      ),
                    if (cacheStatus?.toUpperCase() == 'HIT')
                      const MintStatusPill(
                        icon: Icons.bolt_rounded,
                        label: 'Instant Cache',
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.coralGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.coralPrimary.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: onViewMapTap,
                  icon: const Icon(Icons.map_rounded, size: 17),
                  label: const Text(
                    'View Map',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (hasBudgetCap) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _HeaderMetric(
                    icon: Icons.account_balance_wallet_outlined,
                    label:
                        'Est. ${AppFormatters.formatCurrency(liveTotal, trip.currency)}'
                        ' / ${AppFormatters.formatCurrency(budgetCap, trip.currency)}',
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isOverBudget
                      ? 'Over by ${AppFormatters.formatCurrency(remaining.abs(), trip.currency)}'
                      : '${AppFormatters.formatCurrency(remaining, trip.currency)} left',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: meterColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(meterColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppTheme.coralPrimary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _DayPlanView extends StatelessWidget {
  const _DayPlanView({
    required this.day,
    required this.currency,
    required this.colors,
    required this.theme,
    required this.onCustomizeActivity,
    this.transportSummary,
    this.departureCity,
  });

  final DayPlanModel day;
  final String currency;
  final ColorScheme colors;
  final ThemeData theme;
  final ValueChanged<ActivityModel> onCustomizeActivity;
  final TransportSummaryModel? transportSummary;
  final String? departureCity;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (transportSummary != null)
          _TransportSummaryBanner(
            summary: transportSummary!,
            currency: currency,
            departureCity: departureCity,
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                day.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (day.totalDistanceKm != null)
              Chip(
                avatar: const Icon(
                  Icons.route_outlined,
                  size: 16,
                  color: AppTheme.coralPrimary,
                ),
                label: Text(AppFormatters.formatDistance(day.totalDistanceKm)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (!day.feasible && day.distanceWarnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colors.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Long travel distance detected',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final warning in day.distanceWarnings)
                        Text(
                          warning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (day.activities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'All activities removed for Day ${day.dayNumber}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < day.activities.length; i++)
            ActivityCard(
              activity: day.activities[i],
              currency: currency,
              indexNumber: i + 1,
              onTap: () => onCustomizeActivity(day.activities[i]),
              onCustomizeTap: () => onCustomizeActivity(day.activities[i]),
            ),
      ],
    );
  }
}
