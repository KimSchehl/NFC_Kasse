import '../models/category_model.dart';
import '../models/user_model.dart';
import 'api_client.dart';

/// CRUD operations for user accounts, permissions, and category access.
class UsersService {
  final ApiClient _client;
  UsersService(this._client);

  Future<List<UserListItem>> getUsers() async {
    final resp = await _client.dio.get('/api/users/');
    return (resp.data as List)
        .map((j) => UserListItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<UserListItem> createUser({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final data = <String, dynamic>{'username': username, 'password': password};
    if (displayName != null) data['display_name'] = displayName;
    final resp = await _client.dio.post('/api/users/', data: data);
    return UserListItem.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<UserListItem> updateUser(int id, {String? username, String? password, String? displayName}) async {
    final data = <String, dynamic>{};
    if (username != null) data['username'] = username;
    if (password != null && password.isNotEmpty) data['password'] = password;
    if (displayName != null) data['display_name'] = displayName;
    final resp = await _client.dio.put('/api/users/$id', data: data);
    return UserListItem.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deactivateUser(int id) async {
    await _client.dio.delete('/api/users/$id');
  }

  Future<Map<String, dynamic>> getUserPermissions(int id) async {
    final resp = await _client.dio.get('/api/users/$id/permissions');
    return resp.data as Map<String, dynamic>;
  }

  Future<void> setPermissions(int id, List<String> permissionIds) async {
    await _client.dio.put('/api/users/$id/permissions', data: {
      'permission_ids': permissionIds,
    });
  }

  Future<void> setCategoryAccess(
    int userId,
    List<CategoryModel> categories,
  ) async {
    await _client.dio.put('/api/users/$userId/categories', data: {
      'categories': categories
          .map((c) => {
                'category_id': c.id,
                'can_book': c.canBook,
                'can_storno_5min': c.canStorno5min,
                'can_storno_unlimited': c.canStornoUnlimited,
                'can_create_article': c.canCreateArticle,
                'can_edit_article': c.canEditArticle,
                'can_deactivate_article': c.canDeactivateArticle,
                'can_delete_article': c.canDeleteArticle,
              })
          .toList(),
    });
  }

  /// Fetches the global leaf-permission nodes from the backend, grouped by
  /// their parent section label. Adding a new permission to the DB is now
  /// sufficient — no Flutter change needed.
  Future<List<Map<String, dynamic>>> getPermissionTree() async {
    final resp = await _client.dio.get('/api/users/permission-tree');
    return (resp.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
