import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../providers/providers.dart';
import 'dialogs/edit_category_dialog.dart';

/// Navigation sidebar shown on the left of the screen (tablet) or inside a
/// Drawer (phone).
///
/// Contains:
/// - The NFC Kasse logo header
/// - The list of categories accessible to the logged-in user
/// - Bottom nav tiles (Statistik, Benutzer, Einstellungen, Bearbeitungsmodus)
/// - The current user's name at the very bottom
///
/// The "Neue Kategorie" button and the category edit pencil icons are only
/// visible when the user has the required permissions. The Bearbeitungsmodus
/// toggle is only shown when on the POS screen and the user has edit rights.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final selectedCat = ref.watch(selectedCategoryProvider);
    final currentScreen = ref.watch(currentScreenProvider);
    final editMode = ref.watch(editModeProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    final categories = categoriesAsync.valueOrNull ?? [];
    final canCreateCategory = user?.hasPermission('categories.create') ?? false;

    return Container(
      width: 220,
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            // App title bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(Icons.point_of_sale, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'NFC Kasse',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            // Categories list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (categories.isNotEmpty || canCreateCategory) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(
                        'KATEGORIEN',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    ...categories.map((cat) => _CategoryTile(
                          category: cat,
                          selected: selectedCat?.id == cat.id &&
                              currentScreen == AppScreen.pos,
                          editMode: editMode,
                          onTap: () {
                            ref.read(selectedCategoryProvider.notifier).state = cat;
                            ref.read(currentScreenProvider.notifier).state = AppScreen.pos;
                            _closeDrawer(context);
                          },
                          onEdit: () => _editCategory(context, cat, user?.hasPermission('categories.delete') ?? false),
                        )),
                    // "New category" button
                    if (canCreateCategory)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.add_circle_outline,
                            size: 18, color: theme.colorScheme.primary),
                        title: Text(
                          'Neue Kategorie',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                        onTap: () => _createCategory(context, ref),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                  ],
                ],
              ),
            ),

            // Bottom nav items
            const Divider(height: 1),
            if (user?.canViewStats == true)
              _NavTile(
                icon: Icons.bar_chart,
                label: 'Statistik',
                selected: currentScreen == AppScreen.stats,
                onTap: () => _navigate(context, ref, AppScreen.stats),
              ),
            if (user?.canManageUsers == true)
              _NavTile(
                icon: Icons.people_outline,
                label: 'Benutzer',
                selected: currentScreen == AppScreen.users,
                onTap: () => _navigate(context, ref, AppScreen.users),
              ),
            _NavTile(
              icon: Icons.settings_outlined,
              label: 'Einstellungen',
              selected: currentScreen == AppScreen.settings,
              onTap: () => _navigate(context, ref, AppScreen.settings),
            ),

            // Edit mode toggle: always visible on POS (everyone can set button colors)
            if (currentScreen == AppScreen.pos)
              _NavTile(
                icon: editMode ? Icons.edit_off_outlined : Icons.edit_outlined,
                label: 'Bearbeitungsmodus',
                selected: editMode,
                selectedColor: theme.colorScheme.tertiary,
                onTap: () => ref.read(editModeProvider.notifier).state = !editMode,
              ),

            const Divider(height: 1),

            // Current user at bottom
            _NavTile(
              icon: Icons.account_circle_outlined,
              label: user?.displayLabel ?? '–',
              selected: currentScreen == AppScreen.account,
              onTap: () => _navigate(context, ref, AppScreen.account),
            ),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _editCategory(BuildContext context, CategoryModel category, bool canDelete) {
    showDialog(
      context: context,
      builder: (_) => EditCategoryDialog(
        category: category,
        canDelete: canDelete,
      ),
    );
  }

  void _closeDrawer(BuildContext context) {
    if (Scaffold.of(context).hasDrawer) Navigator.of(context).pop();
  }

  void _navigate(BuildContext context, WidgetRef ref, AppScreen screen) {
    ref.read(currentScreenProvider.notifier).state = screen;
    _closeDrawer(context);
  }

  Future<void> _createCategory(BuildContext context, WidgetRef ref) async {
    _closeDrawer(context);

    // Capture everything from ref NOW — synchronous, before any await.
    // The drawer close disposes this widget (and invalidates ref) during the
    // first await below, so we must not call ref.read() after that point.
    final productSvc = ref.read(productServiceProvider);
    final categoriesRefreshNotifier = ref.read(categoriesRefreshProvider.notifier);
    final selectedCatNotifier = ref.read(selectedCategoryProvider.notifier);
    final currentScreenNotifier = ref.read(currentScreenProvider.notifier);

    String inputName = '';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        String error = '';
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Neue Kategorie'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    errorText: error.isEmpty ? null : error,
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (v) {
                    if (error.isNotEmpty) setState(() => error = '');
                  },
                  onSubmitted: (_) {
                    final v = controller.text.trim();
                    if (v.isEmpty) {
                      setState(() => error = 'Name darf nicht leer sein');
                    } else {
                      inputName = v;
                      Navigator.pop(ctx, true);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isEmpty) {
                    setState(() => error = 'Name darf nicht leer sein');
                  } else {
                    inputName = v;
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Erstellen'),
              ),
            ],
          ),
        );
      },
    );
    if (result != true) return;

    final name = inputName.trim();
    if (name.isEmpty) return;

    try {
      final cat = await productSvc.createCategory(name);
      categoriesRefreshNotifier.state++;
      // Auto-select the new category
      selectedCatNotifier.state = cat;
      currentScreenNotifier.state = AppScreen.pos;
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Fehler'),
            content: Text(e.toString()),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}

class _CategoryTile extends StatelessWidget {
  final CategoryModel category;
  final bool selected;
  final bool editMode;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
    this.editMode = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showEdit = editMode && (category.canEditArticle || category.canDeleteArticle);
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      leading: Icon(
        Icons.label_outline,
        size: 18,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        category.name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      trailing: showEdit
          ? IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: 'Kategorie bearbeiten',
            )
          : null,
      onTap: onTap,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? (selectedColor ?? theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor:
          (selectedColor ?? theme.colorScheme.primaryContainer).withValues(alpha: 0.3),
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
}
