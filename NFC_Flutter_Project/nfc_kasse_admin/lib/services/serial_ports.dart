import 'dart:convert';
import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

class SerialPortInfo {
  final String port;
  final String? description;

  const SerialPortInfo(this.port, this.description);

  String get label => description == null ? port : '$port  ·  $description';
}

/// COM ports present on this PC, with Device Manager names where available
/// (e.g. "COM4 · USB-SERIAL CH340"), so the printer can be picked without
/// opening Device Manager.
class SerialPorts {
  SerialPorts._();

  static Future<List<SerialPortInfo>> list() async {
    final described = await _describedPorts();
    final ports = {..._registryPorts(), ...described.keys}.toList()
      ..sort((a, b) => _comNumber(a).compareTo(_comNumber(b)));
    return [for (final p in ports) SerialPortInfo(p, described[p])];
  }

  static Set<String> _registryPorts() {
    try {
      final key = Registry.openPath(
        RegistryHive.localMachine,
        path: r'HARDWARE\DEVICEMAP\SERIALCOMM',
      );
      try {
        return {for (final v in key.values) v.data.toString()};
      } finally {
        key.close();
      }
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, String>> _describedPorts() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
              r"Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match '\(COM\d+\)' } | "
              r"ForEach-Object { $_.Name }",
        ],
        stdoutEncoding: utf8,
      ).timeout(const Duration(seconds: 10));

      final described = <String, String>{};
      for (final line in (result.stdout as String).split('\n')) {
        final match = RegExp(r'^(.*)\((COM\d+)\)\s*$').firstMatch(line.trim());
        if (match != null) described[match.group(2)!] = match.group(1)!.trim();
      }
      return described;
    } catch (_) {
      return {};
    }
  }

  static int _comNumber(String port) =>
      int.tryParse(port.replaceFirst(RegExp('^COM', caseSensitive: false), '')) ?? 0;
}
