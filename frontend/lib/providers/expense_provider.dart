import 'package:flutter/foundation.dart';

import '../models/expense_model.dart';
import '../models/trip_model.dart';
import '../services/currency_service.dart';
import '../services/storage_service.dart';

/// Manages multi-currency trip expense logging and budget tracking (MFR-11, FM4).
class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider({
    StorageService? storage,
    CurrencyService? currencyService,
  })  : _storage = storage ?? InMemoryStorageService(),
        _currencyService = currencyService ?? CurrencyService(storage: storage);

  final StorageService _storage;
  final CurrencyService _currencyService;

  final Map<String, List<ExpenseModel>> _expensesByTrip = {};
  bool _ratesLoaded = false;

  CurrencyService get currencyService => _currencyService;

  List<ExpenseModel> expensesForTrip(String tripId) =>
      List.unmodifiable(_expensesByTrip[tripId] ?? const []);

  Future<void> loadExpensesForTrip(String tripId) async {
    if (!_ratesLoaded) {
      await _currencyService.refreshRates();
      _ratesLoaded = true;
    }
    final loaded = await _storage.loadExpenses(tripId);
    _expensesByTrip[tripId] = loaded;
    notifyListeners();
  }

  Future<void> addExpense(ExpenseModel expense) async {
    await _storage.saveExpense(expense);
    final list = List<ExpenseModel>.from(_expensesByTrip[expense.tripId] ?? []);
    list.insert(0, expense);
    _expensesByTrip[expense.tripId] = list;
    notifyListeners();
  }

  Future<void> deleteExpense(String tripId, String expenseId) async {
    await _storage.deleteExpense(expenseId);
    final list = List<ExpenseModel>.from(_expensesByTrip[tripId] ?? []);
    list.removeWhere((e) => e.expenseId == expenseId);
    _expensesByTrip[tripId] = list;
    notifyListeners();
  }

  double convertToTripCurrency(ExpenseModel expense, String tripCurrency) {
    return _currencyService.convert(
      amount: expense.amount,
      fromCurrency: expense.currency,
      toCurrency: tripCurrency,
    );
  }

  double totalSpentForTrip(TripModel trip) {
    final list = _expensesByTrip[trip.tripId] ?? const [];
    final sum = list.fold<double>(
      0.0,
      (acc, e) => acc + convertToTripCurrency(e, trip.currency),
    );
    return double.parse(sum.toStringAsFixed(2));
  }

  double remainingBudgetForTrip(TripModel trip) {
    final diff = trip.effectiveBudget - totalSpentForTrip(trip);
    return double.parse(diff.toStringAsFixed(2));
  }

  Map<String, double> categoryTotalsForTrip(TripModel trip) {
    final totals = <String, double>{};
    for (final e in _expensesByTrip[trip.tripId] ?? const <ExpenseModel>[]) {
      final converted = convertToTripCurrency(e, trip.currency);
      totals[e.category] = double.parse(
        ((totals[e.category] ?? 0.0) + converted).toStringAsFixed(2),
      );
    }
    return totals;
  }

  void clearInMemory() {
    _expensesByTrip.clear();
    notifyListeners();
  }
}
