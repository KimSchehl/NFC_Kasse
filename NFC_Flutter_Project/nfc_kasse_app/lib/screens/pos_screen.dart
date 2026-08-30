import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../providers/providers.dart';
import '../services/app_logger.dart';
import '../utils/layout_utils.dart';
import '../widgets/cart_panel.dart';
import '../widgets/customer_info_panel.dart';
import '../widgets/nfc_input_field.dart';
import '../widgets/pager_list_panel.dart';
import '../widgets/product_grid.dart';

/// Main cash-register screen. Delegates layout to [_WidePosLayout] (≥ 700 px)
/// or [_NarrowPosLayout] (< 700 px) based on available width.
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final user = ref.watch(authProvider).valueOrNull;
    final categories = user?.categories ?? [];

    // Auto-select the first category on first build. We must defer the state
    // write with addPostFrameCallback because calling ref.read inside build
    // is fine, but writing provider state synchronously during build triggers
    // a rebuild before the current one finishes.
    if (selectedCategory == null && categories.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedCategoryProvider.notifier).state = categories.first;
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        if (isWide) {
          return _WidePosLayout(category: selectedCategory);
        } else {
          return _NarrowPosLayout(category: selectedCategory);
        }
      },
    );
  }
}

/// Tablet / wide layout: product grid in the middle, cart on the right, and
/// (pager add-on only) an open-pager list on the left. The cart and pager
/// columns are both independently drag-resizable in width — see
/// [_VerticalDragHandle] and `clampPanelWidth`.
class _WidePosLayout extends ConsumerWidget {
  final CategoryModel? category;

  const _WidePosLayout({this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagerEnabled = ref.watch(authProvider).valueOrNull?.pagerEnabled ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rawCartWidth = ref.watch(cartWidthProvider);
        final rawPagerWidth = ref.watch(pagerWidthProvider);
        final totalHandleWidth =
            pagerEnabled ? _VerticalDragHandle.width * 2 : _VerticalDragHandle.width;

        final cartWidth = clampPanelWidth(
          rawCartWidth,
          constraints.maxWidth,
          (pagerEnabled ? rawPagerWidth : 0.0) + totalHandleWidth,
        );
        final pagerWidth = pagerEnabled
            ? clampPanelWidth(rawPagerWidth, constraints.maxWidth, cartWidth + totalHandleWidth)
            : 0.0;

        return Row(
          children: [
            if (pagerEnabled) ...[
              SizedBox(width: pagerWidth, child: const PagerListPanel()),
              _VerticalDragHandle(
                onDragUpdate: (dx) => ref.read(pagerWidthProvider.notifier).state = clampPanelWidth(
                  pagerWidth + dx,
                  constraints.maxWidth,
                  cartWidth + totalHandleWidth,
                ),
                onDragEnd: () => setPagerWidth(ref, ref.read(pagerWidthProvider)),
              ),
            ],

            // Middle: NFC input + product grid
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: NfcInputField(
                      onSubmit: (uid) => _handleNfc(uid, ref),
                    ),
                  ),
                  if (category != null)
                    Expanded(child: ProductGrid(category: category!))
                  else
                    const Expanded(
                      child: Center(child: Text('Bitte eine Kategorie auswählen')),
                    ),
                ],
              ),
            ),

            _VerticalDragHandle(
              onDragUpdate: (dx) => ref.read(cartWidthProvider.notifier).state = clampPanelWidth(
                cartWidth - dx,
                constraints.maxWidth,
                (pagerEnabled ? pagerWidth : 0.0) + totalHandleWidth,
              ),
              onDragEnd: () => setCartWidth(ref, ref.read(cartWidthProvider)),
            ),

