import 'package:material_ui/material_ui.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/error_dialogs.dart';
import '../../core/utils/formatters.dart';
import '../../models/trip_model.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../itinerary/loading_screen.dart';

/// Trip preference capture form with strict local validation (MFR-04, MFR-05).
class TripCreationScreen extends StatefulWidget {
  const TripCreationScreen({super.key});

  @override
  State<TripCreationScreen> createState() => _TripCreationScreenState();
}

class _TripCreationScreenState extends State<TripCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _budgetController = TextEditingController(text: '500');

  late DateTime _startDate;
  late DateTime _endDate;
  String _currency = 'USD';
  String _travelStyle = 'Moderate';
  final Set<String> _selectedInterests = {'Nature', 'Local Food'};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day + 1);
    _endDate = DateTime(now.year, now.month, now.day + 3);
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _budgetController.dispose();
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
    final request = TripRequestModel(
      destination: _destinationController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      budget: budget,
      currency: _currency,
      interests: _selectedInterests.toList(),
      travelStyle: _travelStyle,
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
      appBar: AppBar(title: const Text('Create Trip')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                'Where are you headed?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
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
              const SizedBox(height: 20),
              Text(
                'Dates & Duration (1–${AppStrings.maxTripDays} days)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: Icon(Icons.date_range_rounded, color: colors.primary),
                  title: Text(AppFormatters.toDateRange(_startDate, _endDate)),
                  subtitle: Text('$_durationDays ${_durationDays == 1 ? "day" : "days"}'),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickDateRange,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [2, 3, 5, 7].map((days) {
                  return ChoiceChip(
                    label: Text('$days Days'),
                    selected: _durationDays == days,
                    onSelected: (_) => _setQuickDuration(days),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'Budget & Currency',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
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
                      hintText: '500',
                      prefixIcon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final raw = value?.trim() ?? '';
                        final parsed = double.tryParse(raw);
                        if (parsed == null || parsed.isNaN || parsed.isInfinite) {
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: AppStrings.supportedCurrencies
                          .map(
                            (code) => DropdownMenuItem(
                              value: code,
                              child: Text(code),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _currency = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Travel Style',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: AppStrings.travelStyles
                    .map(
                      (style) => ButtonSegment<String>(
                        value: style,
                        label: Text(style),
                      ),
                    )
                    .toList(),
                selected: {_travelStyle},
                onSelectionChanged: (selected) {
                  setState(() => _travelStyle = selected.first);
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Interests',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppStrings.defaultInterests.map((interest) {
                  final selected = _selectedInterests.contains(interest);
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
              const SizedBox(height: 28),
              CustomButton(
                label: 'Generate AI Itinerary',
                icon: Icons.auto_awesome_rounded,
                onPressed: _submitForm,
              ),
              const SizedBox(height: 16),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
