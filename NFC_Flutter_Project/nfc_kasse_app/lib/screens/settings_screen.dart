import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
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
            tabs: const [
              Tab(icon: Icon(Icons.info_outline), text: 'Über'),
              Tab(icon: Icon(Icons.palette_outlined), text: 'Design'),
              Tab(icon: Icon(Icons.bluetooth), text: 'NFC-Lesegerät'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _UeberTab(),
              _DesignTab(),
              _BleTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Über
// ---------------------------------------------------------------------------

class _UeberTab extends ConsumerWidget {
  const _UeberTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serverUrl = ref.watch(serverUrlProvider);
    final downloadUrl = '$serverUrl/download';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server'),
                subtitle: Text(serverUrl),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                subtitle: Text(
                  ref.watch(appVersionProvider).valueOrNull ?? '…',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Abmelden',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Abmelden?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Abmelden'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(authProvider.notifier).logout();
              }
            },
          ),
        ),
        const SizedBox(height: 32),
        Column(
          children: [
            Text(
              'App auf neuem Gerät installieren',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'QR-Code scannen → APK herunterladen',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: downloadUrl,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              downloadUrl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Design
// ---------------------------------------------------------------------------

class _DesignTab extends ConsumerWidget {
  const _DesignTab();

  // (label, textScale, gridColumns, cartTextScale, buttonMaxLines)
  static const _presets = [
    ('Klein',    0.85, 4, 0.85, 2),
    ('Standard', 1.0,  3, 1.0,  2),
    ('Groß',     1.2,  2, 1.1,  3),
  ];

  bool _presetActive(
    double ts, int gc, double cts, int bml,
    double pts, int pgc, double pcts, int pbml,
  ) =>
      (ts - pts).abs() < 0.01 &&
      gc == pgc &&
      (cts - pcts).abs() < 0.01 &&
      bml == pbml;

  Future<void> _applyPreset(
      WidgetRef ref, double ts, int gc, double cts, int bml) async {
    ref.read(textScaleProvider.notifier).state = ts;
    ref.read(gridColumnsProvider.notifier).state = gc;
    ref.read(cartTextScaleProvider.notifier).state = cts;
    ref.read(buttonMaxLinesProvider.notifier).state = bml;
    final s = ref.read(storageProvider);
    await s.write(key: 'display_textScale', value: ts.toString());
    await s.write(key: 'display_gridColumns', value: gc.toString());
    await s.write(key: 'display_cartTextScale', value: cts.toString());
    await s.write(key: 'display_buttonMaxLines', value: bml.toString());
  }

  Future<void> _saveDouble(
      WidgetRef ref, StateProvider<double> p, String key, double v) async {
    ref.read(p.notifier).state = v;
    await ref.read(storageProvider).write(key: key, value: v.toString());
  }

  Future<void> _saveInt(
      WidgetRef ref, StateProvider<int> p, String key, int v) async {
    ref.read(p.notifier).state = v;
    await ref.read(storageProvider).write(key: key, value: v.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ts  = ref.watch(textScaleProvider);
    final gc  = ref.watch(gridColumnsProvider);
    final cts = ref.watch(cartTextScaleProvider);
    final bml = ref.watch(buttonMaxLinesProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [

        // ── Voreinstellungen ──────────────────────────────────────────────
        _SectionHeader('Voreinstellungen'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (label, pts, pgc, pcts, pbml) in _presets) ...[
              Expanded(
                child: _presetActive(ts, gc, cts, bml, pts, pgc, pcts, pbml)
                    ? FilledButton(
                        onPressed: () =>
                            _applyPreset(ref, pts, pgc, pcts, pbml),
                        child: Text(label),
                      )
                    : OutlinedButton(
                        onPressed: () =>
                            _applyPreset(ref, pts, pgc, pcts, pbml),
                        child: Text(label),
                      ),
              ),
              if (label != 'Groß') const SizedBox(width: 8),
            ],
          ],
        ),

        const SizedBox(height: 28),

        // ── Allgemein ─────────────────────────────────────────────────────
        _SectionHeader('Allgemein'),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Schriftgröße',
          value: ts,
          displayText: '${(ts * 100).round()}%',
          min: 0.75,
          max: 1.4,
          divisions: 13,
          onChanged: (v) => ref.read(textScaleProvider.notifier).state = v,
          onChangeEnd: (v) => _saveDouble(
              ref, textScaleProvider, 'display_textScale', v),
        ),

        const SizedBox(height: 24),

        // ── Produktbereich ────────────────────────────────────────────────
        _SectionHeader('Produktbereich'),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Spalten',
          value: gc.toDouble(),
          displayText: '$gc',
          min: 2,
          max: 5,
          divisions: 3,
          onChanged: (v) =>
              ref.read(gridColumnsProvider.notifier).state = v.round(),
          onChangeEnd: (v) => _saveInt(
              ref, gridColumnsProvider, 'display_gridColumns', v.round()),
        ),
        const SizedBox(height: 16),
        // Number field for max text lines per button
        Row(
          children: [
            Expanded(
              child: Text('Button-Textzeilen',
                  style: theme.textTheme.bodyMedium),
            ),
            _Stepper(
              value: bml,
              min: 1,
              max: 4,
              onChanged: (v) => _saveInt(
                  ref, buttonMaxLinesProvider, 'display_buttonMaxLines', v),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // ── Warenkorb ─────────────────────────────────────────────────────
        _SectionHeader('Warenkorb'),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Schriftgröße',
          value: cts,
          displayText: '${(cts * 100).round()}%',
          min: 0.75,
          max: 1.4,
          divisions: 13,
          onChanged: (v) =>
              ref.read(cartTextScaleProvider.notifier).state = v,
          onChangeEnd: (v) => _saveDouble(
              ref, cartTextScaleProvider, 'display_cartTextScale', v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — NFC-Lesegerät (BLE)
// ---------------------------------------------------------------------------

class _BleTab extends ConsumerWidget {
  const _BleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleReaderProvider);
    final notifier = ref.read(bleReaderProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Gekoppeltes Lesegerät'),
        const SizedBox(height: 10),
        if (ble.isPaired)
          Card(
            child: ListTile(
              leading: Icon(
                ble.isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: ble.isConnected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              title: Text(ble.deviceName?.isNotEmpty == true
                  ? ble.deviceName!
                  : ble.deviceId ?? 'Unbekanntes Gerät'),
              subtitle: Text(switch (ble.status) {
                BleReaderStatus.connecting => 'Verbinde…',
                BleReaderStatus.connected =>
                  'Verbunden${ble.batteryPercent != null ? ' · Akku ${ble.batteryPercent}%' : ''}',
                BleReaderStatus.disconnected => 'Getrennt',
              }),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'reconnect':
                      // Web Bluetooth can't resolve a bare remoteId back to a
                      // connectable device outside of its own requestDevice()
                      // picker (see _restoreSavedDevice in providers.dart) -
                      // kick off a scan instead, which re-triggers that
                      // picker; Android can reconnect by id directly.
                      if (kIsWeb) {
                        notifier.startScan();
                      } else {
                        notifier.connect(BluetoothDevice.fromId(ble.deviceId!));
                      }
                    case 'disconnect':
                      notifier.disconnect();
                    case 'forget':
                      notifier.forget();
                  }
                },
                itemBuilder: (_) => [
                  if (!ble.isConnected)
                    const PopupMenuItem(
                        value: 'reconnect', child: Text('Verbinden')),
                  if (ble.isConnected)
                    const PopupMenuItem(
                        value: 'disconnect', child: Text('Trennen')),
                  const PopupMenuItem(
                      value: 'forget', child: Text('Entkoppeln')),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Kein Lesegerät gekoppelt.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _SectionHeader('Neues Gerät suchen'),
        const SizedBox(height: 10),
        const _BleScanList(),
      ],
    );
  }
}

/// Owns the scan lifecycle (start on demand, stop on leaving the tab) and
/// renders live results from the always-on FlutterBluePlus streams.
class _BleScanList extends ConsumerStatefulWidget {
  const _BleScanList();

  @override
  ConsumerState<_BleScanList> createState() => _BleScanListState();
}

class _BleScanListState extends ConsumerState<_BleScanList> {
  // Captured in initState rather than read fresh in dispose(): when the
  // whole SettingsScreen is torn down in one go (e.g. navigating to a
  // different screen swaps it out via main_shell.dart's switch, not an
  // IndexedStack), Riverpod may already consider `ref` invalid by the time
  // this widget's own dispose() runs - ref.read() at that point throws
  // "Cannot use ref after widget was disposed". Calling a method on an
  // already-held Notifier instance needs no `ref` at all, so it stays safe.
  late final BleReaderNotifier _bleNotifier;

  @override
  void initState() {
    super.initState();
    _bleNotifier = ref.read(bleReaderProvider.notifier);
  }

  @override
  void dispose() {
    _bleNotifier.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<bool>(
          stream: FlutterBluePlus.isScanning,
          initialData: false,
          builder: (context, snap) {
            final scanning = snap.data ?? false;
            return OutlinedButton.icon(
              onPressed: scanning
                  ? () => ref.read(bleReaderProvider.notifier).stopScan()
                  : () => ref.read(bleReaderProvider.notifier).startScan(),
              icon: scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(scanning ? 'Suche läuft…' : 'Nach Geräten suchen'),
            );
          },
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<ScanResult>>(
          stream: FlutterBluePlus.scanResults,
          initialData: const [],
          builder: (context, snap) {
            final results = snap.data ?? const [];
            if (results.isEmpty) {
              return Text(
                'Keine Geräte gefunden. Reader muss eingeschaltet und in Reichweite sein.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            }
            return Column(
              children: [
                for (final r in results)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.nfc),
                      title: Text(
                        r.device.platformName.isNotEmpty
                            ? r.device.platformName
                            : r.advertisementData.advName.isNotEmpty
                                ? r.advertisementData.advName
                                : r.device.remoteId.str,
                      ),
                      subtitle: Text('Signal: ${r.rssi} dBm'),
                      onTap: () =>
                          ref.read(bleReaderProvider.notifier).connect(r.device),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final String displayText;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.displayText,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              displayText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: displayText,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          style: IconButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
          ),
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          style: IconButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
