/// Immutable product as returned by the API.
///
/// Products may have a negative [price] (e.g. "Pfand Rückgabe", "Aufladen").
/// Button colors are stored per-user in [UserPreferences], not on the product.
class ProductModel {
  final int id;
  final String name;
  final double price;
  final int categoryId;
  final int sortOrder;
  final bool active;
  final bool isPayout;
  final bool excludeFromStats;

  const ProductModel({
    required this.id,
    required this.name,
    required this.price,
    required this.categoryId,
    required this.sortOrder,
    required this.active,
    this.isPayout = false,
    this.excludeFromStats = false,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) => ProductModel(
        id: j['id'] as int,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        categoryId: j['category_id'] as int,
        sortOrder: j['sort_order'] as int? ?? 0,
        active: j['active'] as bool? ?? true,
        isPayout: j['is_payout'] as bool? ?? false,
        excludeFromStats: j['exclude_from_stats'] as bool? ?? false,
      );

  // Negative price = refund/topup (Pfand Rückgabe, Aufladen)
  bool get isRefund => price < 0;
}
