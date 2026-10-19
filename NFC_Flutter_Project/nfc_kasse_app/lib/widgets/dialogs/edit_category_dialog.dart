import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category_model.dart';
import '../../providers/providers.dart';
import '../../services/app_logger.dart';
import '../../utils/formatters.dart';

/// Dialog for renaming a category, switching it off for the running fest
/// (when [canDeactivate] is true) or (when [canDelete] is true) deleting it.
///
/// Categories belong to the Veranstalter. Switching one off only hides it in
/// this fest; it is switched back on in the Artikelverwaltung.
///
/// Deletion is a soft-delete on the server (`deleted=1`) — products and their
/// sale history are preserved. After save or delete, [categoriesRefreshProvider]
/// is incremented to trigger a category list reload.
class EditCategoryDialog extends ConsumerStatefulWidget {
  final CategoryModel category;
  final bool canDelete;
  final bool canDeactivate;

  const EditCategoryDialog({
    super.key,
    required this.category,
    this.canDelete = false,
    this.canDeactivate = false,
  });

  @override
  ConsumerState<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends ConsumerState<EditCategoryDialog> {
  late final TextEditingController _name;
  late bool _activeInEvent = widget.category.activeInEvent;
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
    final renamed = name != widget.category.name;
    final toggled = _activeInEvent != widget.category.activeInEvent;
    if (!renamed && !toggled) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(productServiceProvider);
      if (renamed) {
        AppLogger.trace('Kategorie umbenannt: ${widget.category.name} -> $name', logger: 'ui.sidebar');
        await service.updateCategory(widget.category.id, name);
      }
      if (toggled) {
        AppLogger.trace('Kategorie ${_activeInEvent ? 'eingeschaltet' : 'ausgeschaltet'}: $name',
            logger: 'ui.sidebar');
        await service.setCategoryInEvent(widget.category.id, _activeInEvent);
        if (!_activeInEvent && ref.read(selectedCategoryProvider)?.id == widget.category.id) {
          ref.read(selectedCategoryProvider.notifier).state = null;
        }
        // The till's category list comes from /me. Other devices pick the
        // change up on their next reload (fest switch, login, or a booking
        // the server rejects with event_changed).
        await ref.read(authProvider.notifier).refreshFromServer();
        ref.invalidate(productsProvider);
      }
      if (!mounted) return;
      ref.read(categoriesRefreshProvider.notifier).state++;
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
    AppLogger.trace('Kategorie-Löschen bestätigt: ${widget.category.name}', logger: 'ui.sidebar');

    setState(() => _loading = true);
    try {
      await ref.read(productServiceProvider).deleteCategory(widget.category.id);
      if (!mounted) return;
      ref.read(categoriesRefreshProvider.notifier).state++;
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
              if (widget.canDeactivate) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In diesem Fest anzeigen'),
                  subtitle: Text(_activeInEvent
                      ? 'Alle Kassen dieses Festes zeigen die Kategorie.'
                      : 'Ausgeblendet an allen Kassen dieses Festes. Wieder einschalten in der Artikelverwaltung.'),
                  value: _activeInEvent,
                  onChanged: _loading ? null : (v) => setState(() => _activeInEvent = v),
                ),
              ],
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
