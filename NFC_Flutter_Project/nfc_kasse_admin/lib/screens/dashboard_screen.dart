import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/config_env_file.dart';
import '../services/nfc_kasse_paths.dart';
import '../services/service_control.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _openWebapp() async {
    final env = await ConfigEnvFile.load(NfcKassePaths.configEnvPath);
    final port = env.values['PORT'] ?? '8000';
    final route = env.values['WEBAPP_ROUTE'] ?? '/webapp';
    await Process.run('explorer', ['http://localhost:$port$route']);
  }

  Future<void> _openLogs() => Process.run('explorer', [NfcKassePaths.logsDir]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusAsync = ref.watch(serviceStatusProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dienst-Status', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: statusAsync.when(
                loading: () => const Row(
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Prüfe Status …'),
                  ],
                ),
                error: (e, _) => Text('Status unbekannt: $e', style: TextStyle(color: theme.colorScheme.error)),
                data: (status) => _StatusRow(status: status),
              ),
            ),
          ),
          const SizedBox(height: 20),
          statusAsync.maybeWhen(
            data: (status) => Row(
              children: [
                FilledButton.icon(
                  onPressed: status == ServiceStatus.running ? null : () => ServiceControl.start(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Starten'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: status == ServiceStatus.stopped ? null : () => ServiceControl.stop(),
                  icon: const Icon(Icons.stop),
                  label: const Text('Stoppen'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: status == ServiceStatus.running ? () => ServiceControl.restart() : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Neu starten'),
                ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 32),
          Text('Schnellzugriff', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _openWebapp,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Weboberfläche öffnen'),
              ),
              OutlinedButton.icon(
                onPressed: _openLogs,
                icon: const Icon(Icons.folder_open),
                label: const Text('Protokolle öffnen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final ServiceStatus status;
  const _StatusRow({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = switch (status) {
      ServiceStatus.running => (Colors.green, 'Läuft'),
      ServiceStatus.stopped => (Colors.orange, 'Gestoppt'),
      ServiceStatus.notInstalled => (theme.colorScheme.error, 'Nicht installiert'),
      ServiceStatus.unknown => (theme.colorScheme.outline, 'Unbekannt'),
    };
    return Row(
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Text('NFC-Kasse Backend: $label', style: theme.textTheme.titleMedium),
      ],
    );
  }
}
