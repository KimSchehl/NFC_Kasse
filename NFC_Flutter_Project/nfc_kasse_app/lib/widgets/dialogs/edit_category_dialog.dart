import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category_model.dart';
import '../../providers/providers.dart';

/// Dialog for renaming a category or (when [canDelete] is true) deleting it.
///
/// Deletion is a soft-delete on the server (`deleted=1`) — products and their
/// sale history are preserved. After save or delete, [categoriesRefreshProvider]
/// is incremented to trigger a category list reload.
class EditCategoryDialog extends ConsumerStatefulWidget {
  final CategoryModel category;
  final bool canDelete;

  const EditCategoryDialog({
    super.key,
    required this.category,
    this.canDelete = false,
  });

  @override
  ConsumerState<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends ConsumerState<EditCategoryDialog> {
  late final TextEditingController _name;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name darf nicht leer sein');
      return;
    }
    if (name == widget.category.name) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(productServiceProvider).updateCategory(widget.category.id, name);
      ref.read(categoriesRefreshProvider.notifier).state++;
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
        title: const Text('Kategorie löschen?'),
        content: Text(
          '"${widget.category.name}" und alle zugehörigen Artikel endgültig löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
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
      await ref.read(productServiceProvider).deleteCategory(widget.category.id);
      ref.read(categoriesRefreshProvider.notifier).state++;
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
      title: const Text('Kategorie bearbeiten'),
      content: SizedBox(
        width: 320,
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
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),     // Column
        ),       // SingleChildScrollView
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (widget.canDelete)
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
          ],
        ),
      ],
    );
  }
}
