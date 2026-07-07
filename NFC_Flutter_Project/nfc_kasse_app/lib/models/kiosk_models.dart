class KioskTransaction {
  final String type; // 'sale' | 'topup'
  final int id;
  final String description;
  final double price; // negative = sale (money out), positive = topup (money in)
  final DateTime bookedAt;
  final bool cancelled;
  final DateTime? cancelledAt;
  final String bookedBy;

  const KioskTransaction({
    required this.type,
    required this.id,
    required this.description,
    required this.price,
    required this.bookedAt,
    required this.cancelled,
    this.cancelledAt,
    required this.bookedBy,
  });

  factory KioskTransaction.fromJson(Map<String, dynamic> j) => KioskTransaction(
        type: j['type'] as String,
        id: j['id'] as int,
        description: j['description'] as String,
        price: (j['price'] as num).toDouble(),
        bookedAt: DateTime.parse(j['booked_at'] as String),
        cancelled: j['cancelled'] as bool,
        cancelledAt: j['cancelled_at'] != null
            ? DateTime.parse(j['cancelled_at'] as String)
            : null,
        bookedBy: j['booked_by'] as String,
      );
}

class KioskChipInfo {
  final String nfcUid;
  final double balance;
  final double chipDeposit;
  final String? customerName;
  final bool isNewCustomer;
  final List<KioskTransaction> transactions;

  const KioskChipInfo({
    required this.nfcUid,
    required this.balance,
    required this.chipDeposit,
    this.customerName,
    required this.isNewCustomer,
    required this.transactions,
  });

  factory KioskChipInfo.fromJson(Map<String, dynamic> j) => KioskChipInfo(
        nfcUid: j['nfc_uid'] as String,
        balance: (j['balance'] as num).toDouble(),
        chipDeposit: (j['chip_deposit'] as num).toDouble(),
        customerName: j['customer_name'] as String?,
        isNewCustomer: j['is_new_customer'] as bool,
        transactions: (j['transactions'] as List)
            .map((t) => KioskTransaction.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}
