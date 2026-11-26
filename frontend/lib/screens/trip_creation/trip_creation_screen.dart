import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_dialogs.dart';
import '../../core/utils/formatters.dart';
import '../../models/trip_model.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/glass_container.dart';
import '../itinerary/loading_screen.dart';

/// Trip preference capture form with Coral-Orange Glassmorphism cards
/// and strict local validation (MFR-04, MFR-05).
class TripCreationScreen extends StatefulWidget {
  const TripCreationScreen({
    super.key,
    this.initialDestination,
    this.initialBudget,
    this.initialInterest,
  });

  final String? initialDestination;
  final double? initialBudget;
  final String? initialInterest;

  @override
  State<TripCreationScreen> createState() => _TripCreationScreenState();
}

class _TravelModeOption {
  const _TravelModeOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

const _travelModeOptions = <_TravelModeOption>[
  _TravelModeOption(
    id: 'air',
    label: 'By Air',
    icon: Icons.flight_takeoff_rounded,
  ),
  _TravelModeOption(
    id: 'road',
    label: 'By Road',
    icon: Icons.directions_car_rounded,
  ),
  _TravelModeOption(
    id: 'train',
    label: 'Train',
    icon: Icons.train_rounded,
  ),
  _TravelModeOption(
    id: 'bus',
    label: 'Bus',
    icon: Icons.directions_bus_rounded,
  ),
  _TravelModeOption(
    id: 'bike',
    label: 'Bike',
    icon: Icons.two_wheeler_rounded,
  ),
];

class _TripCreationScreenState extends State<TripCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _destinationController;
  late final TextEditingController _budgetController;
  late final TextEditingController _departureCityController;

