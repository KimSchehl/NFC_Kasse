import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/product_model.dart';
import '../../providers/providers.dart';

/// Dialog for creating a new product or editing an existing one.
///
/// Pass [product] = null to create. [categoryId] is always required.
/// [canDelete] / [canDeactivate] gate the delete button and active toggle.

// Predefined tile color palette. null = no custom color → tile uses theme default.
const List<Color?> _palette = [
  null,
  Color(0xFFA5D6A7), // light green
  Color(0xFF81C784), // green
  Color(0xFF80DEEA), // cyan
  Color(0xFFFFF176), // yellow
  Color(0xFFFFCC80), // orange
  Color(0xFFEF9A9A), // light red
  Color(0xFFF48FB1), // pink
  Color(0xFFCE93D8), // light purple
  Color(0xFFBA68C8), // purple
  Color(0xFFBCAAA4), // brown
  Color(0xFFB0BEC5), // blue-grey
];

class EditProductDialog extends ConsumerStatefulWidget {
  /// Pass null to create a new product in [categoryId]
  final ProductModel? product;
  final int categoryId;
  final bool canDelete;
  final bool canDeactivate;

  const EditProductDialog({
    super.key,
    this.product,
    required this.categoryId,
    this.canDelete = false,
    this.canDeactivate = false,
  });

  @override
  ConsumerState<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends ConsumerState<EditProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  bool _active = true;
  bool _isPayout = false;
  Color? _color;
  bool _loading = false;
  String? _error;

  bool get isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _price = TextEditingController(
      text: widget.product != null ? widget.product!.price.toStringAsFixed(2) : '',
    );
    _active = widget.product?.active ?? true;
    _isPayout = widget.product?.isPayout ?? false;
    _color = widget.product?.color;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final priceText = _price.text.trim().replaceAll(',', '.');
    final price = double.tryParse(priceText);

    if (name.isEmpty) {
      setState(() => _error = 'Name darf nicht leer sein');
      return;
    }
    if (price == null) {
      setState(() => _error = 'Ungültiger Preis (Beispiel: 3.50 oder -2.00)');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = ref.read(productServiceProvider);
      final colorHex = _colorToHex(_color);
      if (isNew) {
        await svc.createProduct(
          name: name,
          price: price,
          categoryId: widget.categoryId,
          color: colorHex,
          isPayout: _isPayout,
        );
      } else {
        // Always send sendColor=true when editing so the user can explicitly
        // clear a color by selecting the "no color" swatch (sends null).
        await svc.updateProduct(
          widget.product!.id,
          name: name,
          price: price,
          sendColor: true,
          color: colorHex,
          isPayout: _isPayout,
        );
        if (widget.product!.active != _active && widget.canDeactivate) {
          await svc.setActive(widget.product!.id, _active);
        }
      }
      ref.read(productsRefreshProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Artikel löschen?'),
        content: Text('${widget.product!.name} endgültig löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(productServiceProvider).deleteProduct(widget.product!.id);
      ref.read(productsRefreshProvider.notifier).state++;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  static String? _colorToHex(Color? color) {
    if (color == null) return null;
    return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isNew ? 'Neuer Artikel' : 'Artikel bearbeiten'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              decoration: const InputDecoration(
                labelText: 'Preis (€)',
                helperText: 'Negativ für Rückgabe/Aufladen, z.B. -2.00',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            ),
            const SizedBox(height: 16),
            Text('Farbe', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            _ColorPicker(
              selected: _color,
              onChanged: (c) => setState(() => _color = c),
            ),
            if (!isNew && widget.canDeactivate) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                title: const Text('Aktiv (buchbar)'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('Auszahlungs-Artikel'),
              subtitle: const Text('Buchung zahlt Gesamtguthaben aus'),
              value: _isPayout,
              onChanged: (v) => setState(() => _isPayout = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
          ),   // Column
        ),     // SingleChildScrollView
      ),       // SizedBox
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (!isNew && widget.canDelete)
          TextButton(
            onPressed: _loading ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final Color? selected;
  final ValueChanged<Color?> onChanged;

  const _ColorPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _palette.map((color) => _Swatch(
            color: color,
            isSelected: selected == color,
            onTap: () => onChanged(color),
          )).toList(),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color? color;
  final bool isSelected;
  final VoidCallback onTap;

  const _Swatch({required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNone = color == null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isNone ? theme.colorScheme.surfaceContainerHigh : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isNone
            ? Icon(Icons.block, size: 18, color: theme.colorScheme.onSurfaceVariant)
            : isSelected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: _contrastColor(color!),
                  )
                : null,
      ),
    );
  }

  static Color _contrastColor(Color bg) {
    // Simple luminance check: dark background → white icon, light → dark icon
    final luminance = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b);
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }
}
