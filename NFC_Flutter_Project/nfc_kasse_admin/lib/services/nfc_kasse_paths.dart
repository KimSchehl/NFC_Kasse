import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Resolves where NFC-Kasse is installed. Mirrors the constants baked into
/// packaging/innosetup/nfc_kasse_installer.iss: same AppId (for the registry
/// lookup), same default {autopf}\NFC-Kasse, same fixed {commonappdata}\NFC-Kasse
/// (that one is never user-selectable during setup, unlike the program dir).
class NfcKassePaths {
  NfcKassePaths._();

  static const _appId = '{2EF18757-6135-4143-991F-DA4D728CEE16}';
  static const _defaultInstallDir = r'C:\Program Files\NFC-Kasse';

  /// Fixed — the installer never lets the user change this one.
  static const String dataDir = r'C:\ProgramData\NFC-Kasse';

  static String? _cachedInstallDir;

  /// The folder containing NfcKasseService.exe/NfcKasseBackend.exe. Usually
  /// the Inno Setup default, but the installer's directory page does let a
  /// user pick somewhere else — fall back to the same uninstall-registry key
  /// the installer's own [Code] section reads (InstallLocation) if the
  /// default isn't there.
  static String get installDir {
    final cached = _cachedInstallDir;
    if (cached != null) return cached;

    if (File('$_defaultInstallDir\\NfcKasseService.exe').existsSync()) {
      return _cachedInstallDir = _defaultInstallDir;
    }

    final fromRegistry = _readInstallLocation();
    return _cachedInstallDir = fromRegistry ?? _defaultInstallDir;
  }

  static String? _readInstallLocation() {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: '${r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'}\\$_appId',
      );
      final value = key.getValueAsString('InstallLocation');
      key.close();
      if (value == null || value.isEmpty) return null;
      return value.endsWith(r'\') ? value.substring(0, value.length - 1) : value;
    } catch (_) {
      return null;
    }
  }

  static String get serviceExe => '$installDir\\NfcKasseService.exe';
  static String get backendExe => '$installDir\\NfcKasseBackend.exe';
  static String get configEnvPath => '$dataDir\\config.env';
  static String get bonYamlPath => '$dataDir\\bon.yaml';
  static String get logsDir => '$dataDir\\logs';
}
