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
    bool isPayout = false,
    bool excludeFromStats = false,
  }) async {
    final resp = await _client.dio.post('/api/products/', data: {
      'name': name,
      'price': price,
      'category_id': categoryId,
      'is_payout': isPayout,
      'exclude_from_stats': excludeFromStats,
    });
    return ProductModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ProductModel> updateProduct(
    int id, {
    String? name,
    double? price,
    bool? isPayout,
    bool? excludeFromStats,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (price != null) data['price'] = price;
    if (isPayout != null) data['is_payout'] = isPayout;
    if (excludeFromStats != null) data['exclude_from_stats'] = excludeFromStats;
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
