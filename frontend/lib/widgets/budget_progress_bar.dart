import 'package:material_ui/material_ui.dart';

import '../core/utils/formatters.dart';

/// Visual budget indicator comparing logged spend vs target trip budget (MFR-11).
class BudgetProgressBar extends StatelessWidget {
  const BudgetProgressBar({
    super.key,
    required this.spent,
    required this.budget,
    required this.currency,
  });

  final double spent;
  final double budget;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = budget > 0 ? (spent / budget) : 0.0;
    final clamped = ratio.clamp(0.0, 1.0);
    final remaining = budget - spent;
    final isOver = remaining < 0;
    final isWarning = !isOver && ratio >= 0.85;

    final barColor = isOver
        ? colors.error
        : (isWarning ? Colors.amber.shade700 : colors.primary);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Budget Tracker',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${(ratio * 100).toStringAsFixed(0)}% used',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: barColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: clamped,
                minHeight: 12,
                color: barColor,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spent',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      AppFormatters.formatCurrency(spent, currency),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isOver ? 'Over Budget' : 'Remaining',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOver ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      AppFormatters.formatCurrency(
                        isOver ? remaining.abs() : remaining,
                        currency,
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isOver ? colors.error : colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
