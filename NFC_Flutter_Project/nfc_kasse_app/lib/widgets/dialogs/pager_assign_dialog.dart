import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/cart_item.dart';
import '../../providers/providers.dart';

/// Shown before booking a cart that contains at least one `requiresPager`
/// article. Purely local — no network call here, the chosen number (or
/// null for "Überspringen") is sent along with the booking request itself
/// by the caller.
///
/// Only two ways out: a pager number, or null (skip). No plain "cancel the
/// whole booking" path — that's what the OS back gesture / barrier would
/// normally offer, deliberately disabled here (`PopScope(canPop: false)`,
/// `barrierDismissible: false`) since the two buttons already cover every
/// case the feature describes.
class PagerAssignDialog extends ConsumerStatefulWidget {
  final List<CartItem> pagerItems;

  const PagerAssignDialog({super.key, required this.pagerItems});

  @override
  ConsumerState<PagerAssignDialog> createState() => _PagerAssignDialogState();
}

class _PagerAssignDialogState extends ConsumerState<PagerAssignDialog> {
  late final TextEditingController _number;
  String? _error;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController();
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  String get _itemSummary => widget.pagerItems
      .map((i) => i.quantity > 1 ? '${i.quantity}× ${i.product.name}' : i.product.name)
      .join(', ');

  void _confirm() {
    final parsed = int.tryParse(_number.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Ungültige Pager-Nummer (z. B. 3)');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final openNumbers = ref
        .watch(pagerListProvider)
        .valueOrNull
        ?.map((p) => p.pagerNumber)
        .toSet() ??
        {};
    final typed = int.tryParse(_number.text.trim());
    final duplicateHint =
        typed != null && openNumbers.contains(typed) ? 'Pager Nr. $typed ist bereits offen' : null;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Pager zuweisen'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_itemSummary, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _number,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Pager-Nummer',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  helperText: duplicateHint,
                  helperStyle: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Überspringen'),
          ),
          FilledButton(
            onPressed: _confirm,
            child: const Text('Pager zuweisen'),
          ),
        ],
      ),
    );
  }
}
