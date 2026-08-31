import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/product_model.dart';
import '../utils/formatters.dart';

/// Picks black or white text for readability on top of [bg], based on its
/// perceived luminance. Shared by [ProductTile] and `product_grid.dart`'s
/// `_DraggableTile`, which render the same tile content in two places
/// (normal grid vs. edit-mode drag source) and must stay visually consistent.
Color contrastColor(Color bg) {
  final l = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b;
  return l > 0.5 ? Colors.black87 : Colors.white;
}

// ---------------------------------------------------------------------------
// Sold-out hazard-stripe frame — shared between ProductTile and
// product_grid.dart's `_DraggableTile._editCard`, both of which otherwise
// render independently.
// ---------------------------------------------------------------------------

/// Wraps [child] with a diagonal red/white hazard-stripe border frame
/// (like warning tape) around its edge, leaving [child] itself untouched
/// and fully visible in the center. Used to flag sold-out articles more
/// prominently than the plain greyed-out/"Ausverkauft" label alone.
///
/// Implemented as a full-size striped layer *behind* an inset copy of
/// [child] (rather than clipping a single striped painter down to a
/// border-shaped region via `Path.combine`) because Flutter Web's canvas
/// backend does not reliably support `Path.combine`/`clipPath` there — it
/// silently painted the stripes across the whole tile instead of just the
/// border on web, while rendering correctly on Android. Plain layering only
/// needs a single rounded-rect clip, which is supported everywhere.
class SoldOutFrame extends StatelessWidget {
  final Widget child;

  const SoldOutFrame({super.key, required this.child});

  static const _frameThickness = 8.0;
  static const _borderRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_borderRadius),
            child: const CustomPaint(painter: _HazardStripePainter()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(_frameThickness),
          child: child,
        ),
      ],
    );
  }
}

class _HazardStripePainter extends CustomPainter {
  static const _stripeWidth = 7.0;

  const _HazardStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Rotate the canvas 45° around the tile's center, then paint plain
    // vertical bars spanning well beyond the (now-diagonal) visible bounds
    // — simpler and more robust than computing rotated stripe geometry by hand.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(math.pi / 4);
    final half = size.width + size.height;
    final stripePaint = Paint()..color = const Color(0xFFE53935);
    for (double x = -half; x < half; x += _stripeWidth * 2) {
      canvas.drawRect(Rect.fromLTWH(x, -half, _stripeWidth, half * 2), stripePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HazardStripePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------

/// A single POS grid button — shared by the normal grid and the mini
/// variant-picker grid (`variant_picker_dialog.dart`).
class ProductTile extends StatelessWidget {
  final ProductModel product;
  final int maxLines;
  final Color? color;
  final VoidCallback onTap;

  /// True for a base article that has options — its own price is never
  /// actually charged (an option is always picked instead), so showing it
  /// would be misleading. The tile shows just the name in that case.
  final bool hidePrice;

  const ProductTile({
    super.key,
    required this.product,
    required this.maxLines,
    required this.color,
    required this.onTap,
    this.hidePrice = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = !product.active;
    final outOfStock = product.isOutOfStock;
    final greyedOut = inactive || outOfStock;
    final showFrame = outOfStock && !inactive;
    final isRefund = product.isRefund;

    // The plain "Inaktiv" tile blends its 50%-alpha grey against the
    // ordinary grid background behind it. A sold-out tile instead sits on
    // top of SoldOutFrame's striped layer, so it needs a fully opaque
    // background here — otherwise the stripes bleed through the text.
    final cardColor = inactive
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : showFrame
            ? theme.colorScheme.surfaceContainerHighest
            : color ??
                (isRefund
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.surfaceContainerHigh);

    final onCard =
        color != null && !greyedOut ? contrastColor(color!) : null;

    final card = Card(
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
                      color: greyedOut
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : onCard,
                    ),
                  ),
                ),
              ),
              if (!hidePrice)
                Text(
                  formatPrice(product.price),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: greyedOut
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                        : onCard ??
                            (isRefund
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

    // Sold-out (but not deliberately deactivated) gets the hazard-stripe
    // frame instead of just the plain grey/"Ausverkauft" treatment above.
    return showFrame ? SoldOutFrame(child: card) : card;
  }
}
