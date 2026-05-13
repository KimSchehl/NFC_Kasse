class CategoryRevenue {
  final String categoryName;
  final double revenue;
  final int transactionCount;

  const CategoryRevenue({
    required this.categoryName,
    required this.revenue,
    required this.transactionCount,
  });

  factory CategoryRevenue.fromJson(Map<String, dynamic> j) => CategoryRevenue(
        categoryName: j['category_name'] as String,
        revenue: (j['revenue'] as num).toDouble(),
        transactionCount: j['transaction_count'] as int,
      );
}

class RevenueStats {
  final double totalRevenue;
  final int totalTransactions;
  final List<CategoryRevenue> byCategory;

  const RevenueStats({
    required this.totalRevenue,
    required this.totalTransactions,
    required this.byCategory,
  });

  factory RevenueStats.fromJson(Map<String, dynamic> j) => RevenueStats(
        totalRevenue: (j['total_revenue'] as num).toDouble(),
        totalTransactions: j['total_transactions'] as int,
        byCategory: (j['by_category'] as List)
            .map((c) => CategoryRevenue.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class TransactionItem {
  final int id;
  final String bookedAt;
  final String nfcUid;
  final String productName;
  final double priceAtSale;
  final String categoryName;
  final String bookedByUsername;
  final bool cancelled;

  const TransactionItem({
    required this.id,
    required this.bookedAt,
    required this.nfcUid,
    required this.productName,
    required this.priceAtSale,
    required this.categoryName,
    required this.bookedByUsername,
    required this.cancelled,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> j) => TransactionItem(
        id: j['id'] as int,
        bookedAt: j['booked_at'] as String,
        nfcUid: j['nfc_uid'] as String,
        productName: j['product_name'] as String,
        priceAtSale: (j['price_at_sale'] as num).toDouble(),
        categoryName: j['category_name'] as String,
        bookedByUsername: j['booked_by_username'] as String,
        cancelled: j['cancelled'] as bool? ?? false,
      );
}
