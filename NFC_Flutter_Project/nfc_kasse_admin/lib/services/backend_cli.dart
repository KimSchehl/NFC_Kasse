import 'dart:convert';
import 'dart:io';

import 'nfc_kasse_paths.dart';

class BackendCliException implements Exception {
  final String message;
  final int? exitCode;

  const BackendCliException(this.message, {this.exitCode});

  @override
  String toString() => message;
}

/// Ruft einen Befehl von NfcKasseBackend.exe auf (Sicherungen: db_backup.py,
/// Feste/Vorlagen/CSV: admin_cli.py). Jeder Befehl antwortet mit genau einer
/// JSON-Zeile; "ok": false wird hier zur Exception mit der deutschen
/// Fehlermeldung des Backends.
class BackendCli {
  BackendCli._();

  /// [stdin] geht als eine Zeile an den Befehl — für Passwörter, die
  /// nicht in der (für andere Prozesse sichtbaren) Befehlszeile stehen sollen.
  static Future<Map<String, dynamic>> run(List<String> args, {String? stdin}) async {
    final String stdout;
    final int exitCode;
    try {
      if (stdin == null) {
        final result = await Process.run(
          NfcKassePaths.backendExe,
          args,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        stdout = result.stdout as String;
        exitCode = result.exitCode;
      } else {
        final process = await Process.start(NfcKassePaths.backendExe, args);
        process.stdin.writeln(stdin);
        await process.stdin.close();
        final out = process.stdout.transform(utf8.decoder).join();
        await process.stderr.drain<void>();
        stdout = await out;
        exitCode = await process.exitCode;
      }
    } on ProcessException {
      throw const BackendCliException('NfcKasseBackend.exe wurde nicht gefunden.');
    }

    Map<String, dynamic>? json;
    final lines = stdout.trim().split('\n');
    try {
      json = jsonDecode(lines.last) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }
    if (json == null) {
      throw BackendCliException(
        'Unerwartete Antwort von NfcKasseBackend.exe (Code $exitCode).',
        exitCode: exitCode,
      );
    }
    if (json['ok'] != true) {
      throw BackendCliException(
        json['error'] as String? ?? 'Unbekannter Fehler.',
        exitCode: exitCode,
      );
    }
    return json;
  }
}
