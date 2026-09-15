import 'dart:io';

/// Reads/writes config.env as a flat KEY=VALUE map, preserving every comment
/// and blank line exactly as-is on save — only the matched key's own line
/// text changes. Values with '=' in them (e.g. ALLOWED_ORIGINS) are handled
/// by only splitting on the *first* '='.
class ConfigEnvFile {
  final Map<String, String> values;
  final List<String> _rawLines;

  ConfigEnvFile._(this.values, this._rawLines);

  static Future<ConfigEnvFile> load(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return ConfigEnvFile._({}, []);
    }
    final lines = await file.readAsLines();
    final values = <String, String>{};
    for (final line in lines) {
      final entry = _parseLine(line);
      if (entry != null) values[entry.key] = entry.value;
    }
    return ConfigEnvFile._(values, lines);
  }

  static MapEntry<String, String>? _parseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    final idx = trimmed.indexOf('=');
    if (idx == -1) return null;
    return MapEntry(trimmed.substring(0, idx).trim(), trimmed.substring(idx + 1).trim());
  }

  Future<void> save(String path, Map<String, String> updates) async {
    final remaining = Map<String, String>.from(updates);
    final newLines = <String>[];
    for (final line in _rawLines) {
      final entry = _parseLine(line);
      if (entry != null && remaining.containsKey(entry.key)) {
        newLines.add('${entry.key}=${remaining.remove(entry.key)}');
      } else {
        newLines.add(line);
      }
    }
    // Keys the file didn't already contain (shouldn't normally happen —
    // config.env.template already lists everything) get appended.
    for (final entry in remaining.entries) {
      newLines.add('${entry.key}=${entry.value}');
    }
    await File(path).writeAsString('${newLines.join('\n')}\n');
  }
}
