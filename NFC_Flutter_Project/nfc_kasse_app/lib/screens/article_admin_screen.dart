import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/admin_category_products.dart';
import '../models/product_model.dart';
import '../providers/providers.dart';
import '../services/app_logger.dart';
import '../utils/formatters.dart';
import '../widgets/dialogs/edit_product_dialog.dart';
import '../widgets/tree_branch.dart';

/// Full-screen article management: every category the logged-in user holds
/// any article-management right in, each listing its top-level articles.
/// Options never appear as their own row here — they only ever surface
/// inside their base article's [EditProductDialog] (opened by tapping a
/// row). Reachable via the sidebar ("Artikelverwaltung"), gated on
/// `UserModel.canManageAnyArticles`.
///
/// The POS grid's own edit mode only offers the narrow quick-edit popup
/// (color + stock) — this screen is the only place articles are created,
/// renamed, re-priced, or moved between categories.
///
/// Categories and articles belong to the Veranstalter; this screen lists all
/// of them and is where they are switched on/off for the running fest
/// ("Im Fest" switches).
class ArticleAdminScreen extends ConsumerWidget {
  const ArticleAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(adminCategoriesProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Text('Artikelverwaltung', style: theme.textTheme.titleMedium),
        ),
        Expanded(
          child: categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
            data: (categories) => categories.isEmpty
                ? const Center(child: Text('Keine Kategorien mit Artikel-Rechten'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: categories.length,
                    itemBuilder: (_, i) => _CategorySection(data: categories[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

/// One category's card: header (+ "Neuer Artikel" when allowed) and its
/// top-level articles. Also a [DragTarget] for articles long-press-dragged
/// in from another category's [_CategorySection].
class _CategorySection extends ConsumerWidget {
  final AdminCategoryProducts data;

  const _CategorySection({required this.data});

  Future<void> _move(BuildContext context, WidgetRef ref, ProductModel product) async {
    AppLogger.trace(
      'Artikel verschoben: ${product.name} -> ${data.category.name}',
      logger: 'ui.admin',
    );
    try {
      await ref.read(productServiceProvider).moveProduct(product.id, categoryId: data.category.id);
      ref.read(adminCategoriesRefreshProvider.notifier).state++;
      ref.read(productsRefreshProvider.notifier).state++;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  /// Reloads everything that shows what the running fest offers: this
  /// screen, the till's category list (/me) and the article grids.
  Future<void> _afterFestChange(WidgetRef ref) async {
    ref.read(adminCategoriesRefreshProvider.notifier).state++;
    ref.invalidate(productsProvider);
    await ref.read(authProvider.notifier).refreshFromServer();
  }

  Future<void> _setCategoryInEvent(BuildContext context, WidgetRef ref, bool active) async {
    AppLogger.trace(
      'Kategorie ${active ? "eingeschaltet" : "ausgeschaltet"}: ${data.category.name}',
      logger: 'ui.admin',
    );
    try {
      await ref.read(productServiceProvider).setCategoryInEvent(data.category.id, active);
      if (!active && ref.read(selectedCategoryProvider)?.id == data.category.id) {
        ref.read(selectedCategoryProvider.notifier).state = null;
      }
      await _afterFestChange(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _setProductInEvent(BuildContext context, WidgetRef ref, ProductModel product, bool active) async {
    AppLogger.trace(
      'Artikel ${active ? "eingeschaltet" : "ausgeschaltet"}: ${product.name}',
      logger: 'ui.admin',
    );
    try {
      await ref.read(productServiceProvider).setInEvent(product.id, active);
      await _afterFestChange(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
      }
    }
  }

  Future<void> _openDialog(BuildContext context, WidgetRef ref, ProductModel? product) async {
    AppLogger.trace(
      'Artikelverwaltung-Dialog geöffnet: ${product?.name ?? "Neuer Artikel"}',
      logger: 'ui.admin',
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => EditProductDialog(
        product: product,
        categoryId: data.category.id,
        allCategoryProducts: data.products,
        canEditDetails: product == null ? true : data.category.canEditArticle,
        canCreateArticle: data.category.canCreateArticle,
        canDelete: data.category.canDeleteArticle,
        canDeactivate: data.category.canDeactivateArticle,
      ),
    );
    if (result == true) {
      ref.read(adminCategoriesRefreshProvider.notifier).state++;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final topLevel = data.topLevel;
    final canSwitchCategory =
        ref.watch(authProvider).valueOrNull?.hasPermission('categories.deactivate') ?? false;
    final categoryOn = data.category.activeInEvent;

    return DragTarget<ProductModel>(
      onWillAcceptWithDetails: (details) => details.data.categoryId != data.category.id,
      onAcceptWithDetails: (details) => _move(context, ref, details.data),
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: highlighted ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        categoryOn ? data.category.name : '${data.category.name} · nicht in diesem Fest',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: categoryOn ? null : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (canSwitchCategory) ...[
                      Text('Im Fest', style: theme.textTheme.labelSmall),
                      Switch(
                        value: categoryOn,
                        onChanged: (v) => _setCategoryInEvent(context, ref, v),
                      ),
                    ],
                    if (data.category.canCreateArticle)
                      TextButton.icon(
                        onPressed: () => _openDialog(context, ref, null),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Neuer Artikel'),
                      ),
                  ],
                ),
                if (topLevel.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Keine Artikel',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  TreeBranch(
                    lineColor: theme.colorScheme.outlineVariant,
                    children: [
                      for (final p in topLevel)
                        _ArticleRow(
                          product: p,
                          optionCount: data.optionsOf(p.id).length,
                          onTap: () => _openDialog(context, ref, p),
                          onInEventChanged: data.category.canDeactivateArticle
                              ? (v) => _setProductInEvent(context, ref, p, v)
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final ProductModel product;
  final int optionCount;
  final VoidCallback onTap;

  /// Switches the article on/off for the running fest; null = no right.
  final ValueChanged<bool>? onInEventChanged;

  const _ArticleRow({
    required this.product,
    required this.optionCount,
    required this.onTap,
    this.onInEventChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = [
      formatPrice(product.price),
      if (optionCount > 0) '$optionCount ${optionCount == 1 ? "Option" : "Optionen"}',
      if (product.stock != null) 'Bestand: ${product.stock}',
      if (!product.inEvent) 'nicht in diesem Fest',
    ];
    final dimmed = !product.active || !product.inEvent;

    final row = ListTile(
      dense: true,
      title: Text(
        product.name,
        style: TextStyle(color: dimmed ? theme.colorScheme.onSurfaceVariant : null),
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!product.active) ...[
            const Chip(
              label: Text('Inaktiv'),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(fontSize: 11),
            ),
            const SizedBox(width: 8),
          ],
          if (onInEventChanged != null)
            Tooltip(
              message: 'In diesem Fest anbieten',
              child: Switch(value: product.inEvent, onChanged: onInEventChanged),
            ),
          Icon(Icons.drag_indicator, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );

    return LongPressDraggable<ProductModel>(
      data: product,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(product.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: row),
      child: row,
    );
  }
}
