import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/kiosk_models.dart';
import '../providers/providers.dart';
import '../services/nfc_service.dart';
import '../utils/formatters.dart';

/// Self-service kiosk screen shown when the logged-in user has 'kiosk.access'.
///
/// Flow:
///   Idle → tap NFC chip → Loading → Result (shows balance + all transactions)
///        → auto-reset after 30 s back to Idle
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

enum _KioskState { idle, loading, result, error }

class _KioskScreenState extends ConsumerState<KioskScreen> {
  _KioskState _state = _KioskState.idle;
  KioskChipInfo? _info;
  String? _errorMsg;
  Timer? _resetTimer;
  bool _nfcAvailable = false;

  static const _resetAfter = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _initNfc();
  }

  Future<void> _initNfc() async {
    final available = await NfcService.isAvailable();
    if (!mounted) return;
    setState(() => _nfcAvailable = available);
    if (available) {
      NfcService.startSession(_onNfcScan);
    }
  }

  void _onNfcScan(String uid) {
    if (_state == _KioskState.loading) return; // already fetching
    _loadChip(uid);
  }

  Future<void> _loadChip(String rawUid) async {
    final uid = normalizeUid(rawUid) ?? rawUid.toUpperCase();
    _resetTimer?.cancel();
    setState(() {
      _state = _KioskState.loading;
      _info = null;
      _errorMsg = null;
    });

    try {
      final info = await ref.read(kioskServiceProvider).getChipInfo(uid);
      if (!mounted) return;
      setState(() {
        _state = _KioskState.result;
        _info = info;
      });
      _resetTimer = Timer(_resetAfter, _resetToIdle);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _KioskState.error;
        _errorMsg = 'Chip nicht gefunden oder Fehler beim Laden.';
      });
      _resetTimer = Timer(const Duration(seconds: 5), _resetToIdle);
    }
  }

  void _resetToIdle() {
    _resetTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _state = _KioskState.idle;
      _info = null;
      _errorMsg = null;
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    if (_nfcAvailable) NfcService.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              username: user?.displayLabel ?? '',
              onLogout: () => ref.read(authProvider.notifier).logout(),
            ),
            Expanded(
              child: switch (_state) {
                _KioskState.idle => _IdleView(nfcAvailable: _nfcAvailable),
                _KioskState.loading => const _LoadingView(),
                _KioskState.result => _ResultView(
                    info: _info!,
                    onReset: _resetToIdle,
                    resetDuration: _resetAfter,
                  ),
                _KioskState.error => _ErrorView(
                    message: _errorMsg ?? 'Unbekannter Fehler',
                    onReset: _resetToIdle,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final String username;
  final VoidCallback onLogout;

  const _Header({required this.username, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront, size: 20),
          const SizedBox(width: 8),
          Text(
            username,
            style: theme.textTheme.titleMedium,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Abmelden'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle state
// ---------------------------------------------------------------------------

class _IdleView extends StatelessWidget {
  final bool nfcAvailable;

  const _IdleView({required this.nfcAvailable});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            nfcAvailable ? Icons.nfc : Icons.credit_card,
            size: 120,
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 32),
          Text(
            'Chip antippen',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w300,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Armband oder Karte an das Lesegerät halten',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onReset;

  const _ErrorView({required this.message, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.titleMedium),
          const SizedBox(height: 24),
          FilledButton(onPressed: onReset, child: const Text('Zurück')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result view: balance card + transaction list
// ---------------------------------------------------------------------------

class _ResultView extends StatefulWidget {
  final KioskChipInfo info;
  final VoidCallback onReset;
  final Duration resetDuration;

  const _ResultView({
    required this.info,
    required this.onReset,
    required this.resetDuration,
  });

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView>
    with SingleTickerProviderStateMixin {
  late AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.resetDuration)
      ..forward();
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onReset();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final balance = info.balance;
    final isNegative = balance < 0;

    return Column(
      children: [
        // Balance card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          color: isNegative
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aktuelles Guthaben',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isNegative
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _fmtEur(balance),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isNegative
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              if (info.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Noch keine Buchungen',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Countdown bar
        AnimatedBuilder(
          animation: _progress,
          builder: (_, _) => LinearProgressIndicator(
            value: 1.0 - _progress.value,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            minHeight: 3,
          ),
        ),

        // Transaction list header
        if (info.transactions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Transaktionen', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${info.transactions.length} Einträge',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: info.transactions.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) =>
                  _TransactionTile(tx: info.transactions[i]),
            ),
          ),
        ] else
          const Expanded(child: SizedBox.shrink()),

        // Reset button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: widget.onReset,
              child: const Text('Fertig'),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction list tile
// ---------------------------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  final KioskTransaction tx;

  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTopup = tx.type == 'topup';
    final isCancelled = tx.cancelled;

    final priceColor = isCancelled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : isTopup
            ? Colors.green.shade600
            : theme.colorScheme.onSurface;

    return Opacity(
      opacity: isCancelled ? 0.5 : 1.0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCancelled
              ? theme.colorScheme.surfaceContainerHighest
              : isTopup
                  ? Colors.green.withValues(alpha: 0.15)
                  : theme.colorScheme.primaryContainer,
          child: Icon(
            isCancelled
                ? Icons.cancel_outlined
                : isTopup
                    ? Icons.add_circle_outline
                    : Icons.shopping_bag_outlined,
            size: 20,
            color: isCancelled
                ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                : isTopup
                    ? Colors.green.shade700
                    : theme.colorScheme.primary,
          ),
        ),
        title: Text(
          tx.description,
          style: TextStyle(
            decoration: isCancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${_fmtDate(tx.bookedAt)}  ·  ${tx.bookedBy}'
          '${isCancelled ? '  ·  Storniert' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        trailing: Text(
          (tx.price >= 0 ? '+' : '') + _fmtEur(tx.price),
          style: theme.textTheme.titleMedium?.copyWith(
            color: priceColor,
            decoration: isCancelled ? TextDecoration.lineThrough : null,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _fmtEur(double v) =>
    '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

String _fmtDate(DateTime dt) {
  final local = dt.toLocal();
  final d = '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.'
      '${local.year}';
  final t = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}
