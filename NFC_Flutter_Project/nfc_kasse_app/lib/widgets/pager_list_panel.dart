import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'arm_confirm_button.dart';

/// Whether the pager list belongs on the POS screen right now (both layouts):
/// pager add-on, the Settings switch on, and a selected category that has a
/// pager article (options inherit the flag from their base, which is in the
/// same list).
bool watchShowPagerList(WidgetRef ref) {
  final category = ref.watch(selectedCategoryProvider);
  final categoryHasPager = category != null &&
      (ref.watch(productsProvider(category.id)).valueOrNull?.any((p) => p.requiresPager) ??
          false);
  return (ref.watch(authProvider).valueOrNull?.pagerEnabled ?? false) &&
      ref.watch(pagerListEnabledProvider) &&
      categoryHasPager;
}

/// Lists the operator's own open pager orders — pager add-on, see
/// `pagerListProvider`. On the wide/tablet layout it is the left-of-grid
/// panel whose width comes from the parent (`SizedBox` in `pos_screen.dart`
/// sized from `pagerWidthProvider`), same as `CartPanel`. On phones it fills
/// the bottom sheet of [showPagerListSheet], which passes its
/// [scrollController] (no collapse button there).
class PagerListPanel extends ConsumerWidget {
  final ScrollController? scrollController;

  const PagerListPanel({super.key, this.scrollController});

  /// Shared by the "PAGER" header and the number in each row, both centred.
  static const _pagerColumnWidth = 56.0;

  /// Below this panel width the three-column row leaves the articles only a
  /// sliver, so each order is stacked instead: pager number + "Fertig" on
  /// top, the articles at full width underneath.
  static const _stackedBelowWidth = 340.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncList = ref.watch(pagerListProvider);

    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < _stackedBelowWidth;
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            color: theme.colorScheme.surfaceContainerHigh,
            child: Row(
              children: [
                Expanded(child: Text('Pager', style: theme.textTheme.headlineSmall)),
                if (scrollController == null)
                  IconButton(
                    icon: const Icon(Icons.menu_open, size: 20),
                    tooltip: 'Pagerliste einklappen',
                    color: theme.colorScheme.primary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setPagerListCollapsed(ref, true),
                  ),
              ],
            ),
          ),
          if (!stacked) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'ARTIKEL',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: _pagerColumnWidth,
                  child: Text(
                    'PAGER',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 96), // aligns with the action column below
              ],
            ),
          ),
          if (!stacked) const Divider(height: 1),
          Expanded(
            child: asyncList.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
              data: (orders) => orders.isEmpty
                  ? Center(
                      child: Text(
                        'Keine offenen Pager',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final order in orders)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            child: stacked
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Pager ${order.pagerNumber}',
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          ArmConfirmButton(
                                            onConfirmed: () => _markDone(context, ref, order.id),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      _items(theme, order.itemSummary),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(flex: 3, child: _items(theme, order.itemSummary)),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: _pagerColumnWidth,
                                        child: Text(
                                          '${order.pagerNumber}',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ArmConfirmButton(
                                        onConfirmed: () => _markDone(context, ref, order.id),
                                      ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      );
    });
  }

  /// One line per article (at most 3 lines each, then "…"): the server
  /// stores "2× Pizza, Steak" (sales.py _build_pager_item_summary), so split
  /// there.
  Widget _items(ThemeData theme, String itemSummary) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in itemSummary.split(', '))
            Text(
              item,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
        ],
      );

  Future<void> _markDone(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(pagerServiceProvider).markDone(id);
      await ref.read(pagerListProvider.notifier).refresh();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatApiError(e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

/// Collapsed form of [PagerListPanel]: a narrow strip with an expand button
/// and the number of open pagers, so they aren't forgotten while collapsed.
class PagerListStrip extends ConsumerWidget {
  const PagerListStrip({super.key});

  static const width = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(pagerListProvider).valueOrNull?.length ?? 0;
    return Container(
      width: width,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.only(top: 8),
      alignment: Alignment.topCenter,
      child: IconButton(
        tooltip: 'Pagerliste einblenden',
        color: theme.colorScheme.primary,
        onPressed: () => setPagerListCollapsed(ref, false),
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: const Icon(Icons.vibration),
        ),
      ),
    );
  }
}

/// Phone counterpart of [PagerListStrip]: AppBar icon with the number of
/// open pagers that opens [showPagerListSheet]. `main_shell.dart` places it
/// only on the narrow POS layout; hidden whenever [watchShowPagerList] is.
class PagerHeaderButton extends ConsumerWidget {
  const PagerHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!watchShowPagerList(ref)) return const SizedBox.shrink();
    final count = ref.watch(pagerListProvider).valueOrNull?.length ?? 0;
    return IconButton(
      tooltip: 'Pagerliste',
      onPressed: () => showPagerListSheet(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.vibration),
      ),
    );
  }
}

/// Opens [PagerListPanel] as a bottom sheet that can be dragged taller and
/// swiped away. It watches `pagerListProvider` itself, so it stays live.
void showPagerListSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => PagerListPanel(scrollController: controller),
    ),
  );
}
