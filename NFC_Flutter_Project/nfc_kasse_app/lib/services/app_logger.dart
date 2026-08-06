import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the backend's level scale (`logging_config.py`'s `LEVEL_NAME_TO_INT`)
/// so a level picked in the UI means the same thing on both ends.
enum LogLevel {
  trace(5, 'TRACE'),
  debug(10, 'DEBUG'),
  info(20, 'INFO'),
  warning(30, 'WARNING'),
  error(40, 'ERROR'),
  fatal(50, 'FATAL');

  final int value;
  final String label;
  const LogLevel(this.value, this.label);

  static LogLevel fromLabel(String? label) => values.firstWhere(
        (l) => l.label == label?.toUpperCase(),
        orElse: () => LogLevel.info,
      );
}

/// One buffered log entry, in the shape `POST /api/logs/ingest` expects.
class BufferedLogEntry {
  final String ts;
  final String level;
  final String logger;
  final String message;
  final String? traceId;
  final String? exception;

  const BufferedLogEntry({
    required this.ts,
    required this.level,
    required this.logger,
    required this.message,
    this.traceId,
    this.exception,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'level': level,
        'logger': logger,
        'message': message,
        'trace_id': traceId,
        'exception': exception,
      };

  factory BufferedLogEntry.fromJson(Map<String, dynamic> j) => BufferedLogEntry(
        ts: j['ts'] as String,
        level: j['level'] as String,
        logger: j['logger'] as String,
        message: j['message'] as String,
        traceId: j['trace_id'] as String?,
        exception: j['exception'] as String?,
      );
}

/// Static logging facade — deliberately free of any Riverpod/Dio dependency
/// so it can be called from anywhere (the Dio interceptors themselves,
/// global error handlers, code that runs before `runApp()`).
///
/// Threshold filtering happens at the call site, not at display time: an
/// entry below [currentLevel] is never buffered, so raising the level later
/// cannot retroactively recover detail that was already discarded. Debugging
/// a specific device means raising its level *before* the interesting event,
/// not after.
class AppLogger {
  AppLogger._();

  static const int _maxBufferSize = 500;
  static const String _prefsKey = 'app_logger_buffer';

  /// The effective level — set by LoggingNotifier as
  /// `remoteOverride ?? localLevel` changes.
  static LogLevel currentLevel = LogLevel.info;

  /// Called whenever an ERROR/FATAL entry is buffered, so the shipping layer
  /// can debounce an out-of-band flush instead of waiting for the next
  /// scheduled rotation.
  static void Function()? onSevereLog;

  static final List<BufferedLogEntry> _buffer = [];
  static SharedPreferences? _prefs;

  static int get pendingCount => _buffer.length;

  static List<Map<String, dynamic>> pendingBatch(int limit) =>
      _buffer.take(limit).map((e) => e.toJson()).toList();

  /// Restores any entries that survived a process kill between app runs.
  /// Must be called once, early in `main()`, before the app starts logging.
  static Future<void> loadPersisted(SharedPreferences prefs) async {
    _prefs = prefs;
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _buffer
        ..clear()
        ..addAll(list.map((e) => BufferedLogEntry.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // Corrupt persisted buffer — start clean rather than repeatedly
      // failing to parse it on every future load.
      await prefs.remove(_prefsKey);
    }
  }

  /// Removes the first [count] entries (the ones a successful ship just
  /// accepted) from both the in-memory buffer and its persisted mirror.
  static void clearShipped(int count) {
    if (count <= 0) return;
    _buffer.removeRange(0, count.clamp(0, _buffer.length));
    unawaited(_persist());
  }

  static Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      _prefsKey,
      jsonEncode(_buffer.map((e) => e.toJson()).toList()),
    );
  }

  static void trace(String message, {String logger = 'app', String? traceId}) =>
      _log(LogLevel.trace, message, logger: logger, traceId: traceId);

  static void debug(String message, {String logger = 'app', String? traceId}) =>
      _log(LogLevel.debug, message, logger: logger, traceId: traceId);

  static void info(String message, {String logger = 'app', String? traceId}) =>
      _log(LogLevel.info, message, logger: logger, traceId: traceId);

  static void warning(
    String message, {
    String logger = 'app',
    String? traceId,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.warning, message,
          logger: logger, traceId: traceId, error: error, stackTrace: stackTrace);

  static void error(
    String message, {
    String logger = 'app',
    String? traceId,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.error, message,
          logger: logger, traceId: traceId, error: error, stackTrace: stackTrace);

  static void fatal(
    String message, {
    String logger = 'app',
    String? traceId,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.fatal, message,
          logger: logger, traceId: traceId, error: error, stackTrace: stackTrace);

  static void _log(
    LogLevel level,
    String message, {
    required String logger,
    String? traceId,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.value < currentLevel.value) return;

    if (kDebugMode) {
      debugPrint('[${level.label}] $logger: $message');
    }

    String? exceptionText;
    if (error != null || stackTrace != null) {
      exceptionText = [
        if (error != null) error.toString(),
        if (stackTrace != null) stackTrace.toString(),
      ].join('\n');
    }

    _buffer.add(BufferedLogEntry(
      ts: DateTime.now().toUtc().toIso8601String(),
      level: level.label,
      logger: logger,
      message: message,
      traceId: traceId,
      exception: exceptionText,
    ));
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }
    unawaited(_persist());

    if (level.value >= LogLevel.error.value) {
      onSevereLog?.call();
    }
  }
}
