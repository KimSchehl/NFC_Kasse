import '../models/stats_models.dart';
import 'api_client.dart';

/// Fetches revenue summaries, transaction lists, export URLs, and manages
/// stats periods (Tagesabschluss).
class StatsService {
  final ApiClient _client;
  StatsService(this._client);

  Future<List<StatsPeriod>> getPeriods() async {
    final resp = await _client.dio.get('/api/stats/periods');
    return (resp.data as List)
        .map((j) => StatsPeriod.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Closes the current open period and opens a new one with [label].
  Future<StatsPeriod> closePeriod(String label) async {
    final resp = await _client.dio.post(
      '/api/stats/periods/close',
      data: {'label': label},
    );
    return StatsPeriod.fromJson(
      resp.data['new_period'] as Map<String, dynamic>,
    );
  }

  Future<RevenueStats> getRevenue({int? periodId, String? from, String? to}) async {
    final params = <String, dynamic>{};
    if (periodId != null) params['period_id'] = periodId;
    if (from != null) params['period_start'] = from;
    if (to != null) params['period_end'] = to;
    final resp = await _client.dio.get('/api/stats/revenue', queryParameters: params);
    return RevenueStats.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<TransactionItem>> getTransactions({
    int? periodId,
    String? from,
    String? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (periodId != null) params['period_id'] = periodId;
    if (from != null) params['period_start'] = from;
    if (to != null) params['period_end'] = to;
    final resp = await _client.dio.get('/api/stats/transactions', queryParameters: params);
    return (resp.data['items'] as List)
        .map((j) => TransactionItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  String exportUrl({int? periodId}) {
    final base = '${_client.dio.options.baseUrl}/api/stats/export';
    return periodId != null ? '$base?period_id=$periodId' : base;
  }
}
