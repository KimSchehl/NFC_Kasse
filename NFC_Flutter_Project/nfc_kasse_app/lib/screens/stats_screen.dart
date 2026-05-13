import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/stats_models.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

// autoDispose — data is discarded when the screen is left, so it re-fetches
// fresh data each time the user navigates back to the stats screen.
final _statsProvider = FutureProvider.autoDispose<RevenueStats>((ref) async {
  return ref.read(statsServiceProvider).getRevenue();
});

final _txProvider = FutureProvider.autoDispose<List<TransactionItem>>((ref) async {
  return ref.read(statsServiceProvider).getTransactions(limit: 50);
});

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header
        Container(
          color: theme.colorScheme.surfaceContainerHigh,
          child: TabBar(
            controller: _tab,
            tabs: const [
              Tab(icon: Icon(Icons.bar_chart), text: 'Übersicht'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Transaktionen'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _RevenueTab(),
              _TransactionsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _RevenueTab extends ConsumerWidget {
  const _RevenueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);
    final theme = Theme.of(context);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Gesamtumsatz',
                    value: formatPrice(stats.totalRevenue),
                    icon: Icons.euro,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Transaktionen',
                    value: stats.totalTransactions.toString(),
                    icon: Icons.receipt,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Nach Kategorie', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            // Category breakdown
            ...stats.byCategory.map((cat) => _CategoryRow(cat: cat)),
          ],
        ),
      ),
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  const _TransactionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(_txProvider);
    final theme = Theme.of(context);

    return txAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (transactions) => transactions.isEmpty
          ? const Center(child: Text('Keine Transaktionen'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: transactions.length,
              separatorBuilder: (_, i) => const Divider(height: 1, indent: 16),
              itemBuilder: (_, i) {
                final tx = transactions[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(Icons.receipt_outlined, size: 16,
                        color: theme.colorScheme.onSecondaryContainer),
                  ),
                  title: Text(tx.productName),
                  subtitle: Text('${tx.nfcUid}  ·  ${formatTime(tx.bookedAt)} Uhr'),
                  trailing: Text(
                    formatPrice(tx.priceAtSale),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: tx.priceAtSale < 0
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                )),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final CategoryRevenue cat;

  const _CategoryRow({required this.cat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(cat.categoryName)),
          Text(
            formatPrice(cat.revenue),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${cat.transactionCount})',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
