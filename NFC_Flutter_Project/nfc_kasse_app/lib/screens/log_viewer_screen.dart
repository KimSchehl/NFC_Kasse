import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_models.dart';
import '../providers/providers.dart';
import '../services/app_logger.dart';
import '../utils/formatters.dart';

const _levelOptions = ['TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL'];

Color _levelColor(BuildContext context, String level) {
  final cs = Theme.of(context).colorScheme;
  switch (level) {
    case 'TRACE':
    case 'DEBUG':
      return cs.onSurfaceVariant;
    case 'INFO':
      return cs.primary;
    case 'WARNING':
      return Colors.orange;
    case 'ERROR':
    case 'FATAL':
      return cs.error;
    default:
      return cs.onSurface;
  }
}

String _fmtTs(String iso) {
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(dt.day)}.${p2(dt.month)}. ${p2(dt.hour)}:${p2(dt.minute)}:${p2(dt.second)}';
}

final _devicesProvider = FutureProvider.autoDispose<List<LogDeviceInfo>>((ref) {
  return ref.read(logsServiceProvider).getDevices();
});

/// Log viewer — gated by `logs.view`. Tab 1 ("Protokoll") is a filterable
/// list spanning server and shipped client entries; Tab 2 ("Geräte"), only
/// shown to holders of the stricter `logs.configure`, lists known devices
/// (including the synthetic server entry) with a per-device level override.
class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen>
    with SingleTickerProviderStateMixin {
  late final bool _canConfigure;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _canConfigure = ref.read(authProvider).valueOrNull?.canConfigureLogs ?? false;
    _tab = TabController(length: _canConfigure ? 2 : 1, vsync: this);
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
        Container(
          color: theme.colorScheme.surfaceContainerHigh,
          child: TabBar(
            controller: _tab,
            tabs: [
              const Tab(icon: Icon(Icons.article_outlined), text: 'Protokoll'),
              if (_canConfigure)
                const Tab(icon: Icon(Icons.devices_other_outlined), text: 'Geräte'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              const _LogListTab(),
              if (_canConfigure) const _DevicesTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Protokoll
// ---------------------------------------------------------------------------

class _LogListTab extends ConsumerStatefulWidget {
  const _LogListTab();

  @override
  ConsumerState<_LogListTab> createState() => _LogListTabState();
}

class _LogListTabState extends ConsumerState<_LogListTab> {
  String? _level;
  String? _origin;
  String? _deviceId;
  final _traceCtrl = TextEditingController();
  final _qCtrl = TextEditingController();
  Timer? _debounce;

  List<LogEntry> _items = [];
  bool _hasMore = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _traceCtrl.dispose();
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    setState(() {
      _loading = true;
      if (!append) _error = null;
    });
    try {
      final result = await ref.read(logsServiceProvider).query(
            level: _level,
            origin: _origin,
            deviceId: _deviceId,
            traceId: _traceCtrl.text.trim(),
            q: _qCtrl.text.trim(),
            limit: 200,
            offset: append ? _items.length : 0,
          );
      if (!mounted) return;
      setState(() {
        _items = append ? [..._items, ...result.items] : result.items;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(e);
        _loading = false;
      });
    }
  }

  void _debouncedReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load());
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(_devicesProvider).valueOrNull ?? const [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String?>(
                value: _level,
                hint: const Text('Min-Level'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Alle Level')),
                  for (final l in _levelOptions)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) {
                  AppLogger.trace('Log-Filter Level geändert: $v', logger: 'ui.logs');
                  setState(() => _level = v);
                  _load();
                },
              ),
              DropdownButton<String?>(
                value: _origin,
                hint: const Text('Herkunft'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Server + Client')),
                  DropdownMenuItem(value: 'server', child: Text('Nur Server')),
                  DropdownMenuItem(value: 'client', child: Text('Nur Client')),
                ],
                onChanged: (v) {
                  AppLogger.trace('Log-Filter Herkunft geändert: $v', logger: 'ui.logs');
                  setState(() => _origin = v);
                  _load();
                },
              ),
              DropdownButton<String?>(
                value: _deviceId,
                hint: const Text('Gerät'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Alle Geräte')),
                  for (final d in devices)
                    DropdownMenuItem(value: d.deviceId, child: Text(d.displayLabel)),
                ],
                onChanged: (v) {
                  AppLogger.trace('Log-Filter Gerät geändert: $v', logger: 'ui.logs');
                  setState(() => _deviceId = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        // Trace-ID is the primary end-to-end debugging tool (client entry
        // <-> matching server entry via the shared X-Trace-Id header), so it
        // gets its own full-width, prominently placed field.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _traceCtrl,
            decoration: InputDecoration(
              labelText: 'Trace-ID',
              hintText: 'Exakte Trace-ID für Ende-zu-Ende-Korrelation',
              prefixIcon: const Icon(Icons.link, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _traceCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _traceCtrl.clear();
                        _load();
                      },
                    )
                  : null,
            ),
            onChanged: (_) => _debouncedReload(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _qCtrl,
            decoration: InputDecoration(
              labelText: 'Volltextsuche',
              hintText: 'Suche in der Nachricht',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _qCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _qCtrl.clear();
                        _load();
                      },
                    )
                  : null,
            ),
            onChanged: (_) => _debouncedReload(),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null && _items.isEmpty
              ? Center(child: Text('Fehler: $_error'))
              : _items.isEmpty && !_loading
                  ? const Center(child: Text('Keine Einträge'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : TextButton(
                                      onPressed: () {
                                        AppLogger.trace('"Mehr laden" geklickt', logger: 'ui.logs');
                                        _load(append: true);
                                      },
                                      child: const Text('Mehr laden'),
                                    ),
                            ),
                          );
                        }
                        return _LogEntryTile(entry: _items[i]);
                      },
                    ),
        ),
      ],
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _levelColor(context, entry.level);
    return ListTile(
      dense: true,
      leading: Container(width: 4, height: 36, color: color),
      title: Text(entry.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          _fmtTs(entry.ts),
          entry.level,
          entry.logger,
          if (entry.origin == 'client') entry.deviceId ?? 'client',
          if (entry.username != null) entry.username!,
        ].join('  ·  '),
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _LogEntryDialog(entry: entry),
      ),
    );
  }
}

