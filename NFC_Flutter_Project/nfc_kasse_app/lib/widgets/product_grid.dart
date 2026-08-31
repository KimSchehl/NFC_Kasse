import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../models/product_model.dart';
import '../models/user_preferences_model.dart';
import '../providers/providers.dart';
import '../services/app_logger.dart';
import '../utils/formatters.dart';
import 'dialogs/quick_edit_product_dialog.dart';
import 'dialogs/variant_picker_dialog.dart';
import 'product_tile.dart';

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

  /// Articles with their own grid tile — excludes options (an article
  /// pointed at by another via `groupId`), which only ever surface inside
  /// their base's variant picker, never as their own tile.
  List<ProductModel> get _topLevelProducts =>
      widget.products.where((p) => p.groupId == null).toList();

  /// The options belonging to [product] (empty if it's a plain article).
  List<ProductModel> _optionsOf(ProductModel product) =>
      widget.products.where((p) => p.groupId == product.id).toList();

  /// Builds the ordered slot list from saved layout + any new products appended.
  /// Deleted product IDs are removed; user-added null gaps are preserved.
  /// An article that became an option since the layout was last saved is
  /// filtered out here the same way a deleted one would be — no separate
  /// migration needed.
  List<int?> _buildSlots() {
    final topLevel = _topLevelProducts;
    final saved = widget.prefs.getLayout(widget.category.id, widget.profile);
    final existing = topLevel.map((p) => p.id).toSet();

    if (saved == null) {
      return topLevel.map((p) => p.id as int?).toList();
    }

    // Remove IDs of products that were deleted (or became options) since layout was saved.
    final valid = saved.where((id) => id == null || existing.contains(id)).toList();

    // Append products added after the layout was last saved.
    final inLayout = valid.whereType<int>().toSet();
    final appended = topLevel
        .where((p) => !inLayout.contains(p.id))
        .map((p) => p.id as int?);

    return [...valid, ...appended];
  }

  void _swap(int from, int to) {
    if (from == to) return;
    AppLogger.trace('Artikel-Layout: Position $from <-> $to getauscht', logger: 'ui.pos');
    final slots = _buildSlots();
    final tmp = slots[from];
    slots[from] = slots[to];
    slots[to] = tmp;
    ref.read(userPrefsProvider.notifier).setLayout(
          widget.category.id, widget.profile, slots);
  }

  void _addEmptySlot() {
    AppLogger.trace('Artikel-Layout: leere Position eingefügt', logger: 'ui.pos');
    ref.read(userPrefsProvider.notifier).setLayout(
          widget.category.id, widget.profile, [..._buildSlots(), null]);
  }

  void _removeLastEmptySlot() {
    final slots = _buildSlots();
    final idx = slots.lastIndexOf(null);
    if (idx < 0) return;
    AppLogger.trace('Artikel-Layout: leere Position entfernt', logger: 'ui.pos');
    slots.removeAt(idx);
    ref.read(userPrefsProvider.notifier).setLayout(
          widget.category.id, widget.profile, slots);
  }

  /// Opens the narrow quick-edit popup (color + current stock only) for an
  /// existing article — full editing (name, price, points, pager, options,
  /// delete, new-article creation) lives on the article admin screen now,
  /// reachable via the sidebar, not from here.
  Future<void> _openQuickEdit(BuildContext context, ProductModel product) async {
    AppLogger.trace('Schnell-Bearbeiten geöffnet: ${product.name}', logger: 'ui.pos');

    // Pull in any stock changes from sales made since the last sync poll
    // first, so the dialog never shows a stale (e.g. pre-sale) stock count
    // instead of the current remainder.
    ProductModel dialogProduct = product;
    await ref.read(productSyncProvider.notifier).checkForChanges();
    if (!mounted) return;
    final fresh = ref.read(productsProvider(widget.category.id)).valueOrNull;
    if (fresh != null) {
      for (final p in fresh) {
        if (p.id == product.id) {
          dialogProduct = p;
          break;
        }
      }
    }

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => QuickEditProductDialog(
        product: dialogProduct,
        canEditStock: widget.category.canEditArticle,
      ),
    );
  }

  /// Normal-mode tap: adds [product] directly, unless it has options (other
  /// articles pointing back at it via `groupId`), in which case a mini-grid
  /// picker opens first — e.g. tapping "Currywurst" offers "mit Pommes"/
  /// "mit Brötchen"; picking one adds *that* article, exactly as if it had
  /// been tapped directly.
  Future<void> _addOrPickVariant(BuildContext context, ProductModel product) async {
    if (!product.active || product.isOutOfStock) return;

    final options = _optionsOf(product);
    if (options.isEmpty) {
      AppLogger.trace('Artikel zu Warenkorb: ${product.name}', logger: 'ui.pos');
      ref.read(cartProvider.notifier).addProduct(product);
      return;
    }

    AppLogger.trace('Options-Popup geöffnet: ${product.name}', logger: 'ui.pos');
    final chosen = await showDialog<ProductModel>(
      context: context,
      builder: (_) => VariantPickerDialog(base: product, options: options),
    );
    if (chosen == null) return;
    AppLogger.trace('Artikel zu Warenkorb: ${chosen.name}', logger: 'ui.pos');
    ref.read(cartProvider.notifier).addProduct(chosen);
  }


  @override
  Widget build(BuildContext context) {
    final slots = _buildSlots();
    final productMap = {for (final p in widget.products) p.id: p};
    final gridColumns = ref.watch(gridColumnsProvider);
    final textScale = ref.watch(textScaleProvider);
    final buttonMaxLines = ref.watch(buttonMaxLinesProvider);
    final tileH = ((50 + 30 * buttonMaxLines) * textScale).clamp(70.0, 220.0);

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
          itemCount: slots.length,
          itemBuilder: (context, i) {
            final slotId = slots[i];

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
                hasOptions: _optionsOf(product).isNotEmpty,
                onDragStarted: () => setState(() => _draggingIndex = i),
                onDragEnd: () => setState(() => _draggingIndex = null),
                onAccept: (from) {
                  setState(() => _draggingIndex = null);
                  _swap(from, i);
                },
                onTap: () => _openQuickEdit(context, product),
              );
            }

            return ProductTile(
              product: product,
              maxLines: buttonMaxLines,
              color: widget.prefs.getProductColor(product.id),
              hidePrice: _optionsOf(product).isNotEmpty,
              onTap: () => _addOrPickVariant(context, product),
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
// ProductTile/SoldOutFrame live in product_tile.dart (shared with the
// variant-picker mini-grid) — only the edit-mode draggable tile stays here.

/// A product tile that can be dragged (edit mode).
class _DraggableTile extends StatelessWidget {
  final int index;
  final ProductModel product;
  final int maxLines;
  final Color? color;
  final bool dragging;
  final bool hasOptions;
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
    required this.hasOptions,
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
    final outOfStock = product.isOutOfStock;
    final greyedOut = inactive || outOfStock;
    final isRefund = product.isRefund;

    final cardColor = hovered
        ? theme.colorScheme.primaryContainer
        : color ?? (isRefund
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.surfaceContainerHigh);

    final onCard = (color != null && !greyedOut && !hovered) ? contrastColor(color!) : null;

    final card = Card(
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
                      color: greyedOut
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : onCard,
                    ),
                  ),
                ),
              ),
              if (!hasOptions)
                Text(
                  formatPrice(product.price),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: greyedOut
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                        : onCard ?? (isRefund
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.primary),
                  ),
                ),
              if (greyedOut)
                Text(
                  inactive ? 'Inaktiv' : 'Ausverkauft',
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

    return (outOfStock && !inactive) ? SoldOutFrame(child: card) : card;
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

