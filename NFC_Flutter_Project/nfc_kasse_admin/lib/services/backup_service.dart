import 'dart:convert';
import 'dart:io';

import 'backend_cli.dart';
import 'nfc_kasse_paths.dart';
import 'service_control.dart';

class BackupEntry {
  final String fileName;
  final String path;
  final DateTime modified;
  final String kind;
  final String? label;
  final int? customers;
  final int? sales;
  final List<String> eventNames;

  const BackupEntry({
    required this.fileName,
    required this.path,
    required this.modified,
    required this.kind,
    required this.label,
    required this.customers,
    required this.sales,
    required this.eventNames,
  });

  factory BackupEntry.fromFile(String path, DateTime modified, Map<String, dynamic> manifest) {
    final fileName = path.split(r'\').last;
    final events = (manifest['events'] as List?) ?? const [];
    return BackupEntry(
      fileName: fileName,
      path: path,
      modified: modified,
      kind: (manifest['kind'] as String?) ?? fileName.split('_').first,
      label: manifest['label'] as String?,
      customers: manifest['customers'] as int?,
      sales: manifest['sales'] as int?,
      eventNames: [for (final e in events) (e as Map)['name'] as String],
    );
  }

  String get sidecarPath => path.replaceFirst(RegExp(r'\.db$'), '.json');

  String get kindLabel => switch (kind) {
        'kasse' => 'Automatisch beim Start',
        'manuell' => 'Manuell',
        'vor-wiederherstellung' => 'Vor einer Wiederherstellung',
        'vor-reset' => 'Vor einem Reset',
        'vor-festwechsel' => 'Vor einem Festwechsel',
        'vor-update' => 'Vor einem Datenbank-Update',
        'vor-veranstalterwechsel' => 'Vor einem Veranstalterwechsel',
        _ => kind,
      };
}

/// Sicherung, Wiederherstellung, Export und Import der Datenbank. Die
/// eigentliche Arbeit macht der Befehl NfcKasseBackend.exe, damit die Regeln
/// (WAL-sicher, Schema-Prüfung, Rückfall bei Fehlern) nur an einer Stelle
/// stehen.
class BackupService {
  BackupService._();

  static Future<List<BackupEntry>> list() async {
    final dir = Directory(NfcKassePaths.backupsDir);
    if (!await dir.exists()) return const [];

    final entries = <BackupEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.db')) continue;
      var manifest = <String, dynamic>{};
      final sidecar = File(entity.path.replaceFirst(RegExp(r'\.db$'), '.json'));
      if (await sidecar.exists()) {
        try {
          manifest = jsonDecode(await sidecar.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          // Eine unlesbare Beschreibung soll die Liste nicht blockieren.
        }
      }
      entries.add(BackupEntry.fromFile(entity.path, await entity.lastModified(), manifest));
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  static Future<String> create({String? label}) async {
    final trimmed = label?.trim() ?? '';
    final json = await BackendCli.run([
      'backup',
      if (trimmed.isNotEmpty) ...['--label', trimmed],
    ]);
    return json['file'] as String;
  }

  /// Stoppt den Dienst, spielt die Sicherung ein und startet den Dienst
  /// danach in jedem Fall wieder.
  static Future<void> restore(String backupPath) async {
    final status = await ServiceControl.queryStatus();
    if (status == ServiceStatus.running) {
      final stopped = await ServiceControl.stop();
      if (!stopped) {
        throw const BackendCliException('Der Dienst konnte nicht gestoppt werden. Es wurde nichts verändert.');
      }
    }
    try {
      await _waitUntilStopped();
      await BackendCli.run(['restore', backupPath]);
    } finally {
      if (status != ServiceStatus.notInstalled) {
        await ServiceControl.start();
      }
    }
  }

  static Future<void> export(BackupEntry entry, String destinationPath) async {
    await File(entry.path).copy(destinationPath);
    final sidecar = File(entry.sidecarPath);
    if (await sidecar.exists()) {
      await sidecar.copy(destinationPath.replaceFirst(RegExp(r'\.db$'), '.json'));
    }
  }

  static Future<void> importFrom(String sourcePath) async {
    await BackendCli.run(['verify', sourcePath]);
    await restore(sourcePath);
  }

  static Future<void> _waitUntilStopped() async {
    for (var i = 0; i < 60; i++) {
      final status = await ServiceControl.queryStatus();
      if (status == ServiceStatus.stopped || status == ServiceStatus.notInstalled) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const BackendCliException('Der Dienst hat nicht rechtzeitig angehalten. Es wurde nichts verändert.');
  }
}
