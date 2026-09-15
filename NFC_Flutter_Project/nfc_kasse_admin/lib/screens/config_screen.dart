import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/config_env_file.dart';
import '../services/nfc_kasse_paths.dart';
import '../services/service_control.dart';

/// Structured form for config.env, grouped exactly like the file itself.
/// SECRET_KEY/INSTALLATION_ID are intentionally not editable here — the
/// former would invalidate every session if touched by accident, the latter
/// would invalidate every issued license key; both are shown read-only on
/// the Info screen instead.
class ConfigScreen extends ConsumerStatefulWidget {
  const ConfigScreen({super.key});

  @override
  ConsumerState<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends ConsumerState<ConfigScreen> {
  static const _textKeys = [
    'HOST', 'PORT',
    'EVENT_NAME', 'CHIP_DEPOSIT', 'BAR_CHIP_UID',
    'LEADERBOARD_LICENSE_KEY', 'PAGER_LICENSE_KEY',
    'WEBAPP_ROUTE', 'ALLOWED_ORIGINS',
    'PRINTER_PORT', 'PRINTER_BAUDRATE', 'PRINTER_HOST', 'PRINTER_LINE_WIDTH',
    'BON_FOOTER_TEXT', 'BON_CASHIER_LABEL',
  ];
  static const _boolKeys = [
    'LEADERBOARD', 'PAGER', 'PRINTER_AUTO_CUT',
    'BON_SHOW_EVENT_NAME', 'BON_SHOW_DATETIME', 'BON_SHOW_PRICE', 'BON_SHOW_CASHIER',
  ];

  final _controllers = <String, TextEditingController>{};
  final _bools = <String, bool>{};
  String _printerType = 'serial';
  String _logLevel = 'INFO';
  bool _populated = false;
  bool _saving = false;

  void _populate(ConfigEnvFile env) {
    if (_populated) return;
    for (final key in _textKeys) {
      _controllers[key] = TextEditingController(text: env.values[key] ?? '');
    }
    for (final key in _boolKeys) {
      _bools[key] = (env.values[key] ?? 'false').trim().toLowerCase() == 'true';
    }
    _printerType = env.values['PRINTER_TYPE'] ?? 'serial';
    _logLevel = env.values['LOG_LEVEL'] ?? 'INFO';
    _populated = true;
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({required bool restart}) async {
    setState(() => _saving = true);
    final updates = <String, String>{
      for (final key in _textKeys) key: _controllers[key]!.text.trim(),
      for (final key in _boolKeys) key: _bools[key]!.toString(),
      'PRINTER_TYPE': _printerType,
      'LOG_LEVEL': _logLevel,
    };
    final env = await ConfigEnvFile.load(NfcKassePaths.configEnvPath);
    await env.save(NfcKassePaths.configEnvPath, updates);
    if (restart) await ServiceControl.restart();
    if (!mounted) return;
    ref.read(configRefreshProvider.notifier).state++;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(restart
          ? 'Gespeichert, Dienst wird neu gestartet …'
          : 'Gespeichert — Neustart nötig, damit die Änderungen wirken.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final envAsync = ref.watch(configEnvProvider);
    final theme = Theme.of(context);

    return envAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('config.env konnte nicht gelesen werden: $e')),
      data: (env) {
        _populate(env);
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Konfiguration', style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 20),
                    const _SectionHeader('Netzwerk'),
                    _TextRow('Netzwerkschnittstelle (HOST)', _controllers['HOST']!),
                    _TextRow('Port', _controllers['PORT']!, keyboardType: TextInputType.number),

                    const _SectionHeader('Veranstaltung'),
                    _TextRow('Name der Veranstaltung', _controllers['EVENT_NAME']!),
                    _TextRow('Chip-Pfand (€)', _controllers['CHIP_DEPOSIT']!, keyboardType: TextInputType.number),
                    _TextRow('Virtuelle Bar-Chip-UID', _controllers['BAR_CHIP_UID']!),

                    const _SectionHeader('Kostenpflichtige Zusatz-Features'),
                    _SwitchRow(
                      'Leaderboard aktiviert',
                      value: _bools['LEADERBOARD']!,
                      onChanged: (v) => setState(() => _bools['LEADERBOARD'] = v),
                    ),
                    _TextRow('Leaderboard-Lizenzschlüssel', _controllers['LEADERBOARD_LICENSE_KEY']!),
                    _SwitchRow(
                      'Pager aktiviert',
                      value: _bools['PAGER']!,
                      onChanged: (v) => setState(() => _bools['PAGER'] = v),
                    ),
                    _TextRow('Pager-Lizenzschlüssel', _controllers['PAGER_LICENSE_KEY']!),

                    const _SectionHeader('Web-Zugriff'),
                    _TextRow('Webapp-Pfad', _controllers['WEBAPP_ROUTE']!),
                    _TextRow('Erlaubte Herkunfts-Adressen (CORS)', _controllers['ALLOWED_ORIGINS']!),
                    _DropdownRow(
                      'Protokoll-Level',
                      value: _logLevel,
                      options: const ['TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'FATAL'],
                      onChanged: (v) => setState(() => _logLevel = v),
                    ),

                    const _SectionHeader('Bondrucker'),
                    _DropdownRow(
                      'Anschlussart',
                      value: _printerType,
                      options: const ['serial', 'network'],
                      onChanged: (v) => setState(() => _printerType = v),
                    ),
                    _TextRow(
                      _printerType == 'network' ? 'TCP-Port' : 'COM-Port',
                      _controllers['PRINTER_PORT']!,
                    ),
                    if (_printerType != 'network')
                      _TextRow('Baudrate', _controllers['PRINTER_BAUDRATE']!, keyboardType: TextInputType.number),
                    if (_printerType == 'network')
                      _TextRow('Drucker-IP-Adresse', _controllers['PRINTER_HOST']!),
                    _TextRow('Zeichen pro Zeile', _controllers['PRINTER_LINE_WIDTH']!, keyboardType: TextInputType.number),
                    _SwitchRow(
                      'Bon automatisch abschneiden',
                      value: _bools['PRINTER_AUTO_CUT']!,
                      onChanged: (v) => setState(() => _bools['PRINTER_AUTO_CUT'] = v),
                    ),

                    const _SectionHeader('Bon-Inhalt'),
                    _SwitchRow(
                      'Veranstaltungsname anzeigen',
                      value: _bools['BON_SHOW_EVENT_NAME']!,
                      onChanged: (v) => setState(() => _bools['BON_SHOW_EVENT_NAME'] = v),
                    ),
                    _SwitchRow(
                      'Datum + Uhrzeit anzeigen',
                      value: _bools['BON_SHOW_DATETIME']!,
                      onChanged: (v) => setState(() => _bools['BON_SHOW_DATETIME'] = v),
                    ),
                    _SwitchRow(
                      'Preis anzeigen',
                      value: _bools['BON_SHOW_PRICE']!,
                      onChanged: (v) => setState(() => _bools['BON_SHOW_PRICE'] = v),
                    ),
                    _TextRow('Fußzeilentext', _controllers['BON_FOOTER_TEXT']!),
                    _SwitchRow(
                      'Kassierer anzeigen',
                      value: _bools['BON_SHOW_CASHIER']!,
                      onChanged: (v) => setState(() => _bools['BON_SHOW_CASHIER'] = v),
                    ),
                    _TextRow('Kassierer-Bezeichnung', _controllers['BON_CASHIER_LABEL']!),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => _save(restart: false),
                    child: const Text('Speichern'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(restart: true),
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Speichern & Dienst neu starten'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Divider(),
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _TextRow(this.label, this.controller, {this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow(this.label, {required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _DropdownRow(this.label, {required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
