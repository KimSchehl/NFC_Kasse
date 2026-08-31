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
                      child: Text(data.category.name, style: theme.textTheme.titleSmall),
                    ),
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

  const _ArticleRow({required this.product, required this.optionCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = [
      formatPrice(product.price),
      if (optionCount > 0) '$optionCount ${optionCount == 1 ? "Option" : "Optionen"}',
      if (product.stock != null) 'Bestand: ${product.stock}',
    ];

    final row = ListTile(
      dense: true,
      title: Text(
        product.name,
        style: TextStyle(color: product.active ? null : theme.colorScheme.onSurfaceVariant),
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