class _LogEntryDialog extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryDialog({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        );

    return AlertDialog(
      title: Text(entry.level, style: TextStyle(color: _levelColor(context, entry.level))),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(entry.message),
            const SizedBox(height: 12),
            row('Zeit', _fmtTs(entry.ts)),
            row('Logger', entry.logger),
            row('Herkunft', entry.origin),
            if (entry.deviceId != null) row('Gerät', entry.deviceId!),
            if (entry.username != null) row('Benutzer', entry.username!),
            if (entry.path != null) row('Pfad', '${entry.method ?? ''} ${entry.path}'.trim()),
            if (entry.statusCode != null) row('Status', '${entry.statusCode}'),
            if (entry.traceId != null) row('Trace-ID', entry.traceId!),
            if (entry.exception != null && entry.exception!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                entry.exception!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Geräte
// ---------------------------------------------------------------------------

class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(_devicesProvider);
    return devicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: ${formatApiError(e)}')),
      data: (devices) {
        if (devices.isEmpty) return const Center(child: Text('Keine Geräte bekannt'));
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_devicesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: devices.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) => _DeviceTile(device: devices[i]),
          ),
        );
      },
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  final LogDeviceInfo device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        device.isServer ? Icons.dns_outlined : Icons.smartphone_outlined,
        color: device.online ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(device.displayLabel),
      subtitle: Text([
        if (device.platform != null) device.platform!,
        device.online ? 'online' : 'offline',
        if (device.lastSeenAt != null) _fmtTs(device.lastSeenAt!),
      ].join('  ·  ')),
      trailing: DropdownButton<String?>(
        value: device.forcedLevel,
        hint: const Text('Automatisch'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Automatisch')),
          for (final l in _levelOptions) DropdownMenuItem(value: l, child: Text(l)),
        ],
        onChanged: (v) async {
          AppLogger.trace(
            'Geräte-Log-Level geändert: ${device.deviceId} -> $v',
            logger: 'ui.logs',
          );
          try {
            await ref.read(logsServiceProvider).setDeviceLevel(device.deviceId, v);
            ref.invalidate(_devicesProvider);
          } catch (_) {
            // Non-fatal: the dropdown simply reverts to the prior value on
            // the next rebuild since the underlying data never changed.
          }
        },
      ),
    );
  }
}