  late DateTime _startDate;
  late DateTime _endDate;
  String _currency = 'PKR';
  String _travelStyle = 'Moderate';
  String _travelMode = 'air';
  late final Set<String> _selectedInterests;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController(
      text: widget.initialDestination ?? '',
    );
    _budgetController = TextEditingController(
      text: (widget.initialBudget ?? 50000).toStringAsFixed(0),
    );
    _departureCityController = TextEditingController();
    _selectedInterests = {'Nature', 'Local Food'};
    if (widget.initialInterest != null &&
        AppStrings.defaultInterests.contains(widget.initialInterest)) {
      _selectedInterests.add(widget.initialInterest!);
    }
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day + 1);
    _endDate = DateTime(now.year, now.month, now.day + 3);
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _budgetController.dispose();
    _departureCityController.dispose();
    super.dispose();
  }

  int get _durationDays {
    final s = DateTime.utc(_startDate.year, _startDate.month, _startDate.day);
    final e = DateTime.utc(_endDate.year, _endDate.month, _endDate.day);
    return e.difference(s).inDays + 1;
  }

  Future<void> _pickDateRange() async {
    final today = DateTime.now();
    final firstAllowed = DateTime(today.year, today.month, today.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstAllowed,
      lastDate: DateTime(today.year + 2, 12, 31),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      helpText: 'Select trip dates (1–${AppStrings.maxTripDays} days)',
    );
    if (picked == null || !mounted) return;

    final startUtc =
        DateTime.utc(picked.start.year, picked.start.month, picked.start.day);
    final endUtc =
        DateTime.utc(picked.end.year, picked.end.month, picked.end.day);
    final days = endUtc.difference(startUtc).inDays + 1;

    if (days > AppStrings.maxTripDays) {
      ErrorDialogs.showSnackBar(
        context,
        'Trip duration cannot exceed ${AppStrings.maxTripDays} days.',
        isError: true,
      );
      return;
    }

    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
  }

  void _setQuickDuration(int days) {
    setState(() {
      _endDate = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day + days - 1,
      );
    });
  }

  void _submitForm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_durationDays < 1 || _durationDays > AppStrings.maxTripDays) {
      ErrorDialogs.showSnackBar(
        context,
        'Trip duration must be between 1 and ${AppStrings.maxTripDays} days.',
        isError: true,
      );
      return;
    }

    if (_selectedInterests.isEmpty) {
      ErrorDialogs.showSnackBar(
        context,
        'Please select at least one travel interest.',
        isError: true,
      );
      return;
    }

    final budget = double.parse(_budgetController.text.trim());
    final departureCity = _departureCityController.text.trim();
    final request = TripRequestModel(
      destination: _destinationController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      budget: budget,
      currency: _currency,
      interests: _selectedInterests.toList(),
      travelStyle: _travelStyle,
      travelMode: _travelMode,
      departureCity: departureCity.isEmpty ? null : departureCity,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoadingScreen(request: request),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Create Trip')),
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: GlassContentConstraint(
            maxWidth: 600,
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    GlassContainer(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Where are you headed?',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          CustomTextField(
                            controller: _destinationController,
                            label: 'Destination',
                            hintText: 'e.g. Hunza Valley, Pakistan',
                            prefixIcon: Icons.place_outlined,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) {
                                return 'Please enter a destination.';
                              }
                              if (text.length > 200) {
                                return 'Destination must be under 200 characters.';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassContainer(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Dates & Duration (1–${AppStrings.maxTripDays} days)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _pickDateRange,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.date_range_rounded,
                                    color: AppTheme.coralPrimary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppFormatters.toDateRange(
                                            _startDate,
                                            _endDate,
                                          ),
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '$_durationDays ${_durationDays == 1 ? "day" : "days"}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.edit_calendar_outlined),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [2, 3, 5, 7].map((days) {
                              return ChoiceChip(
                                label: Text('$days Days'),
                                selected: _durationDays == days,
                                onSelected: (_) => _setQuickDuration(days),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassContainer(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Budget & Currency',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: CustomTextField(
                                  controller: _budgetController,
                                  label: 'Total Budget',
                                  hintText: '50000',
                                  prefixIcon: Icons.payments_outlined,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  validator: (value) {
                                    final raw = value?.trim() ?? '';
                                    final parsed = double.tryParse(raw);
                                    if (parsed == null ||
                                        parsed.isNaN ||
                                        parsed.isInfinite) {
                                      return 'Enter a valid number.';
                                    }
                                    if (parsed <= 0) {
                                      return 'Budget must be greater than 0.';
                                    }
                                    if (parsed > AppStrings.maxBudget) {
                                      return 'Budget cannot exceed 1,000,000.';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _currency,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Currency',
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 15,
                                    ),
                                  ),
                                  items: AppStrings.supportedCurrencies
                                      .map(
                                        (code) => DropdownMenuItem(
                                          value: code,
                                          child: Text(
                                            code,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _currency = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassContainer(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'How do you want to travel?',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _travelModeOptions.map((option) {
                              final isSelected = _travelMode == option.id;
                              return _TravelModePill(
                                option: option,
                                selected: isSelected,
                                onTap: () {
                                  setState(() => _travelMode = option.id);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          CustomTextField(
                            controller: _departureCityController,
                            label: 'Departing From (optional)',
                            hintText: 'e.g. Islamabad, Karachi',
                            prefixIcon: Icons.trip_origin_rounded,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.length > 80) {
                                return 'Departure city must be under 80 characters.';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GlassContainer(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Travel Style',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (var i = 0;
                                  i < AppStrings.travelStyles.length;
                                  i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: _TravelStylePill(
                                    label: AppStrings.travelStyles[i],
                                    selected: _travelStyle ==
                                        AppStrings.travelStyles[i],
                                    onTap: () => setState(
                                      () => _travelStyle =
                                          AppStrings.travelStyles[i],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Interests',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: AppStrings.defaultInterests.map((interest) {
                              final selected =
                                  _selectedInterests.contains(interest);
                              return FilterChip(
                                label: Text(interest),
                                selected: selected,
                                onSelected: (isOn) {
                                  setState(() {
                                    if (isOn) {
                                      _selectedInterests.add(interest);
                                    } else {
                                      _selectedInterests.remove(interest);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: CustomButton(
                      label: 'Generate AI Itinerary',
                      icon: Icons.auto_awesome_rounded,
                      onPressed: _submitForm,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TravelModePill extends StatelessWidget {
  const _TravelModePill({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _TravelModeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);

    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: selected ? AppTheme.coralGradient : null,
              color: selected
                  ? null
                  : (isDark
                      ? const Color(0xFF1E2433).withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.78)),
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? AppTheme.coralPrimary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : const Color(0xFFE2E8F0)),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.coralPrimary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  option.icon,
                  size: 16,
                  color: selected ? Colors.white : AppTheme.coralPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  option.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TravelStylePill extends StatelessWidget {
  const _TravelStylePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: BoxDecoration(
              gradient: selected ? AppTheme.coralGradient : null,
              color: selected
                  ? null
                  : (isDark
                      ? const Color(0xFF1E2433).withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.78)),
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? AppTheme.coralPrimary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : const Color(0xFFE2E8F0)),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.coralPrimary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
