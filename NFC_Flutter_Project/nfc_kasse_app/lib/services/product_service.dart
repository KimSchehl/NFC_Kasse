import '../models/admin_category_products.dart';
import '../models/category_model.dart';
import '../models/product_changes_result.dart';
import '../models/product_model.dart';
import 'api_client.dart';

/// CRUD operations for categories and products.
class ProductService {
  final ApiClient _client;
  ProductService(this._client);

  Future<List<CategoryModel>> getCategories() async {
    final resp = await _client.dio.get('/api/products/categories');
    return (resp.data as List)
        .map((j) => CategoryModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<ProductModel>> getProducts(int categoryId) async {
    final resp = await _client.dio.get('/api/products/', queryParameters: {'category_id': categoryId});
    return (resp.data as List)
        .map((j) => ProductModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ProductModel> createProduct({
    required String name,
    required double price,
    required int categoryId,
    bool isPayout = false,
    bool excludeFromStats = false,
    int points = 0,
    int? stock,
    bool requiresPager = false,
    int? groupId,
  }) async {
    final resp = await _client.dio.post('/api/products/', data: {
      'name': name,
      'price': price,
      'category_id': categoryId,
      'is_payout': isPayout,
      'exclude_from_stats': excludeFromStats,
      'points': points,
      'stock': stock,
      'requires_pager': requiresPager,
      'group_id': groupId,
    });
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ProductModel> updateProduct(
    int id, {
    String? name,
    double? price,
    int? categoryId,
    bool? isPayout,
    bool? excludeFromStats,
    int? points,
    int? stock,
    bool? requiresPager,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (price != null) data['price'] = price;
    if (categoryId != null) data['category_id'] = categoryId;
    if (isPayout != null) data['is_payout'] = isPayout;
    if (excludeFromStats != null) data['exclude_from_stats'] = excludeFromStats;
    if (points != null) data['points'] = points;
    if (requiresPager != null) data['requires_pager'] = requiresPager;
    // Unlike every other field here, `stock` is always sent explicitly, even
    // when null — the only caller (the edit dialog) always resends the full
    // current stock state, and null legitimately means "clear tracking", not
    // "leave unchanged". Don't "fix" this to match the `if (x != null)`
    // pattern above; that would silently reintroduce the inability to clear it.
    data['stock'] = stock;
    final resp = await _client.dio.put('/api/products/$id', data: data);
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Moves an already-existing, top-level (never-grouped) article between
  /// categories — the article admin screen's drag-and-drop action. Kept
  /// separate from [updateProduct] so that method's simpler "send only
  /// what changed" contract doesn't have to grow a third explicit-null
  /// field (after `stock`) just for this one caller; always sends
  /// `group_id` (even null) for an unambiguous "this is exactly where the
  /// article now belongs" request.
  Future<ProductModel> moveProduct(int id, {int? categoryId, int? groupId}) async {
    final data = <String, dynamic>{'group_id': groupId};
    if (categoryId != null) data['category_id'] = categoryId;
    final resp = await _client.dio.put('/api/products/$id', data: data);
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Powers the article admin screen: every article (incl. inactive) across
  /// every category the user can manage articles in.
  Future<List<AdminCategoryProducts>> getAdminCategories() async {
    final resp = await _client.dio.get('/api/products/admin');
    final data = resp.data as Map<String, dynamic>;
    return (data['categories'] as List)
        .map((j) => AdminCategoryProducts.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Powers cross-device catalog sync: returns only the products in
  /// [categoryId] that changed after [since], plus IDs of any that were
  /// deleted since then.
  Future<ProductChangesResult> getChangedProducts(int categoryId, DateTime since) async {
    final resp = await _client.dio.get('/api/products/changed', queryParameters: {
      'category_id': categoryId,
      'since': since.toIso8601String(),
    });
    return ProductChangesResult.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ProductModel> setActive(int id, bool active) async {
    final resp = await _client.dio.patch('/api/products/$id/active', data: {'active': active});
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteProduct(int id) async {
    await _client.dio.delete('/api/products/$id');
  }

  Future<CategoryModel> createCategory(String name) async {
    final resp = await _client.dio.post('/api/products/categories', data: {'name': name});
    return CategoryModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<CategoryModel> updateCategory(int id, String name) async {
    final resp = await _client.dio.put('/api/products/categories/$id', data: {'name': name});
    return CategoryModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(int id) async {
    await _client.dio.delete('/api/products/categories/$id');
  }
}
