/// A guest whose NFC wristband has been scanned.
///
/// [isNew] is true when the chip is being issued for the first time or was
/// previously returned via payout (is_available=1 on the server). The cart
/// automatically adds a locked "Chip Pfand" line when isNew is true.
///
/// [chipDeposit] is the configured deposit amount in EUR (from CHIP_DEPOSIT
/// in config.env). Always present so the cart can show the refund on payout.
///
/// The balance is always server-side. The NFC chip stores only the UID.
class CustomerModel {
  final String nfcUid;
  final double balance;
  final bool isNew;
  final double chipDeposit;

  const CustomerModel({
    required this.nfcUid,
    required this.balance,
    this.isNew = false,
    this.chipDeposit = 0.0,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> j) => CustomerModel(
        nfcUid: j['nfc_uid'] as String,
        balance: (j['balance'] as num).toDouble(),
        isNew: j['is_new_customer'] as bool? ?? false,
        chipDeposit: (j['chip_deposit'] as num?)?.toDouble() ?? 0.0,
      );

  /// Returns a copy with an updated balance, preserving all other fields.
  CustomerModel withBalance(double newBalance) =>
      CustomerModel(nfcUid: nfcUid, balance: newBalance, isNew: isNew, chipDeposit: chipDeposit);
}
