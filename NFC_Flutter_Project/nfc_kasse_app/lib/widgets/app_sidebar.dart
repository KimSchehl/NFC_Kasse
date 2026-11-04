import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/category_model.dart';
import '../providers/providers.dart';
import '../services/app_logger.dart';
import '../utils/formatters.dart';
import 'dialogs/edit_category_dialog.dart';
import 'product_color_picker.dart';

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
  /// Shows a collapse button in the title bar. Only used for the tablet
  /// rail (see `MainShell`) — the phone Drawer already has its own way to
  /// dismiss (swipe / tap outside / hamburger button).
  final bool showCollapseButton;

  const AppSidebar({super.key, this.showCollapseButton = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final selectedCat = ref.watch(selectedCategoryProvider);
    final currentScreen = ref.watch(currentScreenProvider);
    final editMode = ref.watch(editModeProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final theme = Theme.of(context);

    final prefs = ref.watch(userPrefsProvider);
    final categories = prefs.applyCategoryOrder(categoriesAsync.valueOrNull ?? []);
    final canCreateCategory = user?.hasPermission('categories.create') ?? false;

    final showList = categories.isNotEmpty || canCreateCategory;
    final header = !showList
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'KATEGORIEN',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
          );
    final newCategoryTile = !(showList && canCreateCategory)
        ? null
        : ListTile(
            dense: true,
            leading: Icon(Icons.add_circle_outline,
                size: 18, color: theme.colorScheme.primary),
            title: Text(
              'Neue Kategorie',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            onTap: () => _createCategory(context, ref),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          );
    Widget tileFor(int index, CategoryModel cat) => _CategoryTile(
          key: ValueKey(cat.id),
          index: index,
          category: cat,
          color: prefs.getCategoryColor(cat.id) ?? cat.color,
          selected: selectedCat?.id == cat.id && currentScreen == AppScreen.pos,
          editMode: editMode,
          onTap: () {
            AppLogger.trace('Kategorie angeklickt: ${cat.name}', logger: 'ui.sidebar');
            ref.read(selectedCategoryProvider.notifier).state = cat;
            ref.read(currentScreenProvider.notifier).state = AppScreen.pos;
            _closeDrawer(context);
          },
          onEdit: () => _editCategory(
            context,
            cat,
            canDelete: user?.hasPermission('categories.delete') ?? false,
            canDeactivate: user?.hasPermission('categories.deactivate') ?? false,
          ),
          onPickColor: () => _pickCategoryColor(context, ref, cat),
        );

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
                  Expanded(
                    child: Text(
                      'NFC Kasse',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (showCollapseButton)
                    IconButton(
                      icon: const Icon(Icons.menu_open, size: 20),
                      tooltip: 'Seitenleiste ausblenden',
                      color: theme.colorScheme.primary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        AppLogger.trace('Seitenleiste ausgeblendet', logger: 'ui.sidebar');
                        setSidebarCollapsed(ref, true);
                      },
                    ),
                ],
              ),
            ),

            // Categories list — reorderable (per account) only in edit mode,
            // so a normal tap on the till never starts a drag.
            Expanded(
              child: editMode
                  ? ReorderableListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      buildDefaultDragHandles: false,
                      header: header,
                      footer: newCategoryTile,
                      onReorderItem: (oldIndex, newIndex) {
                        final ids = categories.map((c) => c.id).toList();
                        ids.insert(newIndex, ids.removeAt(oldIndex));
                        AppLogger.trace('Kategorien umsortiert', logger: 'ui.sidebar');
                        ref.read(userPrefsProvider.notifier).setCategoryOrder(ids);
                      },
                      children: [
                        for (final (i, cat) in categories.indexed) tileFor(i, cat),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        ?header,
                        for (final (i, cat) in categories.indexed) tileFor(i, cat),
                        ?newCategoryTile,
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
            if (user?.canViewLogs == true)
              _NavTile(
                icon: Icons.article_outlined,
                label: 'Protokolle',
                selected: currentScreen == AppScreen.logs,
                onTap: () => _navigate(context, ref, AppScreen.logs),
              ),
            if (user?.canManageAnyArticles == true)
              _NavTile(
                icon: Icons.inventory_2_outlined,
                label: 'Artikelverwaltung',
                selected: currentScreen == AppScreen.articleAdmin,
                onTap: () => _navigate(context, ref, AppScreen.articleAdmin),
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
                onTap: () {
                  AppLogger.trace(
                    'Bearbeitungsmodus ${!editMode ? "aktiviert" : "deaktiviert"}',
                    logger: 'ui.sidebar',
                  );
                  ref.read(editModeProvider.notifier).state = !editMode;
                },
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

  void _editCategory(
    BuildContext context,
    CategoryModel category, {
    required bool canDelete,
    required bool canDeactivate,
  }) {
    AppLogger.trace('Kategorie-Dialog geöffnet: ${category.name}', logger: 'ui.sidebar');
    showDialog(
      context: context,
      builder: (_) => EditCategoryDialog(
        category: category,
        canDelete: canDelete,
        canDeactivate: canDeactivate,
      ),
    );
  }

  /// Per-account colour (like the article colours in the Bearbeitungsmodus);
  /// the "none" swatch falls back to the category's default colour.
  void _pickCategoryColor(BuildContext context, WidgetRef ref, CategoryModel category) {
    final notifier = ref.read(userPrefsProvider.notifier);
    final current = ref.read(userPrefsProvider).getCategoryColor(category.id);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(category.name),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Farbe (nur für dein Konto)', style: Theme.of(ctx).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text('Ohne Auswahl gilt die Standard-Farbe der Kategorie.',
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              ProductColorPicker(
                selected: current,
                onChanged: (c) {
                  AppLogger.trace('Kategorie-Farbe gesetzt: ${category.name}', logger: 'ui.sidebar');
                  notifier.setCategoryColor(category.id, c);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen')),
        ],
      ),
    );
  }

  void _closeDrawer(BuildContext context) {
    if (Scaffold.of(context).hasDrawer) Navigator.of(context).pop();
  }

  void _navigate(BuildContext context, WidgetRef ref, AppScreen screen) {
    AppLogger.trace('Navigation: ${screen.name}', logger: 'ui.sidebar');
    ref.read(currentScreenProvider.notifier).state = screen;
    _closeDrawer(context);
  }

  Future<void> _createCategory(BuildContext context, WidgetRef ref) async {
    AppLogger.trace('Neue-Kategorie-Dialog geöffnet', logger: 'ui.sidebar');
    _closeDrawer(context);

    // Capture everything from ref NOW — synchronous, before any await.
    // The drawer close disposes this widget (and invalidates ref) during the
    // first await below, so we must not call ref.read() after that point.
    final productSvc = ref.read(productServiceProvider);
    final categoriesRefreshNotifier = ref.read(categoriesRefreshProvider.notifier);
    final selectedCatNotifier = ref.read(selectedCategoryProvider.notifier);
    final currentScreenNotifier = ref.read(currentScreenProvider.notifier);
    final authNotifier = ref.read(authProvider.notifier);

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
      AppLogger.trace('Neue Kategorie erstellt: $name', logger: 'ui.sidebar');
      final cat = await productSvc.createCategory(name);
      categoriesRefreshNotifier.state++;
      // Manager permissions/category access are only re-evaluated on the
      // next /me call — without this, a manager who just created their
      // first category wouldn't see "Artikelverwaltung" appear until the
      // next login/app restart (canManageAnyArticles reads the stale
      // pre-creation snapshot otherwise).
      unawaited(authNotifier.refreshFromServer());
      // Auto-select the new category
      selectedCatNotifier.state = cat;
      currentScreenNotifier.state = AppScreen.pos;
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Fehler'),
            content: Text(formatApiError(e)),
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
  final int index;
  final CategoryModel category;
  final Color? color; // effective colour (account override ?? default), null = theme
  final bool selected;
  final bool editMode;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onPickColor;

  const _CategoryTile({
    super.key,
    required this.index,
    required this.category,
    required this.selected,
    required this.onTap,
    this.color,
    this.editMode = false,
    this.onEdit,
    this.onPickColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showEdit = editMode && (category.canEditArticle || category.canDeleteArticle);
    final iconColor = color ??
        (selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant);
    final icon = Icon(color != null ? Icons.label : Icons.label_outline, size: 18, color: iconColor);
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: (color ?? theme.colorScheme.primaryContainer).withValues(alpha: 0.5),
      leading: editMode
          ? ReorderableDragStartListener(
              index: index,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.drag_indicator, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  icon,
                ],
              ),
            )
          : icon,
      title: Text(
        category.name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      trailing: editMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.palette_outlined,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  onPressed: onPickColor,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Farbe (nur für dein Konto)',
                ),
                if (showEdit)
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Kategorie bearbeiten',
                  ),
              ],
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
