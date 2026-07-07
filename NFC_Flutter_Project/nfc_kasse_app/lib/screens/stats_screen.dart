import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chip_models.dart';
import '../models/stats_models.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

// ---------------------------------------------------------------------------
// File-level providers — autoDispose so data is fresh on each screen visit.
// Family key is String? where null = all time, "1" = single period,
// "1,3,5" = combined periods (sorted, comma-separated IDs).
// ---------------------------------------------------------------------------

final _statsProvider = FutureProvider.autoDispose
    .family<RevenueStats, String?>((ref, periodKey) async {
  return ref.read(statsServiceProvider).getRevenue(periodIds: periodKey);
});

final _txProvider = FutureProvider.autoDispose
    .family<List<TransactionItem>, String?>((ref, periodKey) async {
  return ref.read(statsServiceProvider).getTransactions(limit: 200, periodIds: periodKey);
});

final _chipsProvider = FutureProvider.autoDispose<List<ChipModel>>((ref) async {
  return ref.read(customerServiceProvider).getChips();
});

final _chipSummaryProvider = FutureProvider.autoDispose
    .family<ChipSummary, String?>((ref, periodKey) async {
  return ref.read(customerServiceProvider).getSummary(periodIds: periodKey);
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
  Set<int> _selectedPeriodIds = {};
  bool _loadingPeriods = true;

  /// Null = "Alle Zeiten", "5" = single period, "1,3,5" = combined.
  String? get _periodKey {
    if (_selectedPeriodIds.isEmpty) return null;
    final sorted = _selectedPeriodIds.toList()..sort();
    return sorted.join(',');
  }

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
          _selectedPeriodIds = {current.id};
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
      setState(() => _selectedPeriodIds = {newPeriod.id});
      ref.invalidate(_statsProvider(_periodKey));
      ref.invalidate(_txProvider(_periodKey));
      ref.invalidate(_chipSummaryProvider(_periodKey));
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
      setState(() => _selectedPeriodIds = {newPeriod.id});
      ref.invalidate(_statsProvider(_periodKey));
      ref.invalidate(_txProvider(_periodKey));
      ref.invalidate(_chipSummaryProvider(_periodKey));
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

  String get _selectionSummary {
    if (_selectedPeriodIds.isEmpty) return 'Alle Zeiten';
    if (_selectedPeriodIds.length == 1) {
      final p = _periods.where((p) => p.id == _selectedPeriodIds.first).firstOrNull;
      return p != null ? _periodLabel(p) : '1 Periode';
    }
    return '${_selectedPeriodIds.length} Perioden';
  }

  Future<void> _openPeriodSelector() async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => _PeriodSelectorDialog(
        periods: _periods,
        selected: Set.of(_selectedPeriodIds),
        periodLabel: _periodLabel,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selectedPeriodIds = result);
    ref.invalidate(_statsProvider(_periodKey));
    ref.invalidate(_txProvider(_periodKey));
    ref.invalidate(_chipSummaryProvider(_periodKey));
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
              // Row 1: period selector button
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _loadingPeriods
                    ? const SizedBox(
                        height: 36,
                        child: Center(child: LinearProgressIndicator()),
                      )
                    : OutlinedButton.icon(
                        onPressed: _openPeriodSelector,
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectionSummary,
                                overflow: TextOverflow.ellipsis,
                                style: _selectedPeriodIds.length == 1 &&
                                        _periods
                                            .where((p) => p.id == _selectedPeriodIds.first)
                                            .any((p) => p.isOpen)
                                    ? TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      )
                                    : null,
                              ),
                            ),
                            Icon(Icons.expand_more,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
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
              _RevenueTab(periodKey: _periodKey),
              _TransactionsTab(periodKey: _periodKey),
              _ChipsTab(periodKey: _periodKey),
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
  final String? periodKey;
  const _RevenueTab({this.periodKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider(periodKey));
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
            ...stats.byCategory.map((cat) => _CategoryExpansionTile(cat: cat)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Transaktionen
// ---------------------------------------------------------------------------

/// Groups consecutive rows that belong to the same cart submission:
/// same nfcUid + same cashier + all booked within 3 seconds of each other.
List<_BookingGroup> _groupTransactions(List<TransactionItem> items) {
  if (items.isEmpty) return [];

  // Items come newest-first; group by proximity in time.
  final groups = <_BookingGroup>[];
  _BookingGroup? current;

  for (final tx in items) {
    if (current != null &&
        tx.nfcUid == current.nfcUid &&
        tx.bookedByUsername == current.bookedByUsername &&
        _parseSeconds(current.bookedAt) - _parseSeconds(tx.bookedAt) <= 3) {
      current.items.add(tx);
    } else {
      current = _BookingGroup(
        nfcUid: tx.nfcUid,
        bookedAt: tx.bookedAt,
        bookedByUsername: tx.bookedByUsername,
        items: [tx],
      );
      groups.add(current);
    }
  }
  return groups;
}

double _parseSeconds(String dt) {
  try {
    return DateTime.parse(dt.replaceFirst(' ', 'T'))
        .millisecondsSinceEpoch
        .toDouble();
  } catch (_) {
    return 0;
  }
}

class _BookingGroup {
  final String nfcUid;
  final String bookedAt;
  final String bookedByUsername;
  final List<TransactionItem> items;

  _BookingGroup({
    required this.nfcUid,
    required this.bookedAt,
    required this.bookedByUsername,
    required this.items,
  });

  double get total => items.fold(0.0, (s, t) => s + (t.cancelled ? 0 : t.priceAtSale));
  bool get allCancelled => items.every((t) => t.cancelled);
}

class _TransactionsTab extends ConsumerStatefulWidget {
  final String? periodKey;
  const _TransactionsTab({this.periodKey});

  @override
  ConsumerState<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends ConsumerState<_TransactionsTab> {
  final _searchCtrl = TextEditingController();
  String _uidFilter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(_txProvider(widget.periodKey));

    return Column(
      children: [
        // NFC-UID-Suchfeld
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Chip-UID suchen (scannen oder tippen) …',
              prefixIcon: const Icon(Icons.contactless, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _uidFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() {
                        _searchCtrl.clear();
                        _uidFilter = '';
                      }),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _uidFilter = v.trim().toUpperCase()),
          ),
        ),

        Expanded(
          child: txAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
            data: (transactions) {
              final filtered = _uidFilter.isEmpty
                  ? transactions
                  : transactions
                      .where((t) => t.nfcUid.toUpperCase().contains(_uidFilter))
                      .toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('Keine Transaktionen'));
              }

              final groups = _groupTransactions(filtered);

              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: groups.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) => _BookingGroupTile(group: groups[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BookingGroupTile extends StatefulWidget {
  final _BookingGroup group;
  const _BookingGroupTile({required this.group});

  @override
  State<_BookingGroupTile> createState() => _BookingGroupTileState();
}

class _BookingGroupTileState extends State<_BookingGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.group;
    final single = g.items.length == 1;

    // For single-item groups, show a flat ListTile (no expansion needed).
    if (single) {
      final tx = g.items.first;
      return ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: tx.cancelled
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.secondaryContainer,
          child: Icon(
            tx.cancelled ? Icons.cancel_outlined : Icons.receipt_outlined,
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
        subtitle: Text('${tx.nfcUid}  ·  ${_fmtDt(tx.bookedAt)}  ·  ${tx.bookedByUsername}'),
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
    }

    // Multi-item group: collapsible header + item rows.
    final headerColor = g.allCancelled
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.primaryContainer;
    final headerOnColor = g.allCancelled
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: headerColor,
                  child: Icon(Icons.shopping_bag_outlined,
                      size: 16, color: headerOnColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${g.items.length} Artikel',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${g.nfcUid}  ·  ${_fmtDt(g.bookedAt)}  ·  ${g.bookedByUsername}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  formatPrice(g.total),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: g.allCancelled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...g.items.map((tx) => Padding(
                padding: const EdgeInsets.only(left: 44, right: 16, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      tx.cancelled ? Icons.cancel_outlined : Icons.circle,
                      size: tx.cancelled ? 14 : 6,
                      color: tx.cancelled
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tx.productName,
                        style: tx.cancelled
                            ? TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                              )
                            : const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      formatPrice(tx.priceAtSale),
                      style: TextStyle(
                        fontSize: 13,
                        color: tx.cancelled
                            ? theme.colorScheme.onSurfaceVariant
                            : tx.priceAtSale < 0
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              )),
      ],
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

class _CategoryExpansionTile extends StatefulWidget {
  final CategoryRevenue cat;
  const _CategoryExpansionTile({required this.cat});

  @override
  State<_CategoryExpansionTile> createState() => _CategoryExpansionTileState();
}

class _CategoryExpansionTileState extends State<_CategoryExpansionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = widget.cat;

    final normalArticles =
        cat.articles.where((a) => !a.isPayout && !a.excludeFromStats).toList();
    final extraArticles =
        cat.articles.where((a) => a.excludeFromStats && !a.isPayout).toList();
    final payoutArticles = cat.articles.where((a) => a.isPayout).toList();
    final hasDetails = cat.articles.isNotEmpty;

    // Label for the excl_stats section: "Aufladungen" when all add credit to chip,
    // "Pfand" when at least some take credit from chip.
    String extraLabel = 'Pfand / Aufladungen';
    if (extraArticles.isNotEmpty) {
      final allToChip = extraArticles.every((a) => a.revenue < 0);
      final allFromChip = extraArticles.every((a) => a.revenue > 0);
      if (allToChip) extraLabel = 'Aufladungen';
      if (allFromChip) extraLabel = 'Pfand';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header row ──────────────────────────────────────────────────
        InkWell(
          onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(cat.categoryName,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                Text(
                  formatPrice(cat.revenue),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 6),
                Text('(${cat.transactionCount})',
                    style: theme.textTheme.bodySmall),
                if (hasDetails) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ] else
                  const SizedBox(width: 22),
              ],
            ),
          ),
        ),

        // ── Expanded article breakdown ──────────────────────────────────
        if (_expanded) ...[
          if (normalArticles.isNotEmpty)
            ...normalArticles.map((a) => _ArticleDetailRow(article: a)),
          if (extraArticles.isNotEmpty) ...[
            _ArticleSectionHeader(label: extraLabel),
            ...extraArticles.map((a) => _ArticleDetailRow(article: a)),
          ],
          if (payoutArticles.isNotEmpty) ...[
            _ArticleSectionHeader(label: 'Auszahlungen'),
            ...payoutArticles.map((a) => _ArticleDetailRow(article: a)),
          ],
          const SizedBox(height: 4),
        ],

        const Divider(height: 1),
      ],
    );
  }
}

