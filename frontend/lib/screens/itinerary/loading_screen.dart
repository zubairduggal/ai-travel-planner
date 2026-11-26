import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/trip_model.dart';
import '../../providers/trip_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/loading_indicator.dart';
import 'itinerary_screen.dart';

/// Animated AI generation progress screen with cancellation and retry fallback.
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({
    super.key,
    required this.request,
  });

  final TripRequestModel request;

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  static const List<String> _statusMessages = [
    'Analyzing your travel preferences...',
    'Crafting your day-by-day itinerary with AI...',
    'Verifying real-world GPS coordinates...',
    'Checking daily travel route distances...',
  ];

  Timer? _stepTimer;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGeneration());
  }

  void _startTicker() {
    _stepTimer?.cancel();
    _messageIndex = 0;
    _stepTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex = (_messageIndex + 1) % _statusMessages.length;
      });
    });
  }

  Future<void> _runGeneration() async {
    final provider = context.read<TripProvider>();
    final trip = await provider.generateTrip(widget.request);
    if (!mounted) return;

    if (trip != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ItineraryScreen(trip: trip),
        ),
      );
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TripProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && provider.isGenerating) {
          provider.cancelGeneration();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text('Planning ${widget.request.destination}'),
        ),
        body: GlassScaffoldBackground(
          child: SafeArea(
            child: GlassContentConstraint(
              maxWidth: 500,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: provider.errorMessage != null
                    ? _ErrorView(
                        message: provider.errorMessage!,
                        onRetry: () {
                          _startTicker();
                          _runGeneration();
                        },
                        onBack: () => Navigator.of(context).pop(),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Spacer(),
                          GlassContainer(
                            borderRadius: 26,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                LoadingIndicator(
                                  message: _statusMessages[_messageIndex],
                                  subtitle:
                                      '${widget.request.durationDays}-day ${widget.request.travelStyle} trip '
                                      'to ${widget.request.destination}',
                                ),
                                const SizedBox(height: 16),
                                LinearProgressIndicator(
                                  borderRadius: BorderRadius.circular(8),
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          CustomButton(
                            label: 'Cancel',
                            isOutlined: true,
                            icon: Icons.close_rounded,
                            onPressed: () {
                              provider.cancelGeneration();
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.cloud_off_rounded, size: 64, color: colors.error),
        const SizedBox(height: 16),
        Text(
          'Could not generate itinerary',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        CustomButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
        const SizedBox(height: 12),
        CustomButton(
          label: 'Edit Preferences',
          isOutlined: true,
          onPressed: onBack,
        ),
      ],
    );
  }
}
