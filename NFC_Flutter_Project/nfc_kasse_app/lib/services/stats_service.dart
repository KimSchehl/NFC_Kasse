import '../models/stats_models.dart';
import 'api_client.dart';

/// Fetches revenue summaries and transaction lists, and manages stats
/// periods (Tagesabschluss). The CSV export for accounting is in the admin
/// tool, not here.
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

  Future<RevenueStats> getRevenue({String? periodIds, String? from, String? to}) async {
    final params = <String, dynamic>{};
    if (periodIds != null) params['period_ids'] = periodIds;
    if (from != null) params['period_start'] = from;
    if (to != null) params['period_end'] = to;
    final resp = await _client.dio.get('/api/stats/revenue', queryParameters: params);
    return RevenueStats.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<TransactionItem>> getTransactions({
    String? periodIds,
    String? from,
    String? to,
    String? customerName,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (periodIds != null) params['period_ids'] = periodIds;
    if (from != null) params['period_start'] = from;
    if (to != null) params['period_end'] = to;
    if (customerName != null && customerName.isNotEmpty) params['customer_name'] = customerName;
    final resp = await _client.dio.get('/api/stats/transactions', queryParameters: params);
    return (resp.data['items'] as List)
        .map((j) => TransactionItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
