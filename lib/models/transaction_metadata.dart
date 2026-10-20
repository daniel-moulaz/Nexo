class TransactionMetadata {
  final String transactionId;
  final String subcategory;
  final String status; // paid | pending
  final DateTime? dueDate;
  final String expenseClass; // normal | extraordinary
  final bool excludeFromSpending;
  final int? installmentCurrent;
  final int? installmentTotal;
  final bool affectsBalance;
  final String source; // manual | import | recurring

  const TransactionMetadata({
    required this.transactionId,
    this.subcategory = '',
    this.status = 'paid',
    this.dueDate,
    this.expenseClass = 'normal',
    this.excludeFromSpending = false,
    this.installmentCurrent,
    this.installmentTotal,
    this.source = 'manual',
    this.affectsBalance = true,
  });

  bool get isPending => status == 'pending';

  bool get isOverdue {
    if (!isPending || dueDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  String get installmentLabel {
    if (installmentCurrent == null || installmentTotal == null) return '';
    return '$installmentCurrent/$installmentTotal';
  }

  Map<String, dynamic> toMap() => {
        'transaction_id': transactionId,
        'subcategory': subcategory,
        'status': status,
        'due_date': dueDate?.toIso8601String(),
        'expense_class': expenseClass,
        'exclude_from_spending': excludeFromSpending ? 1 : 0,
        'installment_current': installmentCurrent,
        'installment_total': installmentTotal,
        'source': source,
        'affects_balance': affectsBalance ? 1 : 0,
      };

  static TransactionMetadata fromMap(Map<String, dynamic> map) {
    return TransactionMetadata(
      transactionId: map['transaction_id'] as String? ?? '',
      subcategory: map['subcategory'] as String? ?? '',
      status: map['status'] as String? ?? 'paid',
      dueDate: map['due_date'] != null
          ? DateTime.tryParse(map['due_date'] as String)
          : null,
      expenseClass: map['expense_class'] as String? ?? 'normal',
      excludeFromSpending: (map['exclude_from_spending'] as int? ?? 0) == 1,
      installmentCurrent: map['installment_current'] as int?,
      installmentTotal: map['installment_total'] as int?,
      source: map['source'] as String? ?? 'manual',
      affectsBalance: (map['affects_balance'] as int? ?? 1) == 1,
    );
  }
}
