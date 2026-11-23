import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/formatters.dart';
import '../../models/expense_model.dart';
import '../../models/trip_model.dart';
import '../../providers/expense_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

/// Modal sheet to log a multi-currency expense against a trip (MFR-11).
class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({
    super.key,
    required this.trip,
  });

  final TripModel trip;

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  late String _currency;
  String _category = AppStrings.expenseCategories.first;

  @override
  void initState() {
    super.initState();
    _currency = AppStrings.supportedCurrencies.contains(widget.trip.currency)
        ? widget.trip.currency
        : 'USD';
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amountController.text.trim());
    final expense = ExpenseModel(
      expenseId: 'exp_${DateTime.now().microsecondsSinceEpoch}',
      tripId: widget.trip.tripId,
      title: _titleController.text.trim(),
      amount: amount,
      currency: _currency,
      category: _category,
      date: DateTime.now(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    await context.read<ExpenseProvider>().addExpense(expense);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = context.read<ExpenseProvider>();
    final parsedAmount = double.tryParse(_amountController.text.trim());
    final convertedPreview =
        (parsedAmount != null && parsedAmount > 0 && _currency != widget.trip.currency)
            ? expenseProvider.currencyService.convert(
                amount: parsedAmount,
                fromCurrency: _currency,
                toCurrency: widget.trip.currency,
              )
            : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Log Expense',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _titleController,
                label: 'Description',
                hintText: 'e.g. Local lunch at Karimabad',
                prefixIcon: Icons.receipt_long_outlined,
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Enter a description.' : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: CustomTextField(
                      controller: _amountController,
                      label: 'Amount',
                      hintText: '25.00',
                      prefixIcon: Icons.payments_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) {
                          return 'Enter an amount > 0.';
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
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _currency = value);
                      },
                    ),
                  ),
                ],
              ),
              if (convertedPreview != null) ...[
                const SizedBox(height: 8),
                Text(
                  '≈ ${AppFormatters.formatCurrency(convertedPreview, widget.trip.currency)} '
                  'in trip currency (${widget.trip.currency})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: AppStrings.expenseCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _notesController,
                label: 'Notes (Optional)',
                prefixIcon: Icons.notes_rounded,
              ),
              const SizedBox(height: 20),
              CustomButton(
                label: 'Save Expense',
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
