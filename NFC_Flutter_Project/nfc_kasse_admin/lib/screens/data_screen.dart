import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/backup_service.dart';

const _confirmWord = 'WIEDERHERSTELLEN';
const _sqliteType = XTypeGroup(label: 'NFC-Kasse Sicherung', extensions: ['db']);

String _two(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year}  ${_two(d.hour)}:${_two(d.minute)}';

IconData _kindIcon(String kind) => switch (kind) {
      'kasse' => Icons.restart_alt,
      'manuell' => Icons.person_outline,
      'vor-wiederherstellung' || 'vor-reset' || 'vor-festwechsel' => Icons.shield_outlined,
      _ => Icons.backup_outlined,
    };

/// Sicherungen der Datenbank: jetzt sichern, wiederherstellen, exportieren
/// und importieren. Alle Schreibaktionen laufen über BackupService.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends ConsumerState<DataScreen> {
  String? _busyText;

  bool get _busy => _busyText != null;

  void _refresh() => ref.read(backupRefreshProvider.notifier).state++;

  Future<void> _guard(String busyText, Future<void> Function() task, String doneText) async {
    setState(() => _busyText = busyText);
    try {
      await task();
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneText)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _busyText = null);
    }
  }

  Future<String?> _askLabel() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sicherung erstellen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Bezeichnung (optional)',
            hintText: 'z. B. vor Sommerfest',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Sichern')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirmTyped({required String title, required String body}) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final matches = controller.text.trim() == _confirmWord;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  onChanged: (_) => setDialog(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Zur Bestätigung $_confirmWord eingeben',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              FilledButton(
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Wiederherstellen'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  Future<void> _createBackup() async {
    final label = await _askLabel();
    if (label == null) return;
    await _guard(
      'Sicherung wird erstellt …',
      () => BackupService.create(label: label),
      'Sicherung erstellt.',
    );
  }

  Future<void> _restore(BackupEntry entry) async {
    final confirmed = await _confirmTyped(
      title: 'Datenbank wiederherstellen?',
      body: 'Der aktuelle Stand wird durch „${entry.label ?? entry.kindLabel}“ '
          '(${_formatDate(entry.modified)}) ersetzt. Chips, Guthaben, Feste und Buchungen '
          'werden auf diesen Stand zurückgesetzt. Vorher wird der aktuelle Stand automatisch '
          'gesichert. Der Dienst wird dafür kurz gestoppt.',
    );
    if (!confirmed) return;
    await _guard(
      'Wiederherstellung läuft, der Dienst wird kurz angehalten …',
      () => BackupService.restore(entry.path),
      'Wiederhergestellt. Der Dienst läuft wieder.',
    );
  }

  Future<void> _export(BackupEntry entry) async {
    final location = await getSaveLocation(
      suggestedName: entry.fileName,
      acceptedTypeGroups: const [_sqliteType],
    );
    if (location == null) return;
    final path = location.path.toLowerCase().endsWith('.db') ? location.path : '${location.path}.db';
    await _guard(
      'Export läuft …',
      () => BackupService.export(entry, path),
      'Sicherung exportiert nach $path',
    );
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [_sqliteType]);
    if (file == null) return;
    final confirmed = await _confirmTyped(
      title: 'Sicherung importieren?',
      body: 'Die Datenbank wird durch „${file.name}“ ersetzt. Vorher wird der aktuelle Stand '
          'automatisch gesichert. Der Dienst wird dafür kurz gestoppt.',
    );
    if (!confirmed) return;
    await _guard(
      'Import läuft, der Dienst wird kurz angehalten …',
      () => BackupService.importFrom(file.path),
      'Sicherung importiert. Der Dienst läuft wieder.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backupsAsync = ref.watch(backupsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Datensicherung', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Sicherungen enthalten alles: alle Feste, Artikel, Benutzer, Buchungen und das '
            'Guthaben aller Chips. Beim Wiederherstellen wird vorher automatisch eine '
            'Sicherung des aktuellen Stands angelegt.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _createBackup,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Jetzt sichern'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Sicherung importieren'),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_busyText!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 24),
          Text('Vorhandene Sicherungen', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Expanded(
            child: backupsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Sicherungen konnten nicht gelesen werden: $e',
                  style: TextStyle(color: theme.colorScheme.error)),
              data: (entries) {
                if (entries.isEmpty) {
                  return const Text('Noch keine Sicherungen vorhanden.');
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _BackupTile(
                    entry: entries[i],
                    enabled: !_busy,
                    onRestore: () => _restore(entries[i]),
                    onExport: () => _export(entries[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  final BackupEntry entry;
  final bool enabled;
  final VoidCallback onRestore;
  final VoidCallback onExport;

  const _BackupTile({
    required this.entry,
    required this.enabled,
    required this.onRestore,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (entry.eventNames.isNotEmpty) 'Feste: ${entry.eventNames.join(', ')}',
      if (entry.customers != null) '${entry.customers} Kunden-Chips',
      if (entry.sales != null) '${entry.sales} Buchungen',
    ].join('  ·  ');

    return Card(
      child: ListTile(
        leading: Icon(_kindIcon(entry.kind)),
        title: Text('${_formatDate(entry.modified)}  ·  ${entry.label ?? entry.kindLabel}'),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Exportieren',
              icon: const Icon(Icons.save_alt),
              onPressed: enabled ? onExport : null,
            ),
            IconButton(
              tooltip: 'Wiederherstellen',
              icon: const Icon(Icons.settings_backup_restore),
              onPressed: enabled ? onRestore : null,
            ),
          ],
        ),
      ),
    );
  }
}
