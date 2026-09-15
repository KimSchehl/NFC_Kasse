import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers/providers.dart';
import '../services/nfc_kasse_paths.dart';

class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final envAsync = ref.watch(configEnvProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Info', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => _InfoRow(
              'Verwaltungstool-Version',
              snapshot.data?.version ?? '…',
            ),
          ),
          envAsync.when(
            loading: () => const _InfoRow('Installations-ID', '…'),
            error: (_, _) => const _InfoRow('Installations-ID', 'nicht lesbar'),
            data: (env) => _InfoRow(
              'Installations-ID',
              env.values['INSTALLATION_ID'] ?? 'nicht gefunden',
              copyable: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Wird für die Anforderung von Lizenzschlüsseln (Pager, Leaderboard) benötigt.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Divider(height: 40),
          _InfoRow('Programmordner', NfcKassePaths.installDir, copyable: true),
          _InfoRow('Datenordner', NfcKassePaths.dataDir, copyable: true),
          _InfoRow('Protokolle', NfcKassePaths.logsDir, copyable: true),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _InfoRow(this.label, this.value, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 200,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Kopieren',
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
        ],
      ),
    );
  }
}
