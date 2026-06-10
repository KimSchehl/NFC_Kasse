import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chip_models.dart';
import '../models/stats_models.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

// ---------------------------------------------------------------------------
// File-level providers — autoDispose so data is fresh on each screen visit.
// Each takes an optional period ID; null = no time filter (all time).
// ---------------------------------------------------------------------------

final _statsProvider = FutureProvider.autoDispose
    .family<RevenueStats, int?>((ref, periodId) async {
  return ref.read(statsServiceProvider).getRevenue(periodId: periodId);
});

final _txProvider = FutureProvider.autoDispose
    .family<List<TransactionItem>, int?>((ref, periodId) async {
  return ref.read(statsServiceProvider).getTransactions(limit: 200, periodId: periodId);
});

final _chipsProvider = FutureProvider.autoDispose<List<ChipModel>>((ref) async {
  return ref.read(customerServiceProvider).getChips();
});

final _chipSummaryProvider = FutureProvider.autoDispose<ChipSummary>((ref) async {
  return ref.read(customerServiceProvider).getSummary();
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Formats a DB datetime string "YYYY-MM-DD HH:MM:SS" to "DD.MM. HH:MM".
String _fmtDt(String dt) {
  final parts = dt.split(' ');
  if (parts.length != 2) return dt;
  final d = parts[0].split('-');
  final t = parts[1].split(':');
  if (d.length != 3 || t.length < 2) return dt;
  return '${d[2]}.${d[1]}. ${t[0]}:${t[1]}';
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  List<StatsPeriod> _periods = [];
  int? _selectedPeriodId; // null = "Alle Zeiten"
  bool _loadingPeriods = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _loadPeriods(autoSelect: true);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadPeriods({bool autoSelect = false}) async {
    try {
      final periods = await ref.read(statsServiceProvider).getPeriods();
      if (!mounted) return;
      setState(() {
        _periods = periods;
        _loadingPeriods = false;
        if (autoSelect && periods.isNotEmpty) {
          final current = periods.firstWhere(
            (p) => p.isOpen,
            orElse: () => periods.first,
          );
          _selectedPeriodId = current.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPeriods = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Perioden konnten nicht geladen werden: ${formatApiError(e)}'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  String _defaultLabel() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}. '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} Uhr';
  }

  Future<void> _executePeriodClose(String label) async {
    try {
      final newPeriod = await ref.read(statsServiceProvider).closePeriod(label);
      await _loadPeriods();
      if (!mounted) return;
      setState(() => _selectedPeriodId = newPeriod.id);
      ref.invalidate(_statsProvider);
      ref.invalidate(_txProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fehler: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  Future<void> _showCloseDialog() async {
    final defaultLabel = _defaultLabel();
    final labelCtrl = TextEditingController(text: defaultLabel);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tagesabschluss'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aktuelle Periode beenden und eine neue starten?'),
            const SizedBox(height: 16),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung der neuen Periode',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abschließen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final label = labelCtrl.text.trim().isEmpty ? defaultLabel : labelCtrl.text.trim();
    await _executePeriodClose(label);
  }

  Future<void> _showEventResetDialog() async {
    final theme = Theme.of(context);
    final defaultLabel = 'Neues Event ${_defaultLabel()}';
    final labelCtrl = TextEditingController(text: defaultLabel);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            const Text('Neues Event starten'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Diese Aktion setzt ALLE NFC-Chips zurück:\n\n'
                '• Alle Guthaben werden auf 0,00 € gesetzt\n'
                '• Alle Chips gelten beim nächsten Scan\n'
                '   als neue Kunden (Pfand wird erneut erhoben)\n'
                '• Ein Tagesabschluss wird automatisch gemacht\n\n'
                'Artikel, Benutzer und der Buchungsverlauf\n'
                'bleiben vollständig erhalten.',
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung der neuen Periode',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final label = labelCtrl.text.trim().isEmpty ? defaultLabel : labelCtrl.text.trim();

    try {
      final newPeriod = await ref.read(statsServiceProvider).eventReset(label);
      await _loadPeriods();
      if (!mounted) return;
      setState(() => _selectedPeriodId = newPeriod.id);
      ref.invalidate(_statsProvider);
      ref.invalidate(_txProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Chips zurückgesetzt — bereit für neues Event.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fehler: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  String _periodLabel(StatsPeriod p) {
    if (p.isOpen) return '${p.label} (aktiv seit ${_fmtDt(p.startedAt)})';
    return '${p.label}  ${_fmtDt(p.startedAt)} – ${_fmtDt(p.closedAt!)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).valueOrNull;
    final canClose = user?.hasPermission('statistics.revenue') ?? false;

    return Column(
      children: [
        // ── Header: period selector + Tagesabschluss ──────────────────
        Container(
          color: theme.colorScheme.surfaceContainerHigh,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: period dropdown full width
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _loadingPeriods
                    ? const SizedBox(
                        height: 36,
                        child: Center(child: LinearProgressIndicator()),
                      )
                    : DropdownButton<int?>(
                        value: _selectedPeriodId,
                        isExpanded: true,
                        isDense: true,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.expand_more, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Alle Zeiten'),
                          ),
                          ..._periods.map(
                            (p) => DropdownMenuItem<int?>(
                              value: p.id,
                              child: Row(
                                children: [
                                  if (p.isOpen)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      _periodLabel(p),
                                      overflow: TextOverflow.ellipsis,
                                      style: p.isOpen
                                          ? TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedPeriodId = v);
                          ref.invalidate(_statsProvider(v));
                          ref.invalidate(_txProvider(v));
                        },
                      ),
              ),
              // Row 2: action buttons
              if (canClose)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: _showCloseDialog,
                        icon: const Icon(Icons.flag_outlined, size: 18),
                        label: const Text('Tagesabschluss'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.secondary,
                          foregroundColor: theme.colorScheme.onSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _showEventResetDialog,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Neues Event'),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              TabBar(
                controller: _tab,
                tabs: const [
                  Tab(icon: Icon(Icons.bar_chart), text: 'Übersicht'),
                  Tab(icon: Icon(Icons.receipt_long), text: 'Transaktionen'),
                  Tab(icon: Icon(Icons.contactless), text: 'Chips'),
                ],
              ),
            ],
          ),
        ),

        // ── Tab content ───────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _RevenueTab(periodId: _selectedPeriodId),
              _TransactionsTab(periodId: _selectedPeriodId),
              const _ChipsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Übersicht
// ---------------------------------------------------------------------------

class _RevenueTab extends ConsumerWidget {
  final int? periodId;
  const _RevenueTab({this.periodId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider(periodId));
    final theme = Theme.of(context);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            ...stats.byCategory.map((cat) => _CategoryRow(cat: cat)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Transaktionen
// ---------------------------------------------------------------------------

class _TransactionsTab extends ConsumerWidget {
  final int? periodId;
  const _TransactionsTab({this.periodId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(_txProvider(periodId));
    final theme = Theme.of(context);

    return txAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
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
                    backgroundColor: tx.cancelled
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.secondaryContainer,
                    child: Icon(
                      tx.cancelled
                          ? Icons.cancel_outlined
                          : Icons.receipt_outlined,
                      size: 16,
                      color: tx.cancelled
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: Text(
                    tx.productName,
                    style: tx.cancelled
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                  subtitle: Text('${tx.nfcUid}  ·  ${formatTime(tx.bookedAt)} Uhr'),
                  trailing: Text(
                    formatPrice(tx.priceAtSale),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: tx.cancelled
                          ? theme.colorScheme.onSurfaceVariant
                          : tx.priceAtSale < 0
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

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tab: Chips
// ---------------------------------------------------------------------------

class _ChipsTab extends ConsumerStatefulWidget {
  const _ChipsTab();

  @override
  ConsumerState<_ChipsTab> createState() => _ChipsTabState();
}

class _ChipsTabState extends ConsumerState<_ChipsTab> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(_chipSummaryProvider);
    final chipsAsync = ref.watch(_chipsProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Bilanz-Karten ──────────────────────────────────────────────
        summaryAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Fehler: ${formatApiError(e)}',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
          data: (s) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Aktive Chips',
                      value: '${s.activeChips} / ${s.totalChips}',
                      icon: Icons.contactless,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Guthaben gesamt',
                      value: formatPrice(s.totalBalance),
                      icon: Icons.account_balance_wallet_outlined,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Pfand ausstehend',
                      value: formatPrice(s.pendingPfand),
                      icon: Icons.lock_outline,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Aufgeladen',
                      value: formatPrice(s.totalTopup),
                      icon: Icons.add_card_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),

        // ── Suchfeld ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Chip-UID suchen …',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _query = v.trim().toUpperCase()),
          ),
        ),

        // ── Chip-Liste ─────────────────────────────────────────────────
        Expanded(
          child: chipsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Fehler: ${formatApiError(e)}',
                    style: TextStyle(color: theme.colorScheme.error))),
            data: (chips) {
              final filtered = _query.isEmpty
                  ? chips
                  : chips
                      .where((c) => c.nfcUid.contains(_query))
                      .toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('Keine Chips gefunden'));
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (_, i) {
                  final chip = filtered[i];
                  final isActive = chip.isActive;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: isActive
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHigh,
                      child: Icon(
                        Icons.contactless,
                        size: 18,
                        color: isActive
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      chip.nfcUid,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                    ),
                    subtitle: chip.lastProductName != null
                        ? Text(
                            '${chip.lastProductName}'
                            '${chip.lastBookedAt != null ? '  ·  ${formatDateTime(chip.lastBookedAt!)}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : const Text('Noch keine Buchung'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatPrice(chip.balance),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: chip.balance > 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          isActive ? 'Aktiv' : 'Frei',
                          style: TextStyle(
                            fontSize: 11,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
