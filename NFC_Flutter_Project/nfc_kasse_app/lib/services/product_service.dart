import '../models/category_model.dart';
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
    String? color,
    bool isPayout = false,
  }) async {
    final resp = await _client.dio.post('/api/products/', data: {
      'name': name,
      'price': price,
      'category_id': categoryId,
      'color': color,
      'is_payout': isPayout,
    });
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Updates a product. The [sendColor] flag controls whether the `color` field
  /// is included in the request body at all.
  ///
  /// Why the flag? The backend interprets a missing `color` key as "don't touch
  /// the color" and an explicit `null` as "clear the color". Omitting the flag
  /// (default `false`) lets callers update name/price without accidentally
  /// resetting the color.
  Future<ProductModel> updateProduct(
    int id, {
    String? name,
    double? price,
    bool sendColor = false,
    String? color,
    bool? isPayout,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (price != null) data['price'] = price;
    // sendColor=true means we explicitly set the color field (even if null = clear)
    if (sendColor) data['color'] = color;
    if (isPayout != null) data['is_payout'] = isPayout;
    final resp = await _client.dio.put('/api/products/$id', data: data);
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
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
