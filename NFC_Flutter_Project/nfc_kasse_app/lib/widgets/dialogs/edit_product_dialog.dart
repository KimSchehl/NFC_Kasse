import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/app_logger.dart';
import '../../utils/formatters.dart';
import '../product_color_picker.dart';

/// Dialog for creating a new product or editing an existing one. Opened
/// from the article admin screen (`article_admin_screen.dart`) — the POS
/// grid's own quick-edit popup uses the narrower `QuickEditProductDialog`
/// instead.
///
/// Pass [product] = null to create. [categoryId] is always required.
/// [canDelete] / [canDeactivate] gate the delete button and active toggle;
/// [canCreateArticle] additionally gates the "Option hinzufügen" action
/// (adding an option is creating a new article, same server-side
/// permission as the top-level "Neuer Artikel" action).
///
/// [allCategoryProducts] must include every product in [categoryId]
/// (including inactive ones and existing options) — used to seed the
/// options sub-editor with [product]'s current options, if any.
///
/// Button colors are per-user preferences (long-press a tile on the POS
/// screen to set a color), unrelated to any of the above permissions.
class EditProductDialog extends ConsumerStatefulWidget {
  final ProductModel? product;
  final int categoryId;
  final List<ProductModel> allCategoryProducts;
  final bool canEditDetails;
  final bool canCreateArticle;
  final bool canDelete;
  final bool canDeactivate;

  const EditProductDialog({
    super.key,
    this.product,
    required this.categoryId,
    this.allCategoryProducts = const [],
    this.canEditDetails = true,
    this.canCreateArticle = false,
    this.canDelete = false,
    this.canDeactivate = false,
  });

  @override
  ConsumerState<EditProductDialog> createState() => _EditProductDialogState();
}

/// One row in the options sub-editor. `id == null` means it isn't saved
/// yet — created on next save rather than updated.
class _OptionDraft {
  final int? id;
  final TextEditingController suffixCtrl;
  final TextEditingController priceCtrl;

  _OptionDraft({this.id, String suffix = '', String price = ''})
      : suffixCtrl = TextEditingController(text: suffix),
        priceCtrl = TextEditingController(text: price);

