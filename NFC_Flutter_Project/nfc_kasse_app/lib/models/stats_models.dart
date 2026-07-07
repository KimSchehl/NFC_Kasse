class StatsPeriod {
  final int id;
  final String label;
  final String startedAt;
  final String? closedAt;

  const StatsPeriod({
    required this.id,
    required this.label,
    required this.startedAt,
    this.closedAt,
  });

  bool get isOpen => closedAt == null;

  factory StatsPeriod.fromJson(Map<String, dynamic> j) => StatsPeriod(
        id: j['id'] as int,
        label: j['label'] as String,
        startedAt: j['started_at'] as String,
        closedAt: j['closed_at'] as String?,
      );
}

class ArticleBreakdown {
  final String productName;
  final double revenue; // negative = money added to chip (topup / Pfand issue)
  final int transactionCount;
  final bool isPayout;
  final bool excludeFromStats;

  const ArticleBreakdown({
    required this.productName,
    required this.revenue,
    required this.transactionCount,
    required this.isPayout,
    required this.excludeFromStats,
  });

  factory ArticleBreakdown.fromJson(Map<String, dynamic> j) => ArticleBreakdown(
        productName: j['product_name'] as String,
        revenue: (j['revenue'] as num).toDouble(),
        transactionCount: j['transaction_count'] as int,
        isPayout: j['is_payout'] as bool? ?? false,
        excludeFromStats: j['exclude_from_stats'] as bool? ?? false,
      );
}

class CategoryRevenue {
  final String categoryName;
  final double revenue;
  final int transactionCount;
  final List<ArticleBreakdown> articles;

  const CategoryRevenue({
    required this.categoryName,
    required this.revenue,
    required this.transactionCount,
    this.articles = const [],
  });

  factory CategoryRevenue.fromJson(Map<String, dynamic> j) => CategoryRevenue(
        categoryName: j['category_name'] as String,
        revenue: (j['revenue'] as num).toDouble(),
        transactionCount: j['transaction_count'] as int,
        articles: (j['articles'] as List? ?? [])
            .map((a) => ArticleBreakdown.fromJson(a as Map<String, dynamic>))
            .toList(),
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
  final String? customerName;
  final String productName;
  final double priceAtSale;
  final String categoryName;
  final String bookedByUsername;
  final bool cancelled;

  const TransactionItem({
    required this.id,
    required this.bookedAt,
    required this.nfcUid,
    this.customerName,
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
        customerName: j['customer_name'] as String?,
        productName: j['product_name'] as String,
        priceAtSale: (j['price_at_sale'] as num).toDouble(),
        categoryName: j['category_name'] as String,
        bookedByUsername: j['booked_by_username'] as String,
        cancelled: j['cancelled'] as bool? ?? false,
      );
}
