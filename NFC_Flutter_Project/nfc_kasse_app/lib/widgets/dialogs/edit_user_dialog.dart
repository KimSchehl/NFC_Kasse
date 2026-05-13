import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category_model.dart';
import '../../models/user_model.dart';
import '../../providers/providers.dart';

enum _CatFlag {
  book, storno5min, stornoUnlimited,
  createArticle, editArticle, deactivateArticle, deleteArticle,
}

class EditUserDialog extends ConsumerStatefulWidget {
  final UserListItem? user;
  const EditUserDialog({super.key, this.user});

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  late final TextEditingController _username;
  late final TextEditingController _displayName;
  late final TextEditingController _password;

  bool _loading = false;
  String? _error;

  Set<String> _selectedPerms = {};
  Map<int, CategoryModel> _catAccess = {};
  List<Map<String, dynamic>> _permTree = [];
  List<CategoryModel> _allCategories = [];

  bool get isNew => widget.user == null;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.user?.username ?? '');
    _displayName = TextEditingController(text: widget.user?.displayName ?? '');
    _password = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final svc = ref.read(usersServiceProvider);
    final permTree = await svc.getPermissionTree();
    final cats = await ref.read(productServiceProvider).getCategories();

    Map<int, CategoryModel> catAccess = {};
    Set<String> perms = {};

    if (!isNew) {
      try {
        final data = await svc.getUserPermissions(widget.user!.id);
        perms = Set<String>.from((data['permissions'] as List? ?? []).cast<String>());
        for (final c in (data['categories'] as List? ?? [])) {
          final cat = CategoryModel(
            id: c['category_id'] as int,
            name: c['category_name'] as String,
            sortOrder: 0,
            canBook: c['can_book'] as bool? ?? false,
            canStorno5min: c['can_storno_5min'] as bool? ?? false,
            canStornoUnlimited: c['can_storno_unlimited'] as bool? ?? false,
            canCreateArticle: c['can_create_article'] as bool? ?? false,
            canEditArticle: c['can_edit_article'] as bool? ?? false,
            canDeactivateArticle: c['can_deactivate_article'] as bool? ?? false,
            canDeleteArticle: c['can_delete_article'] as bool? ?? false,
          );
          catAccess[cat.id] = cat;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _permTree = permTree;
        _allCategories = cats;
        _selectedPerms = perms;
        _catAccess = catAccess;
      });
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final displayName = _displayName.text.trim();
    final password = _password.text;

    if (username.isEmpty) {
      setState(() => _error = 'Benutzername darf nicht leer sein');
      return;
    }
    if (isNew && password.isEmpty) {
      setState(() => _error = 'Passwort ist erforderlich');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final svc = ref.read(usersServiceProvider);
      int userId;
      if (isNew) {
        final created = await svc.createUser(
          username: username,
          password: password,
          displayName: displayName.isEmpty ? null : displayName,
        );
        userId = created.id;
      } else {
        await svc.updateUser(
          widget.user!.id,
          username: username,
          password: password.isEmpty ? null : password,
          displayName: displayName.isEmpty ? null : displayName,
        );
        userId = widget.user!.id;
      }

      await svc.setPermissions(userId, _selectedPerms.toList());
      await svc.setCategoryAccess(userId, _catAccess.values.toList());

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _updateCatAccess(int catId, CategoryModel? model) {
    setState(() {
      if (model == null) {
        _catAccess = Map.from(_catAccess)..remove(catId);
      } else {
        _catAccess = {..._catAccess, catId: model};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in _permTree) {
      final g = p['group'] as String;
      groups.putIfAbsent(g, () => []).add(p);
    }

    return AlertDialog(
      title: Text(isNew ? 'Neuer Benutzer' : 'Benutzer bearbeiten'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Basic fields ───────────────────────────────────────────
              TextField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Benutzername'),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'Anzeigename (optional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: isNew ? 'Passwort' : 'Neues Passwort (leer = unverändert)',
                ),
                obscureText: true,
              ),

              const SizedBox(height: 20),
              Text('Globale Berechtigungen', style: theme.textTheme.titleSmall),
              const Divider(),

              // ── Global permission groups ─────────────────────────────────
              ...groups.entries.map((entry) => _PermissionGroup(
                    groupName: entry.key,
                    nodes: entry.value,
                    selected: _selectedPerms,
                    onToggle: (id, val) => setState(() {
                      if (val) {
                        _selectedPerms = {..._selectedPerms, id};
                      } else {
                        _selectedPerms = _selectedPerms.where((p) => p != id).toSet();
                      }
                    }),
                    onToggleGroup: (ids, val) => setState(() {
                      if (val) {
                        _selectedPerms = {..._selectedPerms, ...ids};
                      } else {
                        _selectedPerms = _selectedPerms.where((p) => !ids.contains(p)).toSet();
                      }
                    }),
                  )),

              const SizedBox(height: 20),
              Text('Kategorien & Berechtigungen', style: theme.textTheme.titleSmall),
              const Divider(),

              // ── Per-category tree ────────────────────────────────────────
              if (_allCategories.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Keine Kategorien vorhanden',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ..._allCategories.map((cat) => _CategoryTreeTile(
                    category: cat,
                    access: _catAccess[cat.id],
                    onChanged: (model) => _updateCatAccess(cat.id, model),
                  )),

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

// ---------------------------------------------------------------------------
// Category tree tile
// ---------------------------------------------------------------------------

class _CategoryTreeTile extends StatelessWidget {
  final CategoryModel category;
  final CategoryModel? access;
  final void Function(CategoryModel?) onChanged;

  const _CategoryTreeTile({
    required this.category,
    required this.access,
    required this.onChanged,
  });

  bool get _hasAccess => access != null;

  static bool? _tri(List<bool> flags) {
    if (flags.every((f) => f)) return true;
    if (flags.every((f) => !f)) return false;
    return null;
  }

  // Storno is exclusive: treat any storno as a single logical slot.
  bool? get _bookingState => _hasAccess
      ? _tri([access!.canBook, access!.canStorno5min || access!.canStornoUnlimited])
      : false;

  bool? get _articleState => _hasAccess
      ? _tri([access!.canCreateArticle, access!.canEditArticle,
              access!.canDeactivateArticle, access!.canDeleteArticle])
      : false;

  bool? get _categoryState {
    if (!_hasAccess) return false;
    final b = _bookingState;
    final a = _articleState;
    if (b == true && a == true) return true;
    if (b == false && a == false) return false;
    return null;
  }

  CategoryModel _base() => access ?? CategoryModel(
        id: category.id, name: category.name, sortOrder: category.sortOrder);

  static CategoryModel _applyFlag(CategoryModel c, _CatFlag flag, bool v) =>
      CategoryModel(
        id: c.id, name: c.name, sortOrder: c.sortOrder,
        canBook:              flag == _CatFlag.book              ? v : c.canBook,
        canStorno5min:        flag == _CatFlag.storno5min        ? v : c.canStorno5min,
        canStornoUnlimited:   flag == _CatFlag.stornoUnlimited   ? v : c.canStornoUnlimited,
        canCreateArticle:     flag == _CatFlag.createArticle     ? v : c.canCreateArticle,
        canEditArticle:       flag == _CatFlag.editArticle       ? v : c.canEditArticle,
        canDeactivateArticle: flag == _CatFlag.deactivateArticle ? v : c.canDeactivateArticle,
        canDeleteArticle:     flag == _CatFlag.deleteArticle     ? v : c.canDeleteArticle,
      );

  void _toggleCategory() {
    if (_categoryState == true) {
      onChanged(null); // remove access
    } else if (!_hasAccess) {
      // grant full access
      onChanged(CategoryModel(
        id: category.id, name: category.name, sortOrder: category.sortOrder,
        canBook: true, canStorno5min: false, canStornoUnlimited: true,
        canCreateArticle: true, canEditArticle: true,
        canDeactivateArticle: true, canDeleteArticle: true,
      ));
    } else {
      // partial → check all
      onChanged(CategoryModel(
        id: category.id, name: category.name, sortOrder: category.sortOrder,
        canBook: true, canStorno5min: false, canStornoUnlimited: true,
        canCreateArticle: true, canEditArticle: true,
        canDeactivateArticle: true, canDeleteArticle: true,
      ));
    }
  }

  void _toggleBookingGroup() {
    final newVal = _bookingState != true;
    final a = _base();
    onChanged(CategoryModel(
      id: a.id, name: a.name, sortOrder: a.sortOrder,
      canBook: newVal,
      canStorno5min: newVal,   // default to 5 min when turning group on
      canStornoUnlimited: false,
      canCreateArticle: a.canCreateArticle, canEditArticle: a.canEditArticle,
      canDeactivateArticle: a.canDeactivateArticle, canDeleteArticle: a.canDeleteArticle,
    ));
  }

  void _setStornoEnabled(bool enabled) {
    final a = _base();
    onChanged(CategoryModel(
      id: a.id, name: a.name, sortOrder: a.sortOrder,
      canBook: a.canBook,
      canStorno5min: enabled,   // default to 5 min when enabling
      canStornoUnlimited: false,
      canCreateArticle: a.canCreateArticle, canEditArticle: a.canEditArticle,
      canDeactivateArticle: a.canDeactivateArticle, canDeleteArticle: a.canDeleteArticle,
    ));
  }

  void _setStornoUnlimited(bool unlimited) {
    final a = _base();
    onChanged(CategoryModel(
      id: a.id, name: a.name, sortOrder: a.sortOrder,
      canBook: a.canBook,
      canStorno5min: !unlimited,
      canStornoUnlimited: unlimited,
      canCreateArticle: a.canCreateArticle, canEditArticle: a.canEditArticle,
      canDeactivateArticle: a.canDeactivateArticle, canDeleteArticle: a.canDeleteArticle,
    ));
  }

  void _toggleArticleGroup() {
    final newVal = _articleState != true;
    final a = _base();
    onChanged(CategoryModel(
      id: a.id, name: a.name, sortOrder: a.sortOrder,
      canBook: a.canBook, canStorno5min: a.canStorno5min,
      canStornoUnlimited: a.canStornoUnlimited,
      canCreateArticle: newVal, canEditArticle: newVal,
      canDeactivateArticle: newVal, canDeleteArticle: newVal,
    ));
  }

  void _setLeaf(_CatFlag flag, bool val) =>
      onChanged(_applyFlag(_base(), flag, val));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Category root ───────────────────────────────────────────
          _CheckRow(
            value: _categoryState,
            tristate: true,
            label: category.name,
            bold: true,
            onChanged: (_) => _toggleCategory(),
          ),

          if (_hasAccess)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2, bottom: 4),
              child: _TreeBranch(lineColor: lineColor, children: [
                // ── Buchungen ────────────────────────────────────────────
                _CheckRow(
                  value: _bookingState,
                  tristate: true,
                  label: 'Buchungen',
                  bold: true,
                  onChanged: (_) => _toggleBookingGroup(),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: _TreeBranch(lineColor: lineColor, children: [
                    _CheckRow(value: access!.canBook, label: 'Buchen', onChanged: (v) => _setLeaf(_CatFlag.book, v ?? false)),
                    _StornoRow(
                      enabled: access!.canStorno5min || access!.canStornoUnlimited,
                      unlimited: access!.canStornoUnlimited,
                      onToggle: _setStornoEnabled,
                      onTypeChange: _setStornoUnlimited,
                    ),
                  ]),
                ),

                // ── Positionen ───────────────────────────────────────────
                _CheckRow(
                  value: _articleState,
                  tristate: true,
                  label: 'Positionen',
                  bold: true,
                  onChanged: (_) => _toggleArticleGroup(),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 2),
                  child: _TreeBranch(lineColor: lineColor, children: [
                    _CheckRow(value: access!.canCreateArticle,     label: 'Erstellen',    onChanged: (v) => _setLeaf(_CatFlag.createArticle,     v ?? false)),
                    _CheckRow(value: access!.canEditArticle,       label: 'Bearbeiten',   onChanged: (v) => _setLeaf(_CatFlag.editArticle,       v ?? false)),
                    _CheckRow(value: access!.canDeactivateArticle, label: 'Deaktivieren', onChanged: (v) => _setLeaf(_CatFlag.deactivateArticle, v ?? false)),
                    _CheckRow(value: access!.canDeleteArticle,     label: 'Löschen',      onChanged: (v) => _setLeaf(_CatFlag.deleteArticle,     v ?? false)),
                  ]),
                ),
              ]),
            ),

          Divider(height: 8, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared tree widgets
// ---------------------------------------------------------------------------

class _TreeBranch extends StatelessWidget {
  final Color lineColor;
  final List<Widget> children;
  const _TreeBranch({required this.lineColor, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: lineColor, width: 1.5)),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _CheckRow extends StatelessWidget {
  final bool? value;
  final bool tristate;
  final String label;
  final bool bold;
  final void Function(bool?) onChanged;

  const _CheckRow({
    required this.value,
    required this.label,
    required this.onChanged,
    this.tristate = false,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (tristate) {
          onChanged(null); // let toggle logic decide via parent
        } else {
          onChanged(!(value ?? false));
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: value,
                tristate: tristate,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                label,
                style: bold
                    ? Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
                    : Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Storno checkbox + radio sub-group
// ---------------------------------------------------------------------------

class _StornoRow extends StatelessWidget {
  final bool enabled;
  final bool unlimited;
  final void Function(bool) onToggle;
  final void Function(bool unlimited) onTypeChange;

  const _StornoRow({
    required this.enabled,
    required this.unlimited,
    required this.onToggle,
    required this.onTypeChange,
  });

  Widget _radioRow(BuildContext context, {required bool value, required String label}) {
    return InkWell(
      onTap: () => onTypeChange(value),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Radio<bool>(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 2),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => onToggle(!enabled),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: enabled,
                    onChanged: (v) => onToggle(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 2),
                Text('Storno', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: RadioGroup<bool>(
              groupValue: unlimited,
              onChanged: (v) { if (v != null) onTypeChange(v); },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _radioRow(context, value: false, label: '5 min'),
                  _radioRow(context, value: true, label: 'Unbegrenzt'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Global permission group (tree with tri-state group header)
// ---------------------------------------------------------------------------

class _PermissionGroup extends StatelessWidget {
  final String groupName;
  final List<Map<String, dynamic>> nodes;
  final Set<String> selected;
  final void Function(String id, bool val) onToggle;
  final void Function(List<String> ids, bool val) onToggleGroup;

  const _PermissionGroup({
    required this.groupName,
    required this.nodes,
    required this.selected,
    required this.onToggle,
    required this.onToggleGroup,
  });

  bool? get _groupState {
    final count = nodes.where((n) => selected.contains(n['id'] as String)).length;
    if (count == nodes.length) return true;
    if (count == 0) return false;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lineColor = Theme.of(context).colorScheme.outlineVariant;
    final ids = nodes.map((n) => n['id'] as String).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CheckRow(
            value: _groupState,
            tristate: true,
            label: groupName,
            bold: true,
            onChanged: (_) => onToggleGroup(ids, _groupState != true),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2, bottom: 4),
            child: _TreeBranch(
              lineColor: lineColor,
              children: nodes
                  .map((n) => _CheckRow(
                        value: selected.contains(n['id'] as String),
                        label: n['label'] as String,
                        onChanged: (v) => onToggle(n['id'] as String, v ?? false),
                      ))
                  .toList(),
            ),
          ),
          Divider(
            height: 8,
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}
