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

  /// Returns the global leaf-permission nodes as a flat list grouped by section.
  ///
  /// Booking / storno / article permissions are per-category (user_category_access)
  /// and are NOT in this list — they are shown separately in the category tree.
  Future<List<Map<String, dynamic>>> getPermissionTree() async {
    return const [
      // Guthaben
      {'id': 'guthaben.topup',          'label': 'Aufladen',                'group': 'Guthaben'},
      {'id': 'guthaben.payout',         'label': 'Auszahlen',               'group': 'Guthaben'},
      // Kategorien
      {'id': 'categories.create',       'label': 'Kategorie erstellen',     'group': 'Kategorien'},
      {'id': 'categories.edit',         'label': 'Kategorie bearbeiten',    'group': 'Kategorien'},
      {'id': 'categories.deactivate',   'label': 'Kategorie deaktivieren',  'group': 'Kategorien'},
      {'id': 'categories.delete',       'label': 'Kategorie löschen',       'group': 'Kategorien'},
      // Statistik
      {'id': 'statistics.revenue',      'label': 'Umsatz anzeigen',         'group': 'Statistik'},
      {'id': 'statistics.transactions', 'label': 'Transaktionen',           'group': 'Statistik'},
      {'id': 'statistics.export',       'label': 'CSV Export',              'group': 'Statistik'},
      // Benutzerverwaltung
      {'id': 'users.view',              'label': 'Benutzer anzeigen',       'group': 'Benutzer'},
      {'id': 'users.create',            'label': 'Benutzer erstellen',      'group': 'Benutzer'},
      {'id': 'users.edit',              'label': 'Benutzer bearbeiten',     'group': 'Benutzer'},
      {'id': 'users.deactivate',        'label': 'Benutzer deaktivieren',   'group': 'Benutzer'},
      {'id': 'users.delete',            'label': 'Benutzer löschen',        'group': 'Benutzer'},
      {'id': 'users.manage_permissions','label': 'Rechte vergeben',         'group': 'Benutzer'},
      // Notfall
      {'id': 'help.receive',            'label': 'Notfall-Kontakt',          'group': 'Notfall'},
    ];
  }
}
