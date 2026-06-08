import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../models/product_model.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'dialogs/edit_product_dialog.dart';

class ProductGrid extends ConsumerWidget {
  final CategoryModel category;

  const ProductGrid({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refresh = ref.watch(productsRefreshProvider);
    final productsAsync = ref.watch(productsProvider(category.id));
    final editMode = ref.watch(editModeProvider);

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (products) => _Grid(
        products: products,
        category: category,
        editMode: editMode,
        key: ValueKey('grid-${category.id}-$refresh'),
      ),
    );
  }
}

class _Grid extends ConsumerWidget {
  final List<ProductModel> products;
  final CategoryModel category;
  final bool editMode;

  const _Grid({
    super.key,
    required this.products,
    required this.category,
    required this.editMode,
  });

  Future<void> _openEditDialog(BuildContext context, WidgetRef ref, ProductModel? product) async {
    await showDialog(
      context: context,
      builder: (_) => EditProductDialog(
        product: product,
        categoryId: category.id,
        canDelete: category.canDeleteArticle,
        canDeactivate: category.canDeactivateArticle,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiles = [...products];

    final gridColumns = ref.watch(gridColumnsProvider);
    final textScale = ref.watch(textScaleProvider);
    final buttonMaxLines = ref.watch(buttonMaxLinesProvider);

    // Tile height grows with both text scale and number of allowed text lines.
    final tileHeight = ((50 + 30 * buttonMaxLines) * textScale).clamp(70.0, 220.0);

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridColumns,
        mainAxisExtent: tileHeight,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: editMode && category.canCreateArticle ? tiles.length + 1 : tiles.length,
      itemBuilder: (context, i) {
        // "Add new" tile at the end when in edit mode
        if (editMode && category.canCreateArticle && i == tiles.length) {
          return _AddTile(onTap: () => _openEditDialog(context, ref, null));
        }

        final product = tiles[i];
        return _ProductTile(
          product: product,
          editMode: editMode && category.canManageArticles,
          maxLines: buttonMaxLines,
          onTap: () {
            if (editMode) {
              _openEditDialog(context, ref, product);
            } else {
              if (!product.active) return;
              ref.read(cartProvider.notifier).addProduct(product);
            }
          },
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  final ProductModel product;
  final bool editMode;
  final int maxLines;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.editMode,
    required this.maxLines,
    required this.onTap,
  });

  /// Returns black or white depending on the perceived luminance of [bg].
  /// Coefficients follow the ITU-R BT.601 standard for human color perception
  /// (green contributes most to perceived brightness, blue least).
  static Color _contrastColor(Color bg) {
    final luminance = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRefund = product.isRefund;
    final inactive = !product.active;

    final customColor = product.color;
    final cardColor = inactive
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : customColor ?? (isRefund
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHigh);

    // When a custom color is set, derive text colors from it for readability.
    final onCard = customColor != null && !inactive
        ? _contrastColor(customColor)
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        product.name,
                        textAlign: TextAlign.center,
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 20,
                          color: inactive
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                              : onCard,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    formatPrice(product.price),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: inactive
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : onCard ??
                              (isRefund
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.primary),
                    ),
                  ),
                  if (inactive)
                    Text(
                      'Inaktiv',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            // Edit mode pencil badge
            if (editMode)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.edit, size: 13, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 4),
            Text('Neu', style: TextStyle(color: theme.colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}