  void dispose() {
    suffixCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _EditProductDialogState extends ConsumerState<EditProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _points;
  late final TextEditingController _stock;
  bool _active = true;
  bool _isTopup = false;
  bool _isPayout = false;
  bool _excludeFromStats = false;
  bool _requiresPager = false;
  Color? _color;
  bool _loading = false;
  String? _error;
  List<_OptionDraft> _options = [];
  final List<int> _deletedOptionIds = [];

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
    _points = TextEditingController(text: (p?.points ?? 0).toString());
    _stock = TextEditingController(text: p?.stock?.toString() ?? '');
    _active = p?.active ?? true;
    _isPayout = p?.isPayout ?? false;
    _excludeFromStats = p?.excludeFromStats ?? false;
    _requiresPager = p?.requiresPager ?? false;

    if (p != null) {
      // Options store their full composed name ("Currywurst mit Pommes") —
      // strip the base's own name back off for display, falling back to the
      // raw name if it doesn't start with the expected prefix (e.g. the
      // base was renamed after the option was created).
      final prefix = '${p.name} ';
      _options = widget.allCategoryProducts
          .where((o) => o.groupId == p.id)
          .map((o) => _OptionDraft(
                id: o.id,
                suffix: o.name.startsWith(prefix) ? o.name.substring(prefix.length) : o.name,
                price: o.price.toStringAsFixed(2),
              ))
          .toList();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _points.dispose();
    _stock.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    AppLogger.trace(
      '${isNew ? "Artikel erstellen" : "Artikel speichern"} geklickt: ${_name.text.trim()}',
      logger: 'ui.pos',
    );
    // No edit rights — only save the color preference.
    if (!widget.canEditDetails) {
      if (!isNew) {
        ref.read(userPrefsProvider.notifier).setProductColor(widget.product!.id, _color);
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    final name = _name.text.trim();
    final pointsVal = int.tryParse(_points.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Name darf nicht leer sein');
      return;
    }

    // Once the article has options, its own price field is hidden (see
    // build()) and never actually charged — an option is always booked
    // instead — so it doesn't need a real value here. Matters for a brand
    // new article in particular: _price starts out empty, and previously
    // this validation blocked saving until a throwaway price was entered.
    double savedPrice;
    if (_options.isNotEmpty) {
      savedPrice = 0.0;
    } else {
      final priceText = _price.text.trim().replaceAll(',', '.');
      final price = double.tryParse(priceText);
      if (price == null || (_isTopup && price <= 0)) {
        setState(() => _error = _isTopup
            ? 'Ungültiger Betrag (Beispiel: 20.00)'
            : 'Ungültiger Preis (Beispiel: 3.50 oder -2.00)');
        return;
      }
      savedPrice = _isTopup ? -price.abs() : price;
    }
    if (pointsVal == null) {
      setState(() => _error = 'Ungültige Punkte (ganze Zahl, z.B. 5 oder -10)');
      return;
    }

    final savedExcludeFromStats = _isTopup ? true : _excludeFromStats;
    final savedIsPayout = _isTopup ? false : _isPayout;
    // Same reasoning as stock below — Aufladen/Auszahlungs-Artikel can't
    // sensibly need a pager either.
    final savedRequiresPager = (_isTopup || savedIsPayout) ? false : _requiresPager;

    // Aufladen/Auszahlungs-Artikel represent no physical inventory — the
    // stock field is hidden for them (see build()), so force it to
    // "untracked" here too rather than trusting whatever the (hidden) text
    // field still holds from before the checkbox was toggled.
    int? stockVal;
    if (!_isTopup && !savedIsPayout) {
      final stockText = _stock.text.trim();
      if (stockText.isNotEmpty) {
        stockVal = int.tryParse(stockText);
        if (stockVal == null || stockVal < 0) {
          setState(() => _error = 'Ungültiger Bestand (leer lassen für unbegrenzt, oder eine positive Zahl)');
          return;
        }
      }
    }

    // Options are hidden in the UI (and thus never touched by the user) for
    // payout articles — see build() — so skip validating/syncing them here
    // too rather than silently dropping or reinterpreting stale draft rows.
    final parsedOptions = <({int? id, String suffix, double price})>[];
    if (!savedIsPayout) {
      for (final o in _options) {
        final suffix = o.suffixCtrl.text.trim();
        if (suffix.isEmpty) {
          setState(() => _error = 'Options-Zusatztext darf nicht leer sein');
          return;
        }
        final optPrice = double.tryParse(o.priceCtrl.text.trim().replaceAll(',', '.'));
        if (optPrice == null) {
          setState(() => _error = 'Ungültiger Options-Preis bei "$suffix"');
          return;
        }
        parsedOptions.add((id: o.id, suffix: suffix, price: optPrice));
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = ref.read(productServiceProvider);
      late final int baseId;
      if (isNew) {
        final created = await svc.createProduct(
          name: name,
          price: savedPrice,
          categoryId: widget.categoryId,
          isPayout: savedIsPayout,
          excludeFromStats: savedExcludeFromStats,
          points: pointsVal,
          stock: stockVal,
          requiresPager: savedRequiresPager,
        );
        baseId = created.id;
      } else {
        await svc.updateProduct(
          widget.product!.id,
          name: name,
          price: savedPrice,
          isPayout: savedIsPayout,
          excludeFromStats: savedExcludeFromStats,
          points: pointsVal,
          stock: stockVal,
          requiresPager: savedRequiresPager,
        );
        if (widget.product!.active != _active && widget.canDeactivate) {
          await svc.setActive(widget.product!.id, _active);
        }
        baseId = widget.product!.id;
      }

      if (!savedIsPayout) {
        // Composed once here and stored as a normal product.name — see the
        // class doc comment for why (many read sites, one write site).
        for (final opt in parsedOptions) {
          final optionName = '$name ${opt.suffix}';
          if (opt.id == null) {
            await svc.createProduct(
              name: optionName,
              price: opt.price,
              categoryId: widget.categoryId,
              groupId: baseId,
            );
          } else {
            await svc.updateProduct(opt.id!, name: optionName, price: opt.price);
          }
        }
        for (final deletedId in _deletedOptionIds) {
          await svc.deleteProduct(deletedId);
        }
      }

      if (!mounted) return;
      if (!isNew) {
        ref.read(userPrefsProvider.notifier).setProductColor(widget.product!.id, _color);
      }
      ref.read(productsRefreshProvider.notifier).state++;
      ref.read(adminCategoriesRefreshProvider.notifier).state++;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = formatApiError(e);
      });
    }
  }

  Future<void> _delete() async {
    AppLogger.trace('Löschen-Dialog geöffnet: ${widget.product!.name}', logger: 'ui.pos');
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
    AppLogger.trace('Löschen bestätigt: ${widget.product!.name}', logger: 'ui.pos');

    setState(() => _loading = true);
    try {
      await ref.read(productServiceProvider).deleteProduct(widget.product!.id);
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
              // A base article with options is never booked directly (see
              // the options section below) — its own price would never
              // actually be charged, so showing an editable price field
              // here would be misleading. Each option carries its own price
              // instead.
              if (_options.isEmpty)
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
                )
              else
                Text(
                  'Preis wird pro Option unten festgelegt',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              if (ref.watch(authProvider).valueOrNull?.leaderboardEnabled ?? false) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _points,
                  enabled: widget.canEditDetails,
                  decoration: const InputDecoration(
                    labelText: 'Leaderboard-Punkte',
                    helperText: 'Punkte pro Buchung (negativ erlaubt, z.B. -10)',
                    prefixIcon: Icon(Icons.star_outline, size: 20),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                ),
              ],
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
                if (!_isPayout) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _stock,
                    enabled: widget.canEditDetails,
                    decoration: const InputDecoration(
                      labelText: 'Bestand (leer = unbegrenzt)',
                      helperText: 'Wird bei jeder Buchung automatisch reduziert',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (ref.watch(authProvider).valueOrNull?.pagerEnabled ?? false)
                    CheckboxListTile(
                      title: const Text('Pager erforderlich'),
                      subtitle: const Text('Kunde erhält beim Buchen einen Pager'),
                      value: _requiresPager,
                      onChanged: (v) => setState(() => _requiresPager = v ?? _requiresPager),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ],
              if (!_isPayout) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text('Optionen', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  'Varianten wie "mit Pommes" — teilen sich Bestand, Punkte und Pager mit diesem Artikel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final o in _options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: o.suffixCtrl,
                            enabled: widget.canEditDetails,
                            decoration: const InputDecoration(labelText: 'Zusatz', isDense: true),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: o.priceCtrl,
                            enabled: widget.canEditDetails,
                            decoration: const InputDecoration(labelText: 'Preis (€)', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          ),
                        ),
                        if (widget.canDelete)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Option entfernen',
                            onPressed: () => setState(() {
                              _options.remove(o);
                              if (o.id != null) _deletedOptionIds.add(o.id!);
                              o.dispose();
                            }),
                          ),
                      ],
                    ),
                  ),
                if (widget.canCreateArticle)
                  TextButton.icon(
                    onPressed: () => setState(() => _options.add(_OptionDraft())),
                    icon: const Icon(Icons.add),
                    label: const Text('Option hinzufügen'),
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