class _ArticleSectionHeader extends StatelessWidget {
  final String label;
  const _ArticleSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6, bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ArticleDetailRow extends StatelessWidget {
  final ArticleBreakdown article;
  const _ArticleDetailRow({required this.article});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // revenue < 0 means money was added to the chip (topup / Pfand issuance).
    final toChip = article.revenue < 0;
    final absRevenue = article.revenue.abs();
    final displayAmount =
        toChip ? '+ ${formatPrice(absRevenue)}' : formatPrice(absRevenue);
    final amountColor =
        toChip ? theme.colorScheme.tertiary : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              article.productName,
              style: TextStyle(
                  fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(
            '${article.transactionCount}×',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            displayAmount,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: amountColor),
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
  final String? periodKey;
  const _ChipsTab({this.periodKey});

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
    final summaryAsync = ref.watch(_chipSummaryProvider(widget.periodKey));
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

// ---------------------------------------------------------------------------
// Period multi-selector dialog
// ---------------------------------------------------------------------------

class _PeriodSelectorDialog extends StatefulWidget {
  final List<StatsPeriod> periods;
  final Set<int> selected;
  final String Function(StatsPeriod) periodLabel;

  const _PeriodSelectorDialog({
    required this.periods,
    required this.selected,
    required this.periodLabel,
  });

  @override
  State<_PeriodSelectorDialog> createState() => _PeriodSelectorDialogState();
}

class _PeriodSelectorDialogState extends State<_PeriodSelectorDialog> {
  late Set<int> _current;

  @override
  void initState() {
    super.initState();
    _current = Set.of(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Zeitraum auswählen'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: Icon(
                _current.isEmpty ? Icons.check_circle : Icons.circle_outlined,
                color: _current.isEmpty
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              title: const Text('Alle Zeiten'),
              onTap: () => setState(() => _current.clear()),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.periods.length,
                itemBuilder: (_, i) {
                  final p = widget.periods[i];
                  final checked = _current.contains(p.id);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    secondary: p.isOpen
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        : const SizedBox(width: 8),
                    title: Text(
                      widget.periodLabel(p),
                      style: p.isOpen
                          ? TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _current.add(p.id);
                      } else {
                        _current.remove(p.id);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _current),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
