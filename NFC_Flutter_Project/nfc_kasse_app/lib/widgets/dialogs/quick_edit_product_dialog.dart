import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/app_logger.dart';
import '../../utils/formatters.dart';
import '../product_color_picker.dart';

/// Quick-edit popup opened by tapping a tile in the POS grid's
/// Bearbeitungsmodus — deliberately narrow: only color (a client-local
/// preference, no permission needed) and current stock quantity (a fast
/// recount/restock action). Full article editing (name, price, points,
/// pager, category/options, delete) lives on the article admin screen via
/// the full `EditProductDialog` — floor staff who can't touch prices
/// shouldn't be creating or reconfiguring articles here either.
class QuickEditProductDialog extends ConsumerStatefulWidget {
  final ProductModel product;
  final bool canEditStock;

  const QuickEditProductDialog({
    super.key,
    required this.product,
    required this.canEditStock,
  });

  @override
  ConsumerState<QuickEditProductDialog> createState() => _QuickEditProductDialogState();
}

class _QuickEditProductDialogState extends ConsumerState<QuickEditProductDialog> {
  late final TextEditingController _stock;
  Color? _color;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _color = ref.read(userPrefsProvider).getProductColor(widget.product.id);
    _stock = TextEditingController(text: widget.product.stock?.toString() ?? '');
  }

  @override
  void dispose() {
    _stock.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    AppLogger.trace('Schnell-Bearbeiten gespeichert: ${widget.product.name}', logger: 'ui.pos');

    int? stockVal;
    if (widget.canEditStock) {
      final stockText = _stock.text.trim();
      if (stockText.isNotEmpty) {
        stockVal = int.tryParse(stockText);
        if (stockVal == null || stockVal < 0) {
          setState(() => _error = 'Ungültiger Bestand (leer lassen für unbegrenzt, oder eine positive Zahl)');
          return;
        }
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.canEditStock) {
        await ref.read(productServiceProvider).updateProduct(widget.product.id, stock: stockVal);
      }
      ref.read(userPrefsProvider.notifier).setProductColor(widget.product.id, _color);
      if (!mounted) return;
      ref.read(productsRefreshProvider.notifier).state++;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = formatApiError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.product.name),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Button-Farbe', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              ProductColorPicker(
                selected: _color,
                onChanged: (c) => setState(() => _color = c),
              ),
              if (widget.canEditStock) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _stock,
                  decoration: const InputDecoration(
                    labelText: 'Bestand (leer = unbegrenzt)',
                    helperText: 'Wird bei jeder Buchung automatisch reduziert',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
