/// A product category as seen by the current user.
///
/// The permission flags come from `user_category_access` on the server and
/// reflect what the logged-in user is allowed to do within this category.
/// Admins/managers always receive all flags as `true`.
class CategoryModel {
  final int id;
  final String name;
  final int sortOrder;

  // Booking permissions (per-category, checked server-side on booking/cancel)
  final bool canBook;
  final bool canStorno5min;
  final bool canStornoUnlimited;

  // Article management permissions
  final bool canCreateArticle;
  final bool canEditArticle;
  final bool canDeactivateArticle;
  final bool canDeleteArticle;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.sortOrder,
    this.canBook = false,
    this.canStorno5min = false,
    this.canStornoUnlimited = false,
    this.canCreateArticle = false,
    this.canEditArticle = false,
    this.canDeactivateArticle = false,
    this.canDeleteArticle = false,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> j) => CategoryModel(
        id: j['id'] as int,
        name: j['name'] as String,
        sortOrder: j['sort_order'] as int? ?? 0,
        canBook: j['can_book'] as bool? ?? false,
        canStorno5min: j['can_storno_5min'] as bool? ?? false,
        canStornoUnlimited: j['can_storno_unlimited'] as bool? ?? false,
        canCreateArticle: j['can_create_article'] as bool? ?? false,
        canEditArticle: j['can_edit_article'] as bool? ?? false,
        canDeactivateArticle: j['can_deactivate_article'] as bool? ?? false,
        canDeleteArticle: j['can_delete_article'] as bool? ?? false,
      );

  /// True when the user has at least one article-management right.
  /// Used to decide whether to show the edit badge on product tiles.
  bool get canManageArticles =>
      canCreateArticle || canEditArticle || canDeactivateArticle || canDeleteArticle;
}
