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
      content: SizedBox(
        width: 360,
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.3,
          children: [
            for (final p in options)
              ProductTile(
                product: p,
                maxLines: 2,
                color: null,
                onTap: () {
                  if (!p.active || p.isOutOfStock) return;
                  Navigator.of(context).pop(p);
                },
              ),
          ],
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
}
