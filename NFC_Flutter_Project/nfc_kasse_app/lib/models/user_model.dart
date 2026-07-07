import 'category_model.dart';

/// Full user profile returned by `/api/auth/me`.
///
/// [permissions] is the flat list of leaf-node permission IDs the user holds
/// for the active event (e.g. `'guthaben.topup'`). Group nodes are
/// never included — only actionable leaf nodes are stored in `user_permission`.
///
/// [categories] lists the categories the user has access to, including the
/// per-category flags. Managers receive all categories with full flags.
class UserModel {
  final int id;
  final String username;
  final String? displayName;
  final List<String> permissions;
  final List<CategoryModel> categories;

  const UserModel({
    required this.id,
    required this.username,
    this.displayName,
    required this.permissions,
    required this.categories,
  });

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'] as int,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        permissions: (j['permissions'] as List).cast<String>(),
        // The /me endpoint returns categories as {category_id, category_name, can_*},
        // which we remap to the standard CategoryModel.fromJson key names.
        categories: (j['categories'] as List)
            .map((c) => CategoryModel.fromJson({
                  'id': c['category_id'],
                  'name': c['category_name'],
                  'sort_order': 0,
                  'can_book': c['can_book'],
                  'can_storno_5min': c['can_storno_5min'],
                  'can_storno_unlimited': c['can_storno_unlimited'],
                  'can_create_article': c['can_create_article'],
                  'can_edit_article': c['can_edit_article'],
                  'can_deactivate_article': c['can_deactivate_article'],
                  'can_delete_article': c['can_delete_article'],
                }))
            .toList(),
      );

  bool hasPermission(String p) => permissions.contains(p);

  /// A user is treated as a "manager" if they hold any category-management
  /// permission. Managers see all categories regardless of `user_category_access`
  /// rows — this mirrors the server-side logic in `/me` and the products router.
  bool get isManager => permissions.any(
        (p) => p == 'categories.create' || p == 'categories.edit' ||
               p == 'categories.deactivate' || p == 'categories.delete',
      );

  bool get isKiosk => hasPermission('kiosk.access');

  bool get canManageUsers => hasPermission('users.manage_permissions');

  /// True for any statistics permission — stats screen and sidebar link are
  /// shown as soon as the user has at least one of the three stats permissions.
  bool get canViewStats => permissions.any((p) => p.startsWith('statistics.'));

  String get displayLabel => displayName ?? username;
}

// Lightweight user row returned from the user list endpoint
class UserListItem {
  final int id;
  final String username;
  final String? displayName;
  final bool active;

  const UserListItem({
    required this.id,
    required this.username,
    this.displayName,
    required this.active,
  });

  factory UserListItem.fromJson(Map<String, dynamic> j) => UserListItem(
        id: j['id'] as int,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        active: j['active'] as bool? ?? true,
      );

  String get displayLabel => displayName ?? username;
}
