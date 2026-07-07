import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/kiosk_models.dart';
import '../providers/providers.dart';
import '../services/nfc_service.dart';
import '../utils/formatters.dart';

/// Self-service kiosk screen shown when the logged-in user has 'kiosk.access'.
///
/// Flow:
///   Idle → tap NFC chip → Loading → Result (shows balance + all transactions)
///        → auto-reset after 60 s back to Idle
///   Hidden logout: tap the storefront icon in the header 5× within 2 s.
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

  final _uidController = TextEditingController();
  final _uidFocus = FocusNode();

  static const _resetAfter = Duration(minutes: 1);

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

  void _submitUid(String raw) {
    final trimmed = raw.replaceAll(RegExp(r'[\r\n]'), '').trim();
    if (trimmed.isEmpty) return;
    _uidController.clear();
    _loadChip(trimmed);
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
    _uidController.clear();
    setState(() {
      _state = _KioskState.idle;
      _info = null;
      _errorMsg = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _uidFocus.requestFocus());
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _uidController.dispose();
    _uidFocus.dispose();
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
                _KioskState.idle => _IdleView(
                    nfcAvailable: _nfcAvailable,
                    controller: _uidController,
                    focusNode: _uidFocus,
                    onSubmit: _submitUid,
                  ),
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
// Header — tap the icon 5× to log out (hidden gesture)
// ---------------------------------------------------------------------------

class _Header extends StatefulWidget {
  final String username;
  final VoidCallback onLogout;

  const _Header({required this.username, required this.onLogout});

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  int _taps = 0;
  Timer? _tapReset;

  void _onIconTap() {
    _tapReset?.cancel();
    _taps++;
    if (_taps >= 5) {
      _taps = 0;
      widget.onLogout();
      return;
    }
    // Reset counter if no further tap within 2 seconds
    _tapReset = Timer(const Duration(seconds: 2), () => _taps = 0);
  }

  @override
  void dispose() {
    _tapReset?.cancel();
    super.dispose();
  }

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
          GestureDetector(
            onTap: _onIconTap,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.storefront, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            widget.username,
            style: theme.textTheme.titleMedium,
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
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onSubmit;

  const _IdleView({
    required this.nfcAvailable,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  void _onChanged(String value) {
    if (value.endsWith('\n') || value.endsWith('\r')) {
      onSubmit(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Center(
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
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'UID eingeben oder USB-Lesegerät verwenden …',
              prefixIcon: Icon(
                nfcAvailable ? Icons.nfc : Icons.usb,
                color: nfcAvailable ? theme.colorScheme.primary : null,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: () => onSubmit(controller.text),
                tooltip: 'Laden',
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Fa-f0-9:\- \r\n]')),
            ],
            onChanged: _onChanged,
            onSubmitted: onSubmit,
          ),
        ),
      ],
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

class _ResultView extends ConsumerStatefulWidget {
  final KioskChipInfo info;
  final VoidCallback onReset;
  final Duration resetDuration;

  const _ResultView({
    required this.info,
    required this.onReset,
    required this.resetDuration,
  });

  @override
  ConsumerState<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends ConsumerState<_ResultView>
    with SingleTickerProviderStateMixin {
  late AnimationController _progress;
  String? _customerName;

  @override
  void initState() {
    super.initState();
    _customerName = widget.info.customerName;
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

  Future<void> _editName() async {
    _progress.stop();
    final ctrl = TextEditingController(text: _customerName ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chip benennen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: 'Name eingeben …',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          if (_customerName != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Name entfernen'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _progress.forward();
    if (result == null) return; // cancelled
    try {
      await ref.read(kioskServiceProvider).setChipName(widget.info.nfcUid, result);
      setState(() => _customerName = result.isEmpty ? null : result);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    final balance = info.balance;
    final isNegative = balance < 0;
    final onCardColor = isNegative
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onPrimaryContainer;

    return Column(
      children: [
        // Balance card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
          color: isNegative
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.primaryContainer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktuelles Guthaben',
                      style: theme.textTheme.labelLarge?.copyWith(color: onCardColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _fmtEur(balance),
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: onCardColor,
                      ),
                    ),
                    if (_customerName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _customerName!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: onCardColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                    if (info.transactions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Noch keine Buchungen',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onCardColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Name-Edit-Button top-right
              IconButton(
                onPressed: _editName,
                icon: Icon(
                  _customerName != null ? Icons.badge : Icons.badge_outlined,
                  color: onCardColor.withValues(alpha: 0.7),
                ),
                tooltip: _customerName != null ? 'Name bearbeiten' : 'Name vergeben',
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
            height: 56,
            child: OutlinedButton(
              onPressed: widget.onReset,
              style: OutlinedButton.styleFrom(
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
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
