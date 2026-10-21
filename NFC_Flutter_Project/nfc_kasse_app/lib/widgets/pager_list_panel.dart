import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'arm_confirm_button.dart';

/// Left-of-grid panel (wide/tablet layout only) listing the operator's own
/// open pager orders — pager add-on, see `pagerListProvider`. Its width
/// comes from the parent (`SizedBox` in `pos_screen.dart` sized from
/// `pagerWidthProvider`), same as `CartPanel`.
class PagerListPanel extends ConsumerWidget {
  const PagerListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncList = ref.watch(pagerListProvider);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Row(
            children: [
              Expanded(child: Text('Pager', style: theme.textTheme.headlineSmall)),
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
        Padding(
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
              Text(
                'PAGER',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 96), // aligns with the action column below
            ],
          ),
        ),
        const Divider(height: 1),
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
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final order in orders)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  order.itemSummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '${order.pagerNumber}',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
  }

  Future<void> _markDone(BuildContext context, WidgetRef ref, int id) async {
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
