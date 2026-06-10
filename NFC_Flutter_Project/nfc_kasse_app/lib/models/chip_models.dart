class ChipModel {
  final String nfcUid;
  final double balance;
  final bool isAvailable;
  final String? lastBookedAt;
  final String? lastProductName;

  const ChipModel({
    required this.nfcUid,
    required this.balance,
    required this.isAvailable,
    this.lastBookedAt,
    this.lastProductName,
  });

  factory ChipModel.fromJson(Map<String, dynamic> j) => ChipModel(
        nfcUid: j['nfc_uid'] as String,
        balance: (j['balance'] as num).toDouble(),
        isAvailable: j['is_available'] as bool,
        lastBookedAt: j['last_booked_at'] as String?,
        lastProductName: j['last_product_name'] as String?,
      );

  bool get isActive => !isAvailable;
}

class ChipSummary {
  final int totalChips;
  final int activeChips;
  final double totalBalance;
  final double pendingPfand;
  final double totalTopup;
  final double totalPayout;

  const ChipSummary({
    required this.totalChips,
    required this.activeChips,
    required this.totalBalance,
    required this.pendingPfand,
    required this.totalTopup,
    required this.totalPayout,
  });

  factory ChipSummary.fromJson(Map<String, dynamic> j) => ChipSummary(
        totalChips: j['total_chips'] as int,
        activeChips: j['active_chips'] as int,
        totalBalance: (j['total_balance'] as num).toDouble(),
        pendingPfand: (j['pending_pfand'] as num).toDouble(),
        totalTopup: (j['total_topup'] as num).toDouble(),
        totalPayout: (j['total_payout'] as num).toDouble(),
      );
}
