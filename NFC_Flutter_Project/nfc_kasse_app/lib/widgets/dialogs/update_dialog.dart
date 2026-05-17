import 'package:flutter/material.dart';

import '../../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService service;

  const UpdateDialog({super.key, required this.info, required this.service});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double? _progress; // null = not started, 0.0–1.0 = in progress
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      await widget.service.downloadAndInstall(
        widget.info.downloadPath,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().toLowerCase();
        final isPermission = msg.contains('permission') || msg.contains('denied');
        setState(() {
          _downloading = false;
          _error = isPermission
              ? 'Installation blockiert.\n\n'
                'Android-Einstellungen öffnen:\n'
                'Apps → NFC Kasse → Unbekannte Apps installieren → Erlauben\n\n'
                'Danach hier erneut tippen.'
              : 'Fehler: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        title: const Text('Update verfügbar'),
        content: _downloading ? _buildProgress() : _buildPrompt(),
        actions: _downloading ? null : _buildActions(),
      ),
    );
  }

  Widget _buildPrompt() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Version ${widget.info.version} ist bereit zum Installieren.'),
        const SizedBox(height: 4),
        const Text(
          'Die App wird kurz geschlossen. Danach bitte den Installer bestätigen.',
          style: TextStyle(fontSize: 12),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildProgress() {
    final pct = _progress == null ? null : (_progress! * 100).toStringAsFixed(0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 12),
        Text(pct != null ? 'Lade herunter … $pct %' : 'Wird vorbereitet …'),
      ],
    );
  }

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Später'),
      ),
      FilledButton.icon(
        onPressed: _startDownload,
        icon: const Icon(Icons.system_update),
        label: const Text('Jetzt aktualisieren'),
      ),
    ];
  }
}
