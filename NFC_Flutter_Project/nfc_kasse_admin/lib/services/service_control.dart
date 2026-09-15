import 'dart:io';

import 'nfc_kasse_paths.dart';

enum ServiceStatus { running, stopped, notInstalled, unknown }

/// Controls the "NfcKasseBackend" Windows service via NfcKasseService.exe
/// (the WinSW wrapper the installer registers) and queries its state via the
/// native `sc.exe` — more reliable to parse than relying on WinSW's own
/// status output format.
class ServiceControl {
  static const _serviceName = 'NfcKasseBackend';

  static Future<ServiceStatus> queryStatus() async {
    try {
      final result = await Process.run('sc', ['query', _serviceName]);
      final out = (result.stdout as String? ?? '');
      if (result.exitCode != 0 || out.contains('1060')) {
        // 1060 = ERROR_SERVICE_DOES_NOT_EXIST
        return ServiceStatus.notInstalled;
      }
      if (out.contains('RUNNING')) return ServiceStatus.running;
      if (out.contains('STOPPED')) return ServiceStatus.stopped;
      return ServiceStatus.unknown;
    } catch (_) {
      return ServiceStatus.unknown;
    }
  }

  static Future<bool> start() => _run('start');
  static Future<bool> stop() => _run('stop');

  static Future<bool> restart() async {
    final stopped = await stop();
    if (!stopped) return false;
    return start();
  }

  static Future<bool> _run(String verb) async {
    try {
      final result = await Process.run(
        NfcKassePaths.serviceExe,
        [verb],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
