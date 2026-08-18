import 'product_model.dart';

/// Response shape of `GET /api/products/changed` — powers the cross-device
/// catalog sync poll (see `ProductSyncNotifier` in providers.dart).
class ProductChangesResult {
  final List<ProductModel> products;
  final List<int> removedIds;
  final DateTime checkedAt;

  const ProductChangesResult({
    required this.products,
    required this.removedIds,
    required this.checkedAt,
  });

  factory ProductChangesResult.fromJson(Map<String, dynamic> j) => ProductChangesResult(
        products: (j['products'] as List)
            .map((p) => ProductModel.fromJson(p as Map<String, dynamic>))
            .toList(),
        removedIds: (j['removed_ids'] as List).cast<int>(),
        checkedAt: DateTime.parse(j['checked_at'] as String),
      );
}