            // Right: customer info + cart
            SizedBox(
              width: cartWidth,
              child: Column(
                children: [
                  const CustomerInfoPanel(),
                  const Divider(height: 1),
                  const Expanded(child: CartPanel()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Called when a UID is submitted (HID reader or native NFC).
  /// Fetches the customer's balance. The cart is intentionally NOT cleared here
  /// so staff can pre-fill the cart before scanning.
  Future<void> _handleNfc(String uid, WidgetRef ref) async {
    AppLogger.trace('NFC-UID gescannt: $uid', logger: 'ui.pos');
    try {
      final svc = ref.read(salesServiceProvider);
      final customer = await svc.getBalance(uid);
      // The user may have navigated away from PosScreen while this request
      // was in flight (e.g. a late BLE scan response) - ref is invalid then.
      if (!ref.context.mounted) return;
      ref.read(customerProvider.notifier).state = customer;
    } catch (e) {
      if (!ref.context.mounted) return;
      AppLogger.trace('NFC-UID nicht gefunden/Fehler: $uid', logger: 'ui.pos');
      // Customer not found or network error — clear customer so the UI shows
      // the "Bitte NFC-Chip scannen" placeholder.
      ref.read(customerProvider.notifier).state = null;
    }
  }
}

/// Phone layout: product grid on top half, cart always visible on bottom half
class _NarrowPosLayout extends ConsumerStatefulWidget {
  final CategoryModel? category;

  const _NarrowPosLayout({this.category});

  @override
  ConsumerState<_NarrowPosLayout> createState() => _NarrowPosLayoutState();
}

class _NarrowPosLayoutState extends ConsumerState<_NarrowPosLayout> {
  // Fraction of the available height given to the cart panel (0.15 – 0.80).
  double _cartRatio = 0.45;

  static const _handleHeight = 32.0;

  Future<void> _handleNfc(String uid) async {
    AppLogger.trace('NFC-UID gescannt: $uid', logger: 'ui.pos');
    try {
      final svc = ref.read(salesServiceProvider);
      final customer = await svc.getBalance(uid);
      if (!mounted) return;
      ref.read(customerProvider.notifier).state = customer;
    } catch (_) {
      if (!mounted) return;
      AppLogger.trace('NFC-UID nicht gefunden/Fehler: $uid', logger: 'ui.pos');
      ref.read(customerProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        final cartH = ((available - _handleHeight) * _cartRatio)
            .clamp(80.0, available - 120.0);
        final topH = available - _handleHeight - cartH;

        return Column(
          children: [
            // Top: NFC input + product grid
            SizedBox(
              height: topH,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: [
                        Expanded(child: NfcInputField(onSubmit: _handleNfc)),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: const CustomerInfoPanel(),
                        ),
                      ],
                    ),
                  ),
                  if (widget.category != null)
                    Expanded(child: ProductGrid(category: widget.category!))
                  else
                    const Expanded(
                      child: Center(child: Text('Bitte eine Kategorie auswählen')),
                    ),
                ],
              ),
            ),

            // Draggable divider — also shows the "Warenkorb" label
            _DragHandle(
              label: 'Warenkorb',
              onDrag: (dy) => setState(() {
                _cartRatio = (_cartRatio - dy / (available - _handleHeight))
                    .clamp(0.15, 0.80);
              }),
            ),

            // Bottom: cart (header hidden — label lives in the drag handle)
            SizedBox(
              height: cartH,
              child: const CartPanel(showHeader: false),
            ),
          ],
        );
      },
    );
  }
}

class _DragHandle extends StatelessWidget {
  final void Function(double dy) onDrag;
  final String? label;

  const _DragHandle({required this.onDrag, this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
      child: Container(
        height: _NarrowPosLayoutState._handleHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Row(
          children: [
            if (label != null)
              Text(
                label!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Spacer(),
            Icon(Icons.drag_handle, size: 20, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Horizontal counterpart of [_DragHandle] — resizes a side panel's width
/// instead of a bottom panel's height. Used twice in [_WidePosLayout]: once
/// between the pager list and the grid, once between the grid and the cart.
/// No label (unlike [_DragHandle]) — both side panels already show their own
/// header ("Pager" / "Warenkorb").
class _VerticalDragHandle extends StatelessWidget {
  final void Function(double dx) onDragUpdate;
  final VoidCallback onDragEnd;

  const _VerticalDragHandle({required this.onDragUpdate, required this.onDragEnd});

  static const width = 20.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDragUpdate(d.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd(),
      child: Container(
        width: width,
        color: theme.colorScheme.surfaceContainerHigh,
        child: Center(
          child: RotatedBox(
            quarterTurns: 1,
            child: Icon(Icons.drag_handle, size: 20, color: theme.colorScheme.outline),
          ),
        ),
      ),
    );
  }
}
