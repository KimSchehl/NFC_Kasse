/// One entry returned by `GET /api/logs/query` — either a server-side log
/// line or a shipped client entry, distinguished by [origin].
class LogEntry {
  final String ts;
  final String level;
  final String logger;
  final String message;
  final String? traceId;
  final String origin;
  final String? deviceId;
  final int? userId;
  final String? username;
  final String? path;
  final String? method;
  final int? statusCode;
  final String? exception;

  const LogEntry({
    required this.ts,
    required this.level,
    required this.logger,
    required this.message,
    this.traceId,
    required this.origin,
    this.deviceId,
    this.userId,
    this.username,
    this.path,
    this.method,
    this.statusCode,
    this.exception,
  });

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        ts: j['ts'] as String,
        level: j['level'] as String,
        logger: j['logger'] as String,
        message: j['message'] as String,
        traceId: j['trace_id'] as String?,
        origin: j['origin'] as String? ?? 'server',
        deviceId: j['device_id'] as String?,
        userId: j['user_id'] as int?,
        username: j['username'] as String?,
        path: j['path'] as String?,
        method: j['method'] as String?,
        statusCode: j['status_code'] as int?,
        exception: j['exception'] as String?,
      );
}

class LogQueryResult {
  final List<LogEntry> items;
  final bool hasMore;

  const LogQueryResult({required this.items, required this.hasMore});

  factory LogQueryResult.fromJson(Map<String, dynamic> j) => LogQueryResult(
        items: (j['items'] as List)
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: j['has_more'] as bool,
      );
}

/// A device (or the synthetic `__server__` entry) known to the log system.
class LogDeviceInfo {
  final String deviceId;
  final String? label;
  final String? platform;
  final String? lastSeenAt;
  final String? forcedLevel;
  final bool online;

  const LogDeviceInfo({
    required this.deviceId,
    this.label,
    this.platform,
    this.lastSeenAt,
    this.forcedLevel,
    required this.online,
  });

  factory LogDeviceInfo.fromJson(Map<String, dynamic> j) => LogDeviceInfo(
        deviceId: j['device_id'] as String,
        label: j['label'] as String?,
        platform: j['platform'] as String?,
        lastSeenAt: j['last_seen_at'] as String?,
        forcedLevel: j['forced_level'] as String?,
        online: j['online'] as bool,
      );

  bool get isServer => deviceId == '__server__';

  String get displayLabel {
    if (isServer) return 'Server';
    if (label != null && label!.isNotEmpty) return label!;
    return deviceId;
  }
}
