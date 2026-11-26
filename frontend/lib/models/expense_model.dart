/// An actual expense logged during a trip (MFR-11, FM4).
class ExpenseModel {
  const ExpenseModel({
    required this.expenseId,
    required this.tripId,
    required this.title,
    required this.amount,
    required this.currency,
    required this.category,
    required this.date,
    this.notes,
  });

  final String expenseId;
  final String tripId;
  final String title;
  final double amount;
  final String currency;
  final String category;
  final DateTime date;
  final String? notes;

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      expenseId: json['expense_id'] as String? ?? '',
      tripId: json['trip_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] as String? ?? 'PKR').toUpperCase(),
      category: json['category'] as String? ?? 'Other',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'expense_id': expenseId,
      'trip_id': tripId,
      'title': title,
      'amount': amount,
      'currency': currency,
      'category': category,
      'date': date.toIso8601String(),
      if (notes != null) 'notes': notes,
    };
  }

  ExpenseModel copyWith({
    String? expenseId,
    String? tripId,
    String? title,
    double? amount,
    String? currency,
    String? category,
    DateTime? date,
    String? notes,
  }) {
    return ExpenseModel(
      expenseId: expenseId ?? this.expenseId,
      tripId: tripId ?? this.tripId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      date: date ?? this.date,
      notes: notes ?? this.notes,
    );
  }
}
