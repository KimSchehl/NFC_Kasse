import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../product_color_picker.dart';

/// Dialog for creating a new product or editing an existing one.
///
/// Pass [product] = null to create. [categoryId] is always required.
/// [canDelete] / [canDeactivate] gate the delete button and active toggle.
///
/// Button colors are now per-user preferences (long-press a tile on the POS
/// screen to set a color). This dialog handles name, price, and flags only.
class EditProductDialog extends ConsumerStatefulWidget {
  final ProductModel? product;
  final int categoryId;
  final bool canEditDetails;
  final bool canDelete;
  final bool canDeactivate;

  const EditProductDialog({
    super.key,
    this.product,
    required this.categoryId,
    this.canEditDetails = true,
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
  bool _isTopup = false;
  bool _isPayout = false;
  bool _excludeFromStats = false;
  Color? _color;
  bool _loading = false;
  String? _error;

  bool get isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _color = ref.read(userPrefsProvider).getProductColor(p.id);
    }
    _isTopup = p != null && p.price < 0 && p.excludeFromStats && !p.isPayout;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(
      text: p != null ? (_isTopup ? p.price.abs() : p.price).toStringAsFixed(2) : '',
    );
    _active = p?.active ?? true;
    _isPayout = p?.isPayout ?? false;
    _excludeFromStats = p?.excludeFromStats ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // No edit rights — only save the color preference.
    if (!widget.canEditDetails) {
      if (!isNew) {
        ref.read(userPrefsProvider.notifier).setProductColor(widget.product!.id, _color);
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    final name = _name.text.trim();
    final priceText = _price.text.trim().replaceAll(',', '.');
    final price = double.tryParse(priceText);

    if (name.isEmpty) {
      setState(() => _error = 'Name darf nicht leer sein');
      return;
    }
    if (price == null || (_isTopup && price <= 0)) {
      setState(() => _error = _isTopup
          ? 'Ungültiger Betrag (Beispiel: 20.00)'
          : 'Ungültiger Preis (Beispiel: 3.50 oder -2.00)');
      return;
    }

    final savedPrice = _isTopup ? -price.abs() : price;
    final savedExcludeFromStats = _isTopup ? true : _excludeFromStats;
    final savedIsPayout = _isTopup ? false : _isPayout;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = ref.read(productServiceProvider);
      if (isNew) {
        await svc.createProduct(
          name: name,
          price: savedPrice,
          categoryId: widget.categoryId,
          isPayout: savedIsPayout,
          excludeFromStats: savedExcludeFromStats,
        );
      } else {
        await svc.updateProduct(
          widget.product!.id,
          name: name,
          price: savedPrice,
          isPayout: savedIsPayout,
          excludeFromStats: savedExcludeFromStats,
        );
        if (widget.product!.active != _active && widget.canDeactivate) {
          await svc.setActive(widget.product!.id, _active);
        }
      }
      if (!isNew) {
        ref.read(userPrefsProvider.notifier).setProductColor(widget.product!.id, _color);
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
                enabled: widget.canEditDetails,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: widget.canEditDetails,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                enabled: widget.canEditDetails,
                decoration: InputDecoration(
                  labelText: _isTopup ? 'Auflade-Betrag (€)' : 'Preis (€)',
                  helperText: _isTopup
                      ? 'Positiver Betrag, der dem Guthaben gutgeschrieben wird'
                      : 'Negativ für Rückgabe/Aufladen, z.B. -2.00',
                ),
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                  signed: !_isTopup,
                ),
              ),
              if (widget.canEditDetails) ...[
              const SizedBox(height: 4),
              if (!isNew && widget.canDeactivate)
                CheckboxListTile(
                  title: const Text('Aktiv (buchbar)'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v ?? _active),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              CheckboxListTile(
                title: const Text('Guthaben Aufladung'),
                subtitle: const Text('Guthaben wird um den Betrag erhöht'),
                value: _isTopup,
                onChanged: (v) {
                  final isTopup = v ?? _isTopup;
                  setState(() {
                    _isTopup = isTopup;
                    if (isTopup) {
                      _isPayout = false;
                      _excludeFromStats = true;
                      final current = double.tryParse(
                          _price.text.trim().replaceAll(',', '.'));
                      if (current != null && current < 0) {
                        _price.text = current.abs().toStringAsFixed(2);
                      }
                    }
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (!_isTopup) ...[
                CheckboxListTile(
                  title: const Text('Auszahlungs-Artikel'),
                  subtitle: const Text('Buchung zahlt Gesamtguthaben aus'),
                  value: _isPayout,
                  onChanged: (v) => setState(() => _isPayout = v ?? _isPayout),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: const Text('Von Statistik ausschließen'),
                  subtitle: const Text('Nicht in Umsatzauswertung'),
                  value: _excludeFromStats,
                  onChanged: (v) =>
                      setState(() => _excludeFromStats = v ?? _excludeFromStats),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              ], // end canEditDetails
              if (!isNew) ...[
                const SizedBox(height: 12),
                Text('Button-Farbe', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                ProductColorPicker(
                  selected: _color,
                  onChanged: (c) => setState(() => _color = c),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
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
