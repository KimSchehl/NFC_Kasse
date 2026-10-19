import 'package:flutter/material.dart';

import '../../models/product_model.dart';
import '../product_tile.dart';

/// Shown when tapping a base article that has options (e.g. "Currywurst" ->
/// "mit Brötchen"/"mit Pommes") on the normal POS grid. A small tile grid,
/// visually consistent with the main grid — reuses [ProductTile] as-is.
///
/// Only the options themselves are offered — the base article is never
/// directly bookable once it has options (e.g. "Steak" is always sold
/// "mit Brötchen" or "mit Pommes", never on its own), so it isn't a tile
/// here.
class VariantPickerDialog extends StatelessWidget {
  final ProductModel base;
  final List<ProductModel> options;

  const VariantPickerDialog({super.key, required this.base, required this.options});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(base.name),
      // Tiles grow with the name (long option names wrap instead of being
      // cut off); the tiles of one row share the taller height. Narrow
      // phones get one tile per row.
      content: SizedBox(
        width: 360,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final perRow = constraints.maxWidth >= 300 ? 2 : 1;
            return SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < options.length; i += perRow)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var j = i; j < i + perRow; j++) ...[
                              if (j > i) const SizedBox(width: 8),
                              Expanded(
                                child: j < options.length
                                    ? ConstrainedBox(
                                        constraints: const BoxConstraints(minHeight: 96),
                                        child: _tile(context, options[j]),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, ProductModel p) => ProductTile(
        product: p,
        maxLines: 4,
        color: null,
        fitContent: true,
        onTap: () {
          if (!p.active || p.isOutOfStock) return;
          Navigator.of(context).pop(p);
        },
      );
}
