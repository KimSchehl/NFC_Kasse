import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/backend_cli.dart';
import '../services/config_env_file.dart';
import '../services/license_service.dart';
import '../services/nfc_kasse_paths.dart';
import '../services/service_control.dart';

/// Lizenzen: die Hauptlizenz der Kasse (ohne sie startet der Dienst nicht)
/// und die Zusatzfunktionen Pager und Leaderboard. Jeder Schlüssel wird
/// gleich geprüft — gültig, abgelaufen, für eine andere Installation oder
/// ungültig —, mit derselben Prüfung wie im Dienst.
class LicensesScreen extends ConsumerStatefulWidget {
  const LicensesScreen({super.key});

  @override
  ConsumerState<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends ConsumerState<LicensesScreen> {
  // feature (wie im Backend) → config.env-Schlüssel
  static const _keys = {
    'kasse': 'LICENSE_KEY',
    'pager': 'PAGER_LICENSE_KEY',
    'leaderboard': 'LEADERBOARD_LICENSE_KEY',
  };

  final _controllers = {for (final f in _keys.keys) f: TextEditingController()};
  bool _pager = false;
  bool _leaderboard = false;
  String _installationId = '';
  Map<String, LicenseStatus> _status = {};
  bool _populated = false;
  bool _busy = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _populate(ConfigEnvFile env) {
    if (_populated) return;
    _populated = true;
    for (final e in _keys.entries) {
      _controllers[e.key]!.text = env.values[e.value] ?? '';
    }
    _pager = (env.values['PAGER'] ?? 'false').toLowerCase() == 'true';
    _leaderboard = (env.values['LEADERBOARD'] ?? 'false').toLowerCase() == 'true';
    _installationId = env.values['INSTALLATION_ID'] ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  /// Beim Tippen erst prüfen, wenn kurz Ruhe ist — jede Prüfung startet
  /// NfcKasseBackend.exe.
  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _check);
  }

  Future<void> _check() async {
    try {
      final status = await LicenseService.check({
        for (final f in _keys.keys) f: _controllers[f]!.text.trim(),
      });
      if (mounted) setState(() => _status = status);
    } on BackendCliException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _save({required bool restart}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final env = await ConfigEnvFile.load(NfcKassePaths.configEnvPath);
      await env.save(NfcKassePaths.configEnvPath, {
        for (final e in _keys.entries) e.value: _controllers[e.key]!.text.trim(),
        'PAGER': '$_pager',
        'LEADERBOARD': '$_leaderboard',
      });
      await _check();
      if (restart) await ServiceControl.restart();
      ref.read(configRefreshProvider.notifier).state++;
      final mainOk = _status['kasse']?.valid ?? false;
      messenger.showSnackBar(SnackBar(
        content: Text(!mainOk
            ? 'Gespeichert. Ohne gültige Hauptlizenz startet der Dienst nicht.'
            : restart
                ? 'Gespeichert, Dienst wird neu gestartet …'
                : 'Gespeichert — Neustart nötig, damit die Änderungen wirken.'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Lizenzen', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Jeder Schlüssel gilt nur für diese Installation. Für einen Schlüssel die '
                    'Installations-ID an kontakt@nfc-kasse.de schicken.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: SelectableText('Installations-ID: $_installationId')),
                      IconButton(
                        tooltip: 'Kopieren',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: _installationId)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _LicenseCard(
                    title: 'Kasse (Hauptlizenz)',
                    hint: 'Ohne gültige Hauptlizenz startet der Dienst nicht.',
                    controller: _controllers['kasse']!,
                    status: _status['kasse'],
                    onChanged: _scheduleCheck,
                  ),
                  _LicenseCard(
                    title: 'Pager',
                    controller: _controllers['pager']!,
                    status: _status['pager'],
                    onChanged: _scheduleCheck,
                    enabled: _pager,
                    onEnabledChanged: (v) => setState(() => _pager = v),
                  ),
                  _LicenseCard(
                    title: 'Leaderboard',
                    controller: _controllers['leaderboard']!,
                    status: _status['leaderboard'],
                    onChanged: _scheduleCheck,
                    enabled: _leaderboard,
                    onEnabledChanged: (v) => setState(() => _leaderboard = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _save(restart: false),
                    child: const Text('Speichern'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => _save(restart: true),
                    child: const Text('Speichern & Dienst neu starten'),
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

class _LicenseCard extends StatelessWidget {
  final String title;
  final String? hint;
  final TextEditingController controller;
  final LicenseStatus? status;
  final VoidCallback onChanged;

  /// null = immer aktiv (Hauptlizenz), sonst der Schalter „… aktiviert“.
  final bool? enabled;
  final ValueChanged<bool>? onEnabledChanged;

  const _LicenseCard({
    required this.title,
    this.hint,
    required this.controller,
    required this.status,
    required this.onChanged,
    this.enabled,
    this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status;
    final color = s == null
        ? theme.colorScheme.outline
        : s.valid
            ? Colors.green.shade700
            : theme.colorScheme.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (enabled != null) ...[
                  Text('aktiviert', style: theme.textTheme.labelMedium),
                  Switch(value: enabled!, onChanged: onEnabledChanged),
                ],
              ],
            ),
            if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Lizenzschlüssel', isDense: true),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(s == null ? Icons.hourglass_empty : (s.valid ? Icons.check_circle : Icons.error),
                    size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s == null
                        ? 'Wird geprüft …'
                        : (enabled == false && s.valid ? '${s.label} — Funktion ist ausgeschaltet' : s.label),
                    style: TextStyle(color: color),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
