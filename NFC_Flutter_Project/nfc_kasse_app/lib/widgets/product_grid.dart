import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../models/product_model.dart';
import '../models/user_preferences_model.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'dialogs/edit_product_dialog.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

class ProductGrid extends ConsumerWidget {
  final CategoryModel category;

  const ProductGrid({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider(category.id));
    final editMode = ref.watch(editModeProvider);
    final prefs = ref.watch(userPrefsProvider);
    // P = narrow (phone/portrait), L = wide (tablet/landscape)
    final profile = MediaQuery.sizeOf(context).width >= 600 ? 'L' : 'P';

    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
      data: (products) => _Grid(
        key: ValueKey('grid-${category.id}-$profile'),
        products: products,
        category: category,
        editMode: editMode,
        prefs: prefs,
        profile: profile,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid — stateful so drag state stays local
// ---------------------------------------------------------------------------

class _Grid extends ConsumerStatefulWidget {
  final List<ProductModel> products;
  final CategoryModel category;
  final bool editMode;
  final UserPreferences prefs;
  final String profile;

  const _Grid({
    super.key,
    required this.products,
    required this.category,
    required this.editMode,
    required this.prefs,
    required this.profile,
  });

  @override
  ConsumerState<_Grid> createState() => _GridState();
}

class _GridState extends ConsumerState<_Grid> {
  int? _draggingIndex;

  /// Builds the ordered slot list from saved layout + any new products appended.
  /// Deleted product IDs are removed; user-added null gaps are preserved.
  List<int?> _buildSlots() {
    final saved = widget.prefs.getLayout(widget.category.id, widget.profile);
    final existing = widget.products.map((p) => p.id).toSet();

    if (saved == null) {
      return widget.products.map((p) => p.id as int?).toList();
    }

    // Remove IDs of products that were deleted since layout was saved.
    final valid = saved.where((id) => id == null || existing.contains(id)).toList();

    // Append products added after the layout was last saved.
    final inLayout = valid.whereType<int>().toSet();
    final appended = widget.products
        .where((p) => !inLayout.contains(p.id))
        .map((p) => p.id as int?);

    return [...valid, ...appended];
  }

  void _swap(int from, int to) {
    if (from == to) return;
    final slots = _buildSlots();
    final tmp = slots[from];
    slots[from] = slots[to];
    slots[to] = tmp;
    ref.read(userPrefsProvider.notifier).setLayout(
          widget.category.id, widget.profile, slots);
  }

  void _addEmptySlot() {
    ref.read(userPrefsProvider.notifier).setLayout(
          widget.category.id, widget.profile, [..._buildSlots(), null]);
  }

  void _removeLastEmptySlot() {
    final slots = _buildSlots();
    final idx = slots.lastIndexOf(null);
    if (idx < 0) return;
    slots.removeAt(idx);
    ref.read(userPrefsProvider.notifier).setLayout(
          widget.category.id, widget.profile, slots);
  }

  Future<void> _openEdit(BuildContext context, ProductModel? product) async {
    await showDialog(
      context: context,
      builder: (_) => EditProductDialog(
        product: product,
        categoryId: widget.category.id,
        canEditDetails: product == null ? true : widget.category.canEditArticle,
        canDelete: widget.category.canDeleteArticle,
        canDeactivate: widget.category.canDeactivateArticle,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final slots = _buildSlots();
    final productMap = {for (final p in widget.products) p.id: p};
    final gridColumns = ref.watch(gridColumnsProvider);
    final textScale = ref.watch(textScaleProvider);
    final buttonMaxLines = ref.watch(buttonMaxLinesProvider);
    final tileH = ((50 + 30 * buttonMaxLines) * textScale).clamp(70.0, 220.0);

    // In edit mode append the "Add new product" sentinel (-1).
    final displaySlots = (widget.editMode && widget.category.canCreateArticle)
        ? [...slots, -1]
        : slots;

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridColumns,
            mainAxisExtent: tileH,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: displaySlots.length,
          itemBuilder: (context, i) {
            final slotId = displaySlots[i];

            // "Add new product" tile
            if (slotId == -1) {
              return _AddTile(onTap: () => _openEdit(context, null));
            }

            // Empty slot
            if (slotId == null) {
              return widget.editMode
                  ? _EmptySlotTile(
                      onAccept: (from) {
                        setState(() => _draggingIndex = null);
                        _swap(from, i);
                      },
                    )
                  : const _InvisibleSlot();
            }

            // Product slot
            final product = productMap[slotId];
            if (product == null) return const SizedBox.shrink();

            if (widget.editMode) {
              return _DraggableTile(
                index: i,
                product: product,
                maxLines: buttonMaxLines,
                color: widget.prefs.getProductColor(product.id),
                dragging: _draggingIndex == i,
                onDragStarted: () => setState(() => _draggingIndex = i),
                onDragEnd: () => setState(() => _draggingIndex = null),
                onAccept: (from) {
                  setState(() => _draggingIndex = null);
                  _swap(from, i);
                },
                onTap: () => _openEdit(context, product),
              );
            }

            return _ProductTile(
              product: product,
              maxLines: buttonMaxLines,
              color: widget.prefs.getProductColor(product.id),
              onTap: () {
                if (!product.active) return;
                ref.read(cartProvider.notifier).addProduct(product);
              },
            );
          },
        ),

        // Edit-mode floating buttons: add / remove empty slot
        if (widget.editMode)
          Positioned(
            bottom: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'grid_remove_gap',
                  tooltip: 'Letzte Lücke entfernen',
                  onPressed: _removeLastEmptySlot,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'grid_add_gap',
                  tooltip: 'Leere Position einfügen',
                  onPressed: _addEmptySlot,
                  child: const Icon(Icons.space_bar),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------------

class _ProductTile extends StatelessWidget {
  final ProductModel product;
  final int maxLines;
  final Color? color;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.maxLines,
    required this.color,
    required this.onTap,
  });

  static Color _contrast(Color bg) {
    final l = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
    return l > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = !product.active;
    final isRefund = product.isRefund;

    final cardColor = inactive
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : color ??
            (isRefund
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.surfaceContainerHigh);

    final onCard =
        color != null && !inactive ? _contrast(color!) : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
      ),
    );
  }
}

/// A product tile that can be dragged (edit mode).
class _DraggableTile extends StatelessWidget {
  final int index;
  final ProductModel product;
  final int maxLines;
  final Color? color;
  final bool dragging;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnd;
  final ValueChanged<int> onAccept;
  final VoidCallback onTap;

  const _DraggableTile({
    required this.index,
    required this.product,
    required this.maxLines,
    required this.color,
    required this.dragging,
    required this.onDragStarted,
    required this.onDragEnd,
    required this.onAccept,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DragTarget<int>(
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnd(),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(
                width: 120,
                height: 70,
                child: Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Center(
                    child: Text(
                      product.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _editCard(context, theme, hovered),
          ),
          child: _editCard(context, theme, hovered),
        );
      },
    );
  }

  Widget _editCard(BuildContext context, ThemeData theme, bool hovered) {
    final inactive = !product.active;
    final isRefund = product.isRefund;

    final cardColor = hovered
        ? theme.colorScheme.primaryContainer
        : color ?? (isRefund
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHigh);

    Color? onCard;
    if (color != null && !inactive && !hovered) {
      final l = 0.299 * color!.r + 0.587 * color!.g + 0.114 * color!.b;
      onCard = l > 0.5 ? Colors.black87 : Colors.white;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hovered ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
                      : onCard ?? (isRefund
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
      ),
    );
  }
}

/// Empty slot in edit mode — acts as a drop target.
class _EmptySlotTile extends StatelessWidget {
  final ValueChanged<int> onAccept;

  const _EmptySlotTile({required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<int>(
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidates, _) {
        final hovered = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hovered
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: hovered ? 2 : 1,
            ),
            color: hovered
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
          child: hovered
              ? Center(
                  child: Icon(Icons.arrow_downward,
                      color: theme.colorScheme.primary, size: 20))
              : null,
        );
      },
    );
  }
}

/// Empty slot in normal mode — invisible but keeps grid alignment.
class _InvisibleSlot extends StatelessWidget {
  const _InvisibleSlot();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

