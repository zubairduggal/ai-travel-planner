import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/utils/formatters.dart';
import '../../models/trip_model.dart';
import '../../providers/expense_provider.dart';
import '../../widgets/budget_progress_bar.dart';
import 'add_expense_sheet.dart';

/// Multi-currency expense tracker dashboard for a trip (MFR-11, FM4).
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({
    super.key,
    required this.trip,
  });

  final TripModel trip;

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ExpenseProvider>().loadExpensesForTrip(widget.trip.tripId);
    });
  }

  void _openAddExpense() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddExpenseSheet(trip: widget.trip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final expenses = provider.expensesForTrip(widget.trip.tripId);
    final totalSpent = provider.totalSpentForTrip(widget.trip);
    final categoryTotals = provider.categoryTotalsForTrip(widget.trip);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.trip.destination} Expenses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpense,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        children: [
          BudgetProgressBar(
            spent: totalSpent,
            budget: widget.trip.effectiveBudget,
            currency: widget.trip.currency,
          ),
          const SizedBox(height: 8),
          Text(
            provider.currencyService.usingLiveRates
                ? 'Exchange rates: Live (Frankfurter ECB)'
                : 'Exchange rates: Offline cached / fallback rates',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (categoryTotals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'By Category',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categoryTotals.entries.map((entry) {
                return Chip(
                  label: Text(
                    '${entry.key}: ${AppFormatters.formatCurrency(entry.value, widget.trip.currency)}',
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Logged Expenses (${expenses.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (expenses.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 44,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No expenses logged yet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "Add Expense" to log spending in any currency.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final expense in expenses)
              Card(
                child: ListTile(
                  title: Text(
                    expense.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${expense.category} • ${AppFormatters.toReadableDate(expense.date)}'
                    '${expense.currency != widget.trip.currency ? " • Original: ${AppFormatters.formatCurrency(expense.amount, expense.currency)}" : ""}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppFormatters.formatCurrency(
                          provider.convertToTripCurrency(
                            expense,
                            widget.trip.currency,
                          ),
                          widget.trip.currency,
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colors.error,
                          size: 20,
                        ),
                        tooltip: 'Delete expense',
                        onPressed: () => provider.deleteExpense(
                          widget.trip.tripId,
                          expense.expenseId,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
