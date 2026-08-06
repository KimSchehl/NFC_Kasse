import '../models/log_models.dart';
import 'api_client.dart';

class LogsService {
  final ApiClient _client;
  LogsService(this._client);

  /// Ships a batch of already-JSON-shaped buffered entries (see
  /// `AppLogger.pendingBatch`) to the server. Returns how many were
  /// accepted so the caller can trim exactly that many off the local buffer
  /// (a partial batch that fails mid-flight is retried in full next time).
  Future<int> ingest(String deviceId, List<Map<String, dynamic>> entries) async {
    final resp = await _client.dio.post(
      '/api/logs/ingest',
      data: {
        'device_id': deviceId,
        'entries': entries,
      },
    );
    return resp.data['accepted'] as int;
  }

  /// Requires `logs.view`.
  Future<LogQueryResult> query({
    String? level,
    String? origin,
    String? deviceId,
    String? traceId,
    String? logger,
    String? q,
    String? since,
    String? until,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (level != null) params['level'] = level;
    if (origin != null) params['origin'] = origin;
    if (deviceId != null) params['device_id'] = deviceId;
    if (traceId != null && traceId.isNotEmpty) params['trace_id'] = traceId;
    if (logger != null && logger.isNotEmpty) params['logger'] = logger;
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (since != null) params['since'] = since;
    if (until != null) params['until'] = until;

    final resp = await _client.dio.get('/api/logs/query', queryParameters: params);
    return LogQueryResult.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Requires `logs.configure`.
  Future<List<LogDeviceInfo>> getDevices() async {
    final resp = await _client.dio.get('/api/logs/devices');
    return (resp.data as List)
        .map((j) => LogDeviceInfo.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Requires `logs.configure`. [level] null clears the forced override.
  Future<LogDeviceInfo> setDeviceLevel(String deviceId, String? level) async {
    final resp = await _client.dio.put(
      '/api/logs/devices/$deviceId/level',
      data: {'level': level},
    );
    return LogDeviceInfo.fromJson(resp.data as Map<String, dynamic>);
  }
}
