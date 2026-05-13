/// A guest whose NFC wristband has been scanned.
///
/// [isNew] is true when the UID has never been seen before — the balance
/// screen shows a "Neuer Kunde" badge and the Buchen button is disabled
/// until the guest tops up (or the vendor accepts a negative balance).
///
/// The balance is always server-side. The NFC chip stores only the UID.
class CustomerModel {
  final String nfcUid;
  final double balance;
  final bool isNew;

  const CustomerModel({
    required this.nfcUid,
    required this.balance,
    this.isNew = false,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> j) => CustomerModel(
        nfcUid: j['nfc_uid'] as String,
        balance: (j['balance'] as num).toDouble(),
        isNew: j['is_new_customer'] as bool? ?? false,
      );

  /// Returns a copy with an updated balance, preserving all other fields.
  /// Used by the POS and cancel dialog to reflect the server's new balance
  /// immediately without re-fetching the full customer.
  CustomerModel withBalance(double newBalance) =>
      CustomerModel(nfcUid: nfcUid, balance: newBalance, isNew: isNew);
}
