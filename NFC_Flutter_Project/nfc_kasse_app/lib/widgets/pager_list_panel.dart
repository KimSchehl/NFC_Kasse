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
              Text('Pager', style: theme.textTheme.headlineSmall),
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
