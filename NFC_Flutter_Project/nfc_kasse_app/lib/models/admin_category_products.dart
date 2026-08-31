import 'category_model.dart';
import 'product_model.dart';

/// One category's worth of data for the article admin screen: the category
/// itself (with the current user's article-management flags) plus *every*
/// one of its articles, active or not — unlike the normal per-category
/// product fetch, which hides inactive articles from users who can edit but
/// not deactivate (see backend's GET /api/products/admin docstring).
class AdminCategoryProducts {
  final CategoryModel category;
  final List<ProductModel> products;

  const AdminCategoryProducts({required this.category, required this.products});

  factory AdminCategoryProducts.fromJson(Map<String, dynamic> j) => AdminCategoryProducts(
        category: CategoryModel.fromJson(j),
        products: (j['products'] as List)
            .map((p) => ProductModel.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  /// Articles with their own tile — excludes options (see ProductModel.groupId).
  List<ProductModel> get topLevel => products.where((p) => p.groupId == null).toList();

  /// The options belonging to [baseId], in their saved order.
  List<ProductModel> optionsOf(int baseId) =>
      products.where((p) => p.groupId == baseId).toList();
}
